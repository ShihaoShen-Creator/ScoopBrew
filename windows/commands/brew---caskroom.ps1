# Usage: brew --caskroom [<package>]
# Summary: Print the directory for GUI packages (Scoop has no separate one).
# Group: path
# Help: Scoop keeps command line tools and GUI apps in the same place, so this
#       resolves to the apps directory just like `brew --cellar`.
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
