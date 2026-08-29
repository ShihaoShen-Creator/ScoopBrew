# Usage: brew cat <package>
# Summary: Print the raw Scoop manifest for a package.
# Group: query
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Package,
    [switch]$Json
)

Test-ScoopInstalled | Out-Null

$pkg = Resolve-BrewPackage $Package
if (-not $pkg) { Abort-Brew "No available package named '$Package'." }

if ($pkg.Path -and (Test-Path -LiteralPath $pkg.Path)) {
    Get-Content -LiteralPath $pkg.Path -Raw
    exit 0
}

# Installed-from-URL or auto-generated manifests have no bucket file to show.
$anchor = '^' + [regex]::Escape($pkg.Name) + '$'
$info = @(Get-BrewInstalledPackages -Query $anchor)
if ($info.Count -gt 0) {
    $packagePath = Get-BrewPackagePath -Name $pkg.Name -Global:($info[0].Global -eq $true)
    $installedManifest = if ($packagePath) { Join-Path $packagePath 'manifest.json' } else { $null }
    if ($installedManifest -and (Test-Path -LiteralPath $installedManifest)) {
        Get-Content -LiteralPath $installedManifest -Raw
        exit 0
    }
}

Abort-Brew "No manifest file found for $($pkg.Name)."
