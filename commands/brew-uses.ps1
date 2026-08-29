# Usage: brew uses <package>
# Summary: List packages that depend on the given package.
# Group: query
# Help: Scans every manifest in the added buckets for a reverse dependency.
#
#   --installed    Only report dependents that are currently installed.
#   --include-build    Redundant here; Scoop has no build-only dependencies.
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Package,
    [switch]$Installed
)

Test-ScoopInstalled | Out-Null

$pkg = Resolve-BrewPackage $Package
if (-not $pkg) { Abort-Brew "No available package named '$Package'." }

$dependents = @(Get-BrewDependents -Name $pkg.Name)
if ($Installed) {
    $installedNames = @(Get-BrewInstalledPackages | ForEach-Object { $_.Name })
    $dependents = @($dependents | Where-Object { $installedNames -contains $_.Name })
}

if ($dependents.Count -eq 0) {
    brewMessage "No packages found that depend on $($pkg.Name)."
    exit 0
}

Write-BrewTable -Rows $dependents -Properties @('Name', 'Bucket', 'Version') -Headers @('Name', 'Bucket', 'Version')
