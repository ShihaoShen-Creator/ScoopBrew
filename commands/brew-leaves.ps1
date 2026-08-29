# Usage: brew leaves
# Summary: List installed packages that nothing else depends on.
# Group: query
# Help: Same definition as Homebrew's: an installed package that is not listed
#       in the `depends` stanza of any other installed package.
param([switch]$Pinned)

Test-ScoopInstalled | Out-Null

$installed = @(Get-BrewInstalledPackages)
if ($installed.Count -eq 0) {
    brewMessage 'There are no packages installed.'
    exit 0
}

$dependedOn = @()
foreach ($pkg in $installed) {
    foreach ($dep in @(ConvertTo-BrewList (Resolve-BrewPackage $pkg.Name).Manifest.depends)) {
        $dependedOn += ($dep -split '/')[-1]
    }
}

foreach ($pkg in $installed) {
    if ($dependedOn -contains $pkg.Name) { continue }
    Write-Output $pkg.Name
}
