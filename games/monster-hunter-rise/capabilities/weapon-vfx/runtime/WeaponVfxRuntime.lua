-- MIT licensed reference runtime. The project supplies profile, adapter and reporter.
local Runtime = {}

local VALID_TIERS = { normal = true, finisher = true, signature = true }

local function integer(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function validate(profile)
    if type(profile) ~= "table" or profile.schema_version ~= 1 then
        return false, "unsupported profile schema"
    end
    if profile.enabled ~= true or profile.network_sync ~= false then
        return false, "profile must be enabled and local-only"
    end
    if type(profile.weapon) ~= "table"
        or not integer(profile.weapon.type_id, 0, 255)
        or type(profile.weapon.managed_type) ~= "string" then
        return false, "invalid weapon identity"
    end
    if type(profile.action) ~= "table"
        or not integer(profile.action.bank, 0, 9999)
        or not integer(profile.action.default_whiff_trigger_frame, 0, 30)
        or not integer(profile.action.default_whiff_max_late_frames, 0, 15)
        or not integer(profile.action.hit_grace_ticks, 0, 30) then
        return false, "invalid action contract"
    end
    if type(profile.effects) ~= "table"
        or not integer(profile.effects.container_id, 1, 999999)
        or type(profile.effects.baseline_effect_ids) ~= "table"
        or #profile.effects.baseline_effect_ids ~= 2
        or type(profile.effects.persistent_effect_ids) ~= "table" then
        return false, "invalid effect contract"
    end
    if type(profile.recipes) ~= "table" or #profile.recipes == 0 then
        return false, "missing recipes"
    end

    local persistent = {}
    for _, effect_id in ipairs(profile.effects.persistent_effect_ids) do
        if not integer(effect_id, 1, 999999) or persistent[effect_id] then
            return false, "invalid persistent effect set"
        end
        persistent[effect_id] = true
    end
    local recipes = {}
    for _, recipe in ipairs(profile.recipes) do
        if type(recipe) ~= "table"
            or not integer(recipe.action_id, 1, 999999)
            or type(recipe.name) ~= "string" or recipe.name == ""
            or VALID_TIERS[recipe.tier] ~= true
            or not integer(recipe.whiff_effect_id, 1, 999999)
            or not integer(recipe.hit_effect_id, 1, 999999)
            or not integer(recipe.max_hit_effects, 1, 32)
            or (recipe.whiff_mode ~= "one_shot" and recipe.whiff_mode ~= "instance") then
            return false, "invalid recipe"
        end
        if persistent[recipe.hit_effect_id]
            or (recipe.whiff_mode == "instance" and not persistent[recipe.whiff_effect_id])
            or (recipe.whiff_mode == "one_shot" and persistent[recipe.whiff_effect_id])
            or (recipe.finish_effect_id ~= nil and persistent[recipe.finish_effect_id]) then
            return false, "recipe lifecycle mismatch"
        end
        local key = tostring(profile.action.bank) .. ":" .. tostring(recipe.action_id)
        if recipes[key] ~= nil then return false, "duplicate recipe " .. key end
        recipes[key] = recipe
    end
    return true, { recipes = recipes, persistent = persistent }
end

local function require_adapter(adapter)
    local members = {
        "register_update", "register_hit", "register_reset", "get_action_context",
        "authorize_hit", "effect_exists", "dispatch_effect",
        "create_effect_instance", "release_effect_instance",
    }
    for _, name in ipairs(members) do
        if type(adapter[name]) ~= "function" then return false, "adapter missing " .. name end
    end
    return true
end

function Runtime.start(profile, adapter, reporter)
    local valid, compiled = validate(profile)
    if not valid then return nil, compiled end
    local adapter_valid, adapter_error = require_adapter(adapter)
    if not adapter_valid then return nil, adapter_error end
    reporter = type(reporter) == "function" and reporter or function() end

    local state = {
        active = true,
        tick = 0,
        current_key = nil,
        current_serial = 0,
        current_recipe = nil,
        current_eligible = false,
        current_hit_count = 0,
        current_frame = nil,
        last_frame = nil,
        last_eligible_tick = nil,
        last_eligible_serial = nil,
        last_eligible_recipe = nil,
        last_whiff_serial = -1,
        active_instances = {},
        active_instance_recipe = nil,
        counters = {
            whiff_attempts = 0, whiff_successes = 0,
            hit_attempts = 0, hit_successes = 0,
            instance_dispatches = 0, instance_releases = 0,
            instance_release_failures = 0,
        },
        last_error = nil,
        last_hit_rejection = nil,
    }

    local function report(event)
        reporter({ event = event, profile_id = profile.profile_id, state = state })
    end

    local function effects_ready(effect_id)
        local container = profile.effects.container_id
        for _, baseline in ipairs(profile.effects.baseline_effect_ids) do
            if adapter.effect_exists(container, baseline) ~= true then
                state.last_error = "baseline effect unavailable: " .. tostring(baseline)
                return false
            end
        end
        if adapter.effect_exists(container, effect_id) ~= true then
            state.last_error = "effect unavailable: " .. tostring(effect_id)
            return false
        end
        return true
    end

    local function dispatch(effect_id, role, recipe)
        if not effects_ready(effect_id) then report(role .. "-blocked") return false end
        local ok, error_message = adapter.dispatch_effect(
            profile.effects.container_id, effect_id, false)
        if ok ~= true then
            state.last_error = error_message or "dispatch returned non-true"
            report(role .. "-failed")
            return false
        end
        state.last_error = nil
        report(role .. "-dispatched")
        return true
    end

    local release_instances
    release_instances = function(reason)
        if #state.active_instances == 0 then return true end
        local released, failed = 0, 0
        local recipe = state.active_instance_recipe
        for _, instance in ipairs(state.active_instances) do
            if adapter.release_effect_instance(instance) == true then
                released = released + 1
            else
                failed = failed + 1
            end
        end
        state.active_instances = {}
        state.active_instance_recipe = nil
        state.counters.instance_releases = state.counters.instance_releases + released
        state.counters.instance_release_failures = state.counters.instance_release_failures + failed
        if recipe and recipe.finish_effect_id then
            dispatch(recipe.finish_effect_id, "finish", recipe)
        end
        state.last_error = failed == 0 and nil or ("instance release failures=" .. tostring(failed))
        report("instances-released:" .. reason)
        return failed == 0
    end

    local function dispatch_instance(effect_id, recipe)
        if not effects_ready(effect_id) then report("instance-blocked") return false end
        release_instances("replace-before-dispatch")
        local instance, error_message = adapter.create_effect_instance(
            profile.effects.container_id, effect_id, false)
        if instance == nil or instance == false then
            state.last_error = error_message or "instance creation returned nil"
            report("instance-failed")
            return false
        end
        state.active_instances[1] = instance
        state.active_instance_recipe = recipe
        state.counters.instance_dispatches = state.counters.instance_dispatches + 1
        state.last_error = nil
        report("instance-dispatched")
        return true
    end

    local function eligible_hit_recipe()
        if state.current_eligible then return state.current_serial, state.current_recipe end
        if state.last_eligible_tick ~= nil
            and state.tick - state.last_eligible_tick <= profile.action.hit_grace_ticks then
            return state.last_eligible_serial, state.last_eligible_recipe
        end
        return nil, nil
    end

    local function on_hit(raw_hit)
        if not state.active then return end
        local _, recipe = eligible_hit_recipe()
        if recipe == nil then state.last_hit_rejection = "action-not-current-or-recent" report("hit-rejected") return end
        if state.current_hit_count >= recipe.max_hit_effects then
            state.last_hit_rejection = "action-hit-limit-reached" report("hit-rejected") return
        end
        local authorized, reason, observation = adapter.authorize_hit(raw_hit, profile)
        state.last_hit_observation = observation
        if authorized ~= true then state.last_hit_rejection = reason or "unauthorized-hit" report("hit-rejected") return end
        state.counters.hit_attempts = state.counters.hit_attempts + 1
        if dispatch(recipe.hit_effect_id, "hit", recipe) then
            state.current_hit_count = state.current_hit_count + 1
            state.counters.hit_successes = state.counters.hit_successes + 1
        end
    end

    local function on_update()
        if not state.active then return end
        state.tick = state.tick + 1
        local context = adapter.get_action_context()
        if type(context) ~= "table" then state.last_error = "missing action context" report("update-blocked") return end
        local recipe_key = tostring(context.action_bank) .. ":" .. tostring(context.action_id)
        local recipe = compiled.recipes[recipe_key]
        local eligible = context.weapon_type == profile.weapon.type_id
            and context.action_bank == profile.action.bank
            and recipe ~= nil and type(context.action_frame) == "number"
        local action_key = tostring(context.weapon_type) .. ":" .. recipe_key
        local frame = context.action_frame and math.floor(context.action_frame) or nil
        local changed = action_key ~= state.current_key
        local restarted = eligible and not changed and state.last_frame ~= nil and frame < state.last_frame
        if changed or restarted then
            release_instances(changed and "action-changed" or "action-restarted")
            state.current_key = action_key
            if eligible then
                state.current_serial = state.current_serial + 1
                state.current_hit_count = 0
                state.last_whiff_serial = -1
            end
        end
        state.current_eligible = eligible
        state.current_recipe = eligible and recipe or nil
        state.current_frame = frame
        if eligible then
            state.last_eligible_tick = state.tick
            state.last_eligible_serial = state.current_serial
            state.last_eligible_recipe = recipe
        end
        local previous = (changed or restarted) and -1 or state.last_frame
        local trigger = recipe and (recipe.whiff_trigger_frame or profile.action.default_whiff_trigger_frame)
        local late = recipe and (recipe.whiff_max_late_frames or profile.action.default_whiff_max_late_frames)
        local crossed = eligible and previous ~= nil and previous < trigger
            and frame >= trigger and frame <= trigger + late
        state.last_frame = frame
        if crossed and state.last_whiff_serial ~= state.current_serial then
            state.last_whiff_serial = state.current_serial
            state.counters.whiff_attempts = state.counters.whiff_attempts + 1
            local ok
            if recipe.whiff_mode == "instance" then
                ok = dispatch_instance(recipe.whiff_effect_id, recipe)
            else
                ok = dispatch(recipe.whiff_effect_id, "whiff", recipe)
            end
            if ok then state.counters.whiff_successes = state.counters.whiff_successes + 1 end
        end
        report("update")
    end

    local function on_reset()
        release_instances("script-reset")
        state.active = false
        state.current_eligible = false
        state.current_recipe = nil
        state.last_eligible_tick = nil
        state.last_eligible_serial = nil
        state.last_eligible_recipe = nil
        report("script-reset")
    end

    adapter.register_update(on_update)
    adapter.register_hit(on_hit)
    adapter.register_reset(on_reset)
    report("started")
    return state, nil
end

return Runtime
