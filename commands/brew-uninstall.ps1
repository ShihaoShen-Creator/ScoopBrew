# Usage: brew uninstall <package> [...]
# Summary: Uninstall packages using the Scoop backend.
# Group: lifecycle
# Help: Options:
#   -g, --global    Uninstall a global (all users) package.
#   --force         Also continue when a package is not installed.
#   --zap           Redundant: Scoop always runs the manifest uninstaller.
param(
    [Alias('g')][switch]$Global,
    [switch]$Force,
    [switch]$Zap,
    [switch]$DryRun,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Tokens
)

Test-ScoopInstalled | Out-Null

$names = @(Get-BrewNameArgs $Tokens)
if ($names.Count -eq 0) { Abort-Brew 'This command requires a package name.' }

if ($Zap) { brewWarn '--zap is not needed: Scoop manifests carry their own uninstaller script.' }

$installedNames = @(Get-BrewInstalledPackages | ForEach-Object { $_.Name })
$absent = @($names | Where-Object { $installedNames -notcontains $_ })

if ($absent.Count -gt 0 -and -not $Force) {
    foreach ($name in $absent) { brewError "$name is not installed." }
    exit 1
}
if ($absent.Count -gt 0) {
    brewWarn "Skipping not-installed package(s): $($absent -join ', ')"
}

$targets = @($names | Where-Object { $installedNames -contains $_ })
if ($targets.Count -eq 0) { exit 0 }

$scoopArgs = @('uninstall')
if ($Global) { $scoopArgs += '--global' }
$scoopArgs += $targets

if ($DryRun) {
    brewMessage "Would run: scoop $($scoopArgs -join ' ')"
    exit 0
}

brewMessage "==> Uninstalling $($targets.Count) package(s) with Scoop"
$exit = Invoke-Scoop @($scoopArgs)
if ($exit -eq 0) { brewSuccess "Uninstalled: $($targets -join ', ')" }
exit $exit
