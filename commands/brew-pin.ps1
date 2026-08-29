# Usage: brew pin <package> [...]
# Summary: Prevent a package from being upgraded.
# Group: lifecycle
# Help: Maps onto `scoop hold`, which records the hold in the package's
#       install metadata, so it survives a Scoop self-update.
#
#   -g, --global    Pin a global (all users) package.
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
    foreach ($name in $absent) { brewError "$name is not installed. You cannot pin it." }
    exit 1
}

$scope = @()
if ($Global) { $scope = @('--global') }
exit (Invoke-Scoop @(@('hold') + $scope + $targets))
