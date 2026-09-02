-- Steam 16.0.2.0 reference adapter. Revalidate the reflection contract after game updates.
local Adapter = {}

local HIT_SHAPE = {
    owner_type = "snow.enemy.EnemyCharacterBase",
    name = "afterCalcDamage_DamageSide",
    is_static = false,
    parameter_types = { "snow.hit.DamageFlowInfoBase", "snow.DamageReceiver.HitInfo" },
    return_type = "System.Void",
}

local function safe(fn)
    local ok, value = pcall(fn)
    if ok then return value, nil end
    return nil, tostring(value)
end

local function number_call(fn)
    local value = safe(fn)
    return tonumber(value)
end

local function type_name(type_definition)
    if type_definition == nil then return nil end
    return safe(function() return type_definition:get_full_name() end)
        or safe(function() return type_definition:get_name() end)
end

local function method_matches(method)
    if method == nil or safe(function() return method:get_name() end) ~= HIT_SHAPE.name then return false end
    if safe(function() return method:is_static() end) ~= HIT_SHAPE.is_static then return false end
    if type_name(safe(function() return method:get_return_type() end)) ~= HIT_SHAPE.return_type then return false end
    local parameters = safe(function() return method:get_param_types() end)
    if parameters == nil or #parameters ~= #HIT_SHAPE.parameter_types then return false end
    for index, expected in ipairs(HIT_SHAPE.parameter_types) do
        if type_name(parameters[index]) ~= expected then return false end
        if safe(function() return parameters[index]:is_by_ref() end) == true then return false end
    end
    return true
end

local function unique_hit_method()
    local owner = safe(function() return sdk.find_type_definition(HIT_SHAPE.owner_type) end)
    if owner == nil then return nil, "missing hit owner type" end
    local methods = safe(function() return owner:get_methods() end)
    if methods == nil then return nil, "cannot enumerate hit owner methods" end
    local matches = {}
    for _, method in ipairs(methods) do
        if method_matches(method) then matches[#matches + 1] = method end
    end
    if #matches ~= 1 then return nil, "exact hit method count=" .. tostring(#matches) end
    return matches[1], nil
end

local function is_a(value, expected)
    if value == nil or expected == nil then return false end
    local actual = safe(function() return value:get_type_definition() end)
    return actual ~= nil and safe(function() return actual:is_a(expected) end) == true
end

function Adapter.create(profile, yun)
    if type(profile) ~= "table" or type(yun) ~= "table" then
        return nil, "profile and yun_modules are required"
    end
    local required = {
        "get_master_player", "get_master_player_index", "get_weapon_type",
        "get_action_id", "get_action_bank_id", "get_now_action_frame",
        "is_effect_exists", "set_effect", "set_effect_with_instance",
    }
    for _, name in ipairs(required) do
        if type(yun[name]) ~= "function" then return nil, "yun_modules missing " .. name end
    end

    local weapon_type = safe(function() return sdk.find_type_definition(profile.weapon.managed_type) end)
    local damage_type = safe(function() return sdk.find_type_definition("snow.hit.DamageFlowInfoBase") end)
    local hit_info_type = safe(function() return sdk.find_type_definition("snow.DamageReceiver.HitInfo") end)
    local enemy_type = safe(function() return sdk.find_type_definition(HIT_SHAPE.owner_type) end)
    local hit_method, hit_error = unique_hit_method()
    if weapon_type == nil or damage_type == nil or hit_info_type == nil or enemy_type == nil or hit_method == nil then
        return nil, hit_error or "required TDB reflection contract unavailable"
    end

    local adapter = {}
    function adapter.register_update(callback)
        re.on_pre_application_entry("UpdateScene", callback)
    end
    function adapter.register_hit(callback)
        sdk.hook(hit_method, function(args) callback(args) end)
    end
    function adapter.register_reset(callback)
        re.on_script_reset(callback)
    end
    function adapter.get_action_context()
        return {
            weapon_type = number_call(function() return yun.get_weapon_type() end),
            action_bank = number_call(function() return yun.get_action_bank_id() end),
            action_id = number_call(function() return yun.get_action_id() end),
            action_frame = number_call(function() return yun.get_now_action_frame() end),
        }
    end
    function adapter.effect_exists(container_id, effect_id)
        return safe(function() return yun.is_effect_exists(container_id, effect_id) end) == true
    end
    function adapter.dispatch_effect(container_id, effect_id, sync)
        if sync ~= false then return false, "network effect dispatch is forbidden" end
        local result, call_error = safe(function() return yun.set_effect(container_id, effect_id, false) end)
        return result == true, call_error
    end
    function adapter.create_effect_instance(container_id, effect_id, sync)
        if sync ~= false then return nil, "network effect dispatch is forbidden" end
        return safe(function() return yun.set_effect_with_instance(container_id, effect_id, false) end)
    end
    function adapter.release_effect_instance(instance)
        local released = safe(function()
            instance:finishAll()
            instance:force_release()
            return true
        end)
        return released == true
    end
    function adapter.authorize_hit(args, current_profile)
        local enemy = sdk.to_managed_object(args[2])
        local damage = sdk.to_managed_object(args[3])
        local hit_info = sdk.to_managed_object(args[4])
        local player = safe(function() return yun.get_master_player() end)
        local player_index = number_call(function() return yun.get_master_player_index() end)
        local attacker_id = number_call(function() return damage:get_AttackerID() end)
        local damage_weapon_type = number_call(function() return damage:get_WeaponType() end)
        local observation = {
            player_index = player_index,
            attacker_id = attacker_id,
            damage_weapon_type = damage_weapon_type,
        }
        if not is_a(enemy, enemy_type) then return false, "enemy-type-mismatch", observation end
        if not is_a(damage, damage_type) then return false, "damage-type-mismatch", observation end
        if not is_a(hit_info, hit_info_type) then return false, "hit-info-type-mismatch", observation end
        if not is_a(player, weapon_type) then return false, "master-player-weapon-type-mismatch", observation end
        if player_index == nil or attacker_id == nil or damage_weapon_type == nil then
            return false, "hit-authentication-unavailable", observation
        end
        if attacker_id ~= player_index then return false, "attacker-id-mismatch", observation end
        if damage_weapon_type ~= current_profile.weapon.type_id then
            return false, "damage-weapon-type-mismatch", observation
        end
        if number_call(function() return yun.get_weapon_type() end) ~= current_profile.weapon.type_id then
            return false, "current-weapon-type-mismatch", observation
        end
        return true, nil, observation
    end
    return adapter, nil
end

return Adapter
