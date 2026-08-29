# Usage: brew --prefix [<package>]
# Summary: Print the Scoop root, or the install directory of a package.
# Group: path
param(
    [Parameter(Position = 0)][string]$Package
)

Test-ScoopInstalled | Out-Null

if (-not $Package) {
    Write-Output (Get-BrewScoopRoot)
    exit 0
}

$installed = @(Get-BrewInstalledPackages -Query ('^' + [regex]::Escape($Package) + '$'))
if ($installed.Count -eq 0) { Abort-Brew "$Package is not installed." }

Write-Output (Get-BrewPackagePath -Name $installed[0].Name -Global:($installed[0].Global -eq $true))
