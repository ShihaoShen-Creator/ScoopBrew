# Usage: brew config [--get <key>] [--set <key> <value>] [--list]
# Summary: Show ScoopBrew and Scoop configuration.
# Group: meta
# Help: Without options, prints a diagnostic summary in the style of
#       `brew config`. `--get`, `--set` and `--list` act on Scoop's own
#       configuration and are passed straight through.
param(
    [string]$Get,
    [string[]]$Set,
    [switch]$List
)

Test-ScoopInstalled | Out-Null

if ($List) { exit (Invoke-Scoop config) }
if ($Get) { exit (Invoke-Scoop config $Get) }
if ($Set) { exit (Invoke-Scoop config @($Set)) }

$root = Get-BrewScoopRoot
$shimDir = Get-BrewShimDir
$onPath = (@($env:PATH -split ';') | Where-Object {
    try { (Get-Item -LiteralPath $_ -ErrorAction SilentlyContinue).FullName -eq (Get-Item -LiteralPath $shimDir).FullName } catch { $false }
}).Count -gt 0

$rows = @(
    [pscustomobject]@{ Key = 'ScoopBrew'; Value = $BrewVersion }
    [pscustomobject]@{ Key = 'Scoop'; Value = "$(Get-BrewScoopVersion) at $root" }
    [pscustomobject]@{ Key = 'Windows'; Value = "$([System.Environment]::OSVersion.VersionString) (build $([System.Environment]::OSVersion.Version.Build))" }
    [pscustomobject]@{ Key = 'Architecture'; Value = Get-BrewArchitecture }
    [pscustomobject]@{ Key = 'PowerShell'; Value = $PSVersionTable.PSVersion.ToString() }
    [pscustomobject]@{ Key = 'Shim directory'; Value = $shimDir }
    [pscustomobject]@{ Key = 'Shims on PATH'; Value = if ($onPath) { 'yes' } else { 'no - run the PATH setup in windows/README.md' } }
    [pscustomobject]@{ Key = 'Global root'; Value = Get-GlobalScoopRoot }
    [pscustomobject]@{ Key = 'Cache'; Value = Get-BrewCacheDir }
    [pscustomobject]@{ Key = 'State'; Value = $StateDir }
    [pscustomobject]@{ Key = 'Buckets'; Value = ((Get-BrewBuckets | ForEach-Object { "$($_.Name)($($_.Packages))" }) -join ', ') }
    [pscustomobject]@{ Key = 'Installed'; Value = "$(@(Get-BrewInstalledPackages).Count) packages" }
)

Write-BrewRaw 'HOMEBREW VERSION:' 'Cyan'
foreach ($row in $rows) { Write-Host ('{0,-18}{1}' -f $row.Key, $row.Value) }
