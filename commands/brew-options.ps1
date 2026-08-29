# Usage: brew options [<package>...]
# Summary: Show install-time options for a package.
# Group: query
# Help: Scoop manifests define no build options, so there is nothing to toggle
#   per package. The architecture and `suggest` stanzas are shown because they
#   are the closest equivalent.
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Packages
)

Test-ScoopInstalled | Out-Null

if (-not $Packages) {
    brewMessage 'Scoop manifests have no build options, so nothing to list.'
    brewMessage "Pass a package name to see what can vary for it: brew options <package>"
    exit 0
}

foreach ($query in $Packages) {
    $pkg = Resolve-BrewPackage $query
    if (-not $pkg) { brewError "No available package named '$query'."; exit 1 }

    brewMessage "$($pkg.Name):"
    brewMessage "  --arch=<64bit|32bit|arm64>   install a specific architecture (default: $(Get-BrewArchitecture))"
    foreach ($group in $pkg.Manifest.suggest.PSObject.Properties) {
        brewMessage "  recommended for '$($group.Name)': $(@($group.Value) -join ', ')"
    }
}
