# game-modding-toolkit

A distributable toolkit for game mod development, validation, installation, diagnostics, and publishing. The tools run independently in PowerShell 7 and do not require Codex or Skills.

## Capabilities

- [Steam Workshop publishing](capabilities/publishing/steam-workshop/README.md): read-only preflight, remote identity checks, preview protection, one-shot upload state machine, and evidence capture.
- Reserved categories: `packaging`, `installing`, `validation`, and `diagnostics`.

## Supported games

- [The Binding of Isaac: Rebirth](games/the-binding-of-isaac/README.md): Windows GUI adapter for the bundled `ModUploader.exe`. The Chinese guide is the canonical detailed documentation.

The first release officially supports Windows and PowerShell 7. Other games may reuse the generic capability after implementing and testing their own adapter.

## Quick start

```powershell
pwsh ./capabilities/publishing/steam-workshop/Invoke-WorkshopRelease.ps1 `
  -ProjectProfile ./games/the-binding-of-isaac/examples/project-profile.example.json
```

The command is read-only by default. It changes a Workshop item only when `-Publish` and change notes are supplied explicitly.

## Contributing and license

Put reusable capabilities under `capabilities/<capability>/` and game-specific code under `games/<game>/`. Public examples must not contain personal paths, credentials, or real Workshop IDs.

Licensed under the [MIT License](LICENSE).

