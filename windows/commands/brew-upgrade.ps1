# Usage: brew upgrade [<package>...]
# Summary: Upgrade outdated packages.
# Group: lifecycle
# Help: Without package names, updates Scoop and its buckets and then every
#       outdated package, like `brew upgrade` does.
#
#   -g, --global      Upgrade global (all users) packages.
#   --dry-run         Show what would be upgraded.
#   --fetch           Only refresh Scoop and buckets, upgrade nothing.
param(
    [Alias('g')][switch]$Global,
    [switch]$DryRun,
    [switch]$Fetch,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Tokens
)

Test-ScoopInstalled | Out-Null

$names = @(Get-BrewNameArgs $Tokens)
$scope = @()
if ($Global) { $scope = @('--global') }

brewMessage "==> Updating Scoop and buckets"
$null = Invoke-Scoop @('update')

if ($Fetch) { exit 0 }

if ($names.Count -eq 0) {
    $outdated = @(Get-BrewOutdatedPackages | Where-Object { -not $_.Hold })
    if ($outdated.Count -eq 0) {
        brewSuccess 'All packages are up to date.'
        exit 0
    }
    $names = @($outdated | ForEach-Object { $_.Name })
    brewMessage "==> Upgrading $($names.Count) package(s): $($names -join ', ')"
}
else {
    $installedNames = @(Get-BrewInstalledPackages | ForEach-Object { $_.Name })
    $absent = @($names | Where-Object { $installedNames -notcontains $_ })
    if ($absent.Count -gt 0) {
        foreach ($name in $absent) { brewError "$name is not installed. Use 'brew install $name'." }
        exit 1
    }
    brewMessage "==> Upgrading $($names.Count) package(s)"
}

if ($DryRun) {
    brewMessage "Would run: scoop update $($scope -join ' ') $($names -join ' ')"
    exit 0
}

$bucketNames = @(Get-BrewBuckets | ForEach-Object { $_.Name })
$installedRows = @(Get-BrewInstalledPackages)

# A version-pinned install (`scoop install app@26.00`) keeps its own generated
# manifest, so `scoop update` answers "already latest" and changes nothing.
# Those have to be reinstalled from the bucket to move forward.
$pinned = @()
$normal = @()
foreach ($name in $names) {
    $row = @($installedRows | Where-Object { $_.Name -eq $name })
    $source = if ($row.Count -gt 0) { $row[0].Bucket } else { $null }
    if ($source -and $bucketNames -notcontains $source) { $pinned += $name }
    else { $normal += $name }
}

$exit = 0
$before = @{}
foreach ($row in $installedRows) { $before[$row.Name] = $row.Version }

if ($normal.Count -gt 0) {
    $exit = Invoke-Scoop @(@('update') + $scope + $normal)
}

foreach ($name in $pinned) {
    brewMessage "==> $($name) is pinned to a specific version; reinstalling from its bucket"
    $null = Invoke-Scoop @(@('uninstall') + $scope + @($name))
    $code = Invoke-Scoop @(@('install') + $scope + @($name))
    if ($code -ne 0) { $exit = $code }
}

$after = @(Get-BrewInstalledPackages -Refresh)
$upgraded = @()
$stayed = @()
foreach ($name in $names) {
    $row = @($after | Where-Object { $_.Name -eq $name })
    if ($row.Count -eq 0) { continue }
    if ($before[$name] -and $row[0].Version -ne $before[$name]) {
        $upgraded += "$name $($before[$name]) -> $($row[0].Version)"
    } else {
        $stayed += "$name $($row[0].Version)"
    }
}

if ($upgraded.Count -gt 0) {
    Write-BrewRaw '==> Upgraded' 'Cyan'
    foreach ($line in $upgraded) { brewMessage "  $line" }
}
if ($stayed.Count -gt 0) {
    Write-BrewRaw '==> Already at the version its manifest declares' 'Cyan'
    foreach ($line in $stayed) { brewMessage "  $line" }
}
if ($upgraded.Count -eq 0 -and $stayed.Count -gt 0) {
    brewMessage ''
    brewMessage "Nothing advanced. If a newer manifest exists, run 'brew update' first."
}

exit $exit
