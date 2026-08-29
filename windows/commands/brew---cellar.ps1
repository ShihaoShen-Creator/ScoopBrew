# Usage: brew --cellar [<package>]
# Summary: Print the directory where Scoop keeps installed packages.
# Group: path
# Help: Scoop has no Cellar concept: every package lives directly under the apps
#       directory, so this is an alias for that root.
param(
    [Parameter(Position = 0)][string]$Package
)

Test-ScoopInstalled | Out-Null

if (-not $Package) {
    Write-Output (Get-BrewAppsDir)
    exit 0
}

$installed = @(Get-BrewInstalledPackages -Query ('^' + [regex]::Escape($Package) + '$'))
if ($installed.Count -eq 0) { Abort-Brew "$Package is not installed." }

$appDir = if ($installed[0].Global) { Get-BrewAppsDir -Global } else { Get-BrewAppsDir }
Write-Output (Join-Path $appDir $installed[0].Name)
