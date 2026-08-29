# Usage: brew --cachedir [<package>]
# Summary: Print Scoop's download cache directory.
# Group: path
param(
    [Parameter(Position = 0)][string]$Package
)

Test-ScoopInstalled | Out-Null

$cache = Get-BrewCacheDir

if (-not $Package) {
    Write-Output $cache
    exit 0
}

$cached = @(Get-ChildItem $cache -Filter "$Package#*" -ErrorAction SilentlyContinue)
if ($cached.Count -eq 0) { Abort-Brew "$Package is not cached." }

foreach ($entry in $cached) { Write-Output $entry.FullName }
