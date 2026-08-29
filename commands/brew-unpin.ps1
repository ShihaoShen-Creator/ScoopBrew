# Usage: brew unpin <package> [...]
# Summary: Allow a previously pinned package to be upgraded again.
# Group: lifecycle
# Help: Maps onto `scoop unhold`.
#
#   -g, --global      Unpin a global (all users) package.
param(
    [Alias('g')][switch]$Global,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Packages
)

Test-ScoopInstalled | Out-Null

$targets = @(Get-BrewNameArgs $Packages)
if ($targets.Count -eq 0) { Abort-Brew 'This command requires a package name.' }

$installedNames = @(Get-BrewInstalledPackages | ForEach-Object { $_.Name })
$absent = @($targets | Where-Object { $installedNames -notcontains $_ })
if ($absent.Count -gt 0) {
    foreach ($name in $absent) { brewError "$name is not installed." }
    exit 1
}

$scope = @()
if ($Global) { $scope = @('--global') }
exit (Invoke-Scoop @(@('unhold') + $scope + $targets))
