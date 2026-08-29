# Usage: brew exec [<command> [<args>...]]
# Summary: Run a command with the Scoop shim directories on PATH.
# Group: meta
# Help: Homebrew populates PATH from formula bin directories; Scoop exposes every
#       installed program through its shim directory, which is normally already
#       on PATH. This command guarantees it for the child process, so it works
#       even in a shell that has not been configured.
#
#   --formulae=<a,b>   Install those packages first.
#   --sandbox=<path>   Redundant: Scoop has no sandbox.
#   --deny-network     Redundant: Scoop has no sandbox.
param(
    [Parameter(Position = 0)][string]$Command,
    [string]$Formulae,
    [switch]$DenyNetwork,
    [string]$Sandbox,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

Test-ScoopInstalled | Out-Null

if ($DenyNetwork) { brewWarn '--deny-network has no equivalent: Scoop runs programs directly.' }
if ($Sandbox) { brewWarn '--sandbox has no equivalent: Scoop runs programs directly.' }

if ($Formulae) {
    $wanted = @($Formulae -split ',' | Where-Object { $_ })
    brewMessage "==> Installing $($wanted -join ', ')"
    $exit = Invoke-Scoop @(@('install') + $wanted)
    if ($exit -ne 0) { Abort-Brew 'Installation failed; not running the command.' }
}

if (-not $Command) {
    brewMessage 'ScoopBrew exec environment:'
    brewMessage "  local shims: $(Get-BrewShimDir)"
    $globalRoot = Get-GlobalScoopRoot
    if ($globalRoot) { brewMessage "  global shims: $(Join-Path $globalRoot 'shims')" }
    brewMessage ''
    brewMessage "Run a command with them on PATH: brew exec <command> [args]"
    exit 0
}

$prepend = @((Get-BrewShimDir))
$globalRoot = Get-GlobalScoopRoot
if ($globalRoot) { $prepend += (Join-Path $globalRoot 'shims') }

$env:PATH = (($prepend -join ';') + ';' + $env:PATH)

$resolved = Get-Command $Command -ErrorAction SilentlyContinue
if (-not $resolved) {
    brewError "'$Command' was not found on PATH, even with the Scoop shim directories added."
    brewMessage "Install the package that provides it: brew install <package>"
    brewMessage "Or find it: brew which-formula $Command"
    exit 1
}

$arguments = @($Rest | Where-Object { $null -ne $_ })
& $resolved.Source @arguments
exit $LASTEXITCODE
