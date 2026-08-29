# ScoopBrew contributor guide

## Project overview

ScoopBrew provides a PowerShell implementation of Homebrew's `brew` command
surface on Windows. It delegates package operations to Scoop rather than
reimplementing Scoop's package-management behavior.

## Repository layout

- `bin/brew.ps1` is the command-line entry point; `bin/brew.cmd` is its
  `cmd.exe` wrapper.
- `lib/ScoopBrew.psm1` contains shared discovery, package-resolution, output,
  and argument-handling helpers.
- `commands/brew-<command>.ps1` contains one command implementation per file.
- `lib/tap-map.json` maps known tap repositories to their Scoop bucket names.
- `test/ScoopBrew.Tests.ps1` is the Pester test suite.

## Implementation conventions

- Target Windows PowerShell 5.1 as well as PowerShell 7; do not rely on
  PowerShell 7-only syntax or APIs.
- Keep command scripts thin and put reusable behavior in `lib/ScoopBrew.psm1`.
- Preserve the command-file documentation headers: `# Usage:`, `# Summary:`,
  and, when needed, `# Help:`. Help and command discovery read these headers.
- Route state-changing package operations through the Scoop executable. Reading
  Scoop's documented on-disk manifest and export formats is acceptable.
- Prefer `-LiteralPath` for filesystem paths and preserve existing UTF-8
  no-BOM output behavior when writing files.
- Do not add module dependencies without a clear compatibility reason.

## Testing

Run the Pester suite from a Windows host with Scoop and Pester available:

```powershell
Invoke-Pester -Script 'test'
```

The suite is designed to be read-only with respect to Scoop installs and
buckets. It does inspect the local Scoop installation, so do not treat it as
portable to non-Windows or Scoop-free environments.

## Change checklist

- Update `README.md` when the public command surface, behavior, requirements,
  or limitations change.
- Add or update focused Pester coverage for observable behavior changes.
- Keep the repository free of generated Scoop state, installed-package data,
  and machine-specific paths.
