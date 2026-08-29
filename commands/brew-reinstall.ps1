# Usage: brew reinstall <package> [...]
# Summary: Uninstall and install packages again.
# Group: lifecycle
# Help: Options:
#   -g, --global    Reinstall a global (all users) package.
param(
    [Alias('g')][switch]$Global,
    [switch]$DryRun,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Tokens
)

Test-ScoopInstalled | Out-Null

$names = @(Get-BrewNameArgs $Tokens)
if ($names.Count -eq 0) { Abort-Brew 'This command requires a package name.' }

$scope = @()
if ($Global) { $scope = @('--global') }

$installedNames = @(Get-BrewInstalledPackages | ForEach-Object { $_.Name })

foreach ($name in $names) {
    $isInstalled = $installedNames -contains $name

    if ($DryRun) {
        if ($isInstalled) { brewMessage "Would run: scoop uninstall $($scope -join ' ') $name" }
        brewMessage "Would run: scoop install $($scope -join ' ') $name"
        continue
    }

    if ($isInstalled) {
        brewMessage "==> Uninstalling $name"
        $exit = Invoke-Scoop @(@('uninstall') + $scope + @($name))
        if ($exit -ne 0) { Abort-Brew "Failed to uninstall $name; refusing to reinstall it." }
    }

    brewMessage "==> Installing $name"
    $exit = Invoke-Scoop @(@('install') + $scope + @($name))
    if ($exit -ne 0) { Abort-Brew "Failed to reinstall $name." }
}

if (-not $DryRun) { brewSuccess "Reinstalled: $($names -join ', ')" }
exit 0
