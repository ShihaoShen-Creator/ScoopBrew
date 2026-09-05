# ScoopBrew

The Homebrew command surface for Windows, backed by [Scoop](https://scoop.sh).

`brew` here is not Homebrew's Ruby implementation. It is a PowerShell CLI that
accepts Homebrew command names, options and output conventions, and delegates
every package operation to Scoop. Homebrew's macOS/Linux install engine
(Cellar, kegs, bottles, `rpath`, `dyld`, source builds) has no Windows
counterpart, so the engine is Scoop's and this layer only speaks `brew`.

## Requirements & Installation

| --- | --- |
| Windows | 10 or later |
| PowerShell | 5.1 or 7.x (no module dependencies) |
| Scoop | installed and at least one bucket added |
| git | required for `brew tap` and `brew update` |

Install Scoop first:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
```

Then: 
```powershell
scoop bucket add shihao https://github.com/ShihaoShen-Creator/ScoopBucket
scoop install scoopbrew # or: scoop install shihao/scoopbrew
```

## Usage

```cmd
bin\brew.cmd install git
bin\brew.cmd list
```

Or put `bin` and Scoop's shim directory on `PATH` once:

```powershell
[Environment]::SetEnvironmentVariable('Path', $env:Path + ';path\to\scoopbrew\bin;' + (Join-Path $env:USERPROFILE 'scoop\shims'), 'User')
```

Then open a new terminal and run `brew doctor`, which checks this setup and
reports what is missing.

## How it maps

Homebrew and Scoop solve the same problem with different vocabulary:

| Homebrew                  | Scoop                       |
|---|---|
| tap                       | bucket                      |
| formula, cask             | app (`extras` bucket for GUI apps) |
| Cellar, keg, `opt/` links | `apps\<name>\current` plus shims |
| `brew upgrade`            | `scoop update`              |
| `brew outdated`           | manifest version comparison |
| `brew pin` / `unpin`      | `scoop hold` / `scoop unhold` |
| `brew tab`                | `apps\<name>\<version>\install.json` |
| `brew bundle`             | `scoop export` / `scoop import` |
| `brew doctor`             | `scoop checkup`             |
| `brew --prefix`           | Scoop root, `scoop prefix`  |

Tap-qualified names are accepted too: `brew install user/tap/app` adds the
tap's bucket first when it is missing, then installs `tap/app`.

### Tap names and the tap map

Buckets are stored under stable lowercase names. `lib/tap-map.json` pins
GitHub repositories to local shortnames (`"Owner/Repo": "shortname"`), and
lookups ignore case. Every tap reference accepts three spellings:

- `brew tap ShihaoShen-Creator/ScoopBucket` — the full repository
- `brew tap ScoopBucket` — the repository name alone
- `brew tap shihao` — the mapped shortname

All three add the bucket `shihao`. A `user/repo` the map does not list is
added as `owner-repo` in lowercase, so unmapped taps still get a stable
local name. Point `SCOOPBREW_TAP_MAP` at another JSON file to override the
bundled map.

Two layers of data are read directly rather than through Scoop's PowerShell
functions, deliberately: bucket manifests (`buckets\<name>\**\*.json`) and
`scoop export`. Both are documented on-disk formats, whereas Scoop's internal
function names have changed across releases, so depending on them would make
this CLI break on a Scoop update. Everything that *changes* state goes through
the `scoop` executable itself; no download, hash, shim, persist or shortcut
logic is reimplemented here.

### Commands

Implemented, with the Scoop operation behind each:

`install` `uninstall` `reinstall` `upgrade` `fetch` `outdated` `update`
`list` `search` `info` `cat` `deps` `uses` `missing` `leaves` `home` `source`
`desc` `options` `tab` `log` `which` `which-formula` `pin` `unpin`
`tap` `untap` `tap-info` `--taps` `--repository` `--prefix` `--cellar`
`--caskroom` `--cache` `config` `doctor` `bundle` `exec` `alias` `unalias`
`command` `commands` `developer` `docs` `help` `--version`

Homebrew's internal aliases work with the same meaning, including the one that
reads ambiguously: `brew up` is `update` (refresh definitions), while
`brew upgrade` installs newer versions. List them with
`brew commands --include-aliases`: `ls`, `rm`, `remove`, `abv`, `dr`, `-S`,
`x`, `ln`, `instal`, `uninstal`, `homepage`, `--repo`, `--config`, `lc`, `tc`.

Not implemented, each with a reason printed on use: Homebrew's own release and
CI tooling (`bottle`, `test-bot`, `pr-pull`, `typecheck`, `style`, `tests`,
`lgtm`, every `generate-*`, `vendor-gems`), macOS/Linux-specific machinery
(`link`, `unlink`, `sandbox-exec`, `shellenv`, `linkage`, `services`), Homebrew
data pipelines (`analytics`, `vulns`, `trust`, `readall`, `mcp-server`), and the
language version-manager syncs. Run the command to see its explanation.

### Known limits

- **`brew autoremove` cannot work.** Scoop's `install.json` records only
  `architecture`, `url` and `bucket`. Homebrew can remove orphaned dependencies
  because its Tab records whether you asked for a package directly; Scoop stores
  no such thing, so guessing would delete packages you installed on purpose.
  `brew leaves` does work, because that definition needs no provenance.
- **No source builds.** `--HEAD`, `--build-from-source` and `--with-*` /
  `--without-*` options are reported as dropped. Scoop installs what a manifest
  points at.
- **Version-pinned installs need a reinstall.** `scoop install app@1.2.3` stores
  a generated manifest, so `scoop update` reports it as always current.
  `brew upgrade` detects this and reinstalls from the bucket instead.
- **Symlinks are not required**, since Scoop shims and copies rather than
  linking. Windows Developer Mode is not needed.
- `brew services` is not implemented: Homebrew's version drives `launchd` and
  `systemd`. A Windows backend would mean Task Scheduler or the SCM.

## Layout

```
bin/
  brew.ps1        entry point: flag parsing, command dispatch
  brew.cmd        cmd.exe wrapper so `brew` resolves without a shell hook
lib/
  ScoopBrew.psm1  Scoop discovery, manifest index, version compare, output
  tap-map.json    GitHub repository -> local bucket name map
commands/         one brew-<name>.ps1 per command
test/             Pester suite
```

Each command file declares `# Usage:`, `# Summary:` and optional `# Help:`
comment headers, which `brew commands` and `brew help <command>` read. This
mirrors how Scoop's own `libexec/scoop-<cmd>.ps1` files self-document, and means
adding a command is adding one file.

Options are translated by the dispatcher: PowerShell does not bind GNU-style
`--flag` names, so `--full-name` becomes `-FullName` when the target script
declares that parameter, and stays verbatim otherwise so it can be forwarded to
Scoop.

## Tests

```powershell
Invoke-Pester -Script 'test'
```

The suite is read-only: it inspects the local Scoop install and buckets and
never installs, updates or removes anything. It pins the behaviour of the
version comparison, the manifest field helpers, GNU option binding, and the
requirement that every Homebrew command name is either implemented or has a
stated reason.
