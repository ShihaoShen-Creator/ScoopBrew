# Usage: brew desc <regex>
# Summary: Show one-line descriptions for packages matching a pattern.
# Group: query
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Pattern
)

Test-ScoopInstalled | Out-Null

$results = @(Search-BrewPackages -Pattern $Pattern)
if ($results.Count -eq 0) { Abort-Brew "No packages matching '$Pattern'." }

foreach ($entry in $results) {
    if ($entry.Description) { Write-Host "$($entry.Name): $($entry.Description)" }
    else { Write-Host $entry.Name }
}
