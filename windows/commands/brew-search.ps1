# Usage: brew search [<regex>]
# Summary: Search the added Scoop buckets for packages.
# Group: query
# Help: Matches package names by default. Bucket manifests are read from disk,
#       so this works with no network access.
#
#   --desc      Also match against package descriptions.
#   --names     Name-only match (the default).
#   --limit N   Maximum number of results.
param(
    [Parameter(Position = 0)][string]$Pattern,
    [switch]$Desc,
    [switch]$Names,
    [int]$Limit = 0
)

Test-ScoopInstalled | Out-Null

$installedNames = @(Get-BrewInstalledPackages | ForEach-Object { $_.Name })

if (-not $Pattern) {
    $all = @(Search-BrewPackages -Pattern '')
    brewMessage "==> Packages ($($all.Count))"
    $all | ForEach-Object { $_.Name } | Format-Wide -Column 4
    exit 0
}

$by = if ($Desc) { 'desc' } else { 'name' }
$matches = @(Search-BrewPackages -Pattern $Pattern -By $by)

if ($Limit -gt 0 -and $matches.Count -gt $Limit) {
    $matches = @($matches | Select-Object -First $Limit)
}

if ($matches.Count -eq 0) {
    brewMessage "No packages matching '$Pattern' found."
    brewMessage "Added buckets: $((Get-BrewBuckets | ForEach-Object { $_.Name }) -join ', ')"
    brewMessage "Search all known buckets with 'brew tap', and add one with 'brew tap <user>/<repo>'."
    exit 1
}

brewMessage "==> Packages ($($matches.Count))"
foreach ($m in $matches) {
    $mark = if ($installedNames -contains $m.Name) { ' [installed]' } else { '' }
    $line = "$($m.Name)$mark"
    if ($Desc -and $m.Description) { $line = "$line - $($m.Description)" }
    brewMessage $line
}
