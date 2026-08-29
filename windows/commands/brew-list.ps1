# Usage: brew list [<regex>]
# Summary: List installed packages.
# Group: query
# Help: Installed packages are read straight from the Scoop apps directory, so
#       this always agrees with `scoop list`.
#
#   --versions         Show the installed version of each package.
#   --pinned           Only show packages held against updates.
#   --unpinned         Only show packages that are not held.
#   --full-name        Prefix package names with their bucket.
#   --reverse          Sort newest first.
param(
    [Parameter(Position = 0)][string]$Query,
    [switch]$Versions,
    [switch]$Pinned,
    [switch]$Unpinned,
    [switch]$FullName,
    [switch]$Reverse
)

$packages = @(Get-BrewInstalledPackages -Query $Query)

if ($Pinned) { $packages = @($packages | Where-Object { $_.Hold }) }
if ($Unpinned) { $packages = @($packages | Where-Object { -not $_.Hold }) }
if ($Reverse) { $packages = @($packages | Sort-Object Name -Descending) }

if (@($packages).Count -eq 0) {
    if ($Query) { Abort-Brew "No installed packages matching '$Query'." }
    brewMessage 'There are no packages installed.'
    brewMessage "Run 'brew install <package>' to install one."
    exit 0
}

if ($FullName) {
    $packages = @($packages | ForEach-Object {
        [pscustomobject]@{
            Name    = "$($_.Bucket)/$($_.Name)"
            Version = $_.Version
            Bucket  = $_.Bucket
        }
    })
}

Write-BrewTable -Rows $packages -Properties @('Name', 'Version', 'Bucket') -Headers @('Name', 'Version', 'Bucket')
