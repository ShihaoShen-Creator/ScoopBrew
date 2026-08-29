# Usage: brew outdated [<package>...]
# Summary: List packages that have a newer version available.
# Group: query
# Help: Compares the installed version against each manifest by default, which
#       is offline and fast.
#
#   --fetch     Update Scoop and every bucket first (needs network and git).
#   --greedy    Include packages whose manifest is `current`.
#   --json      Emit machine-readable output.
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Packages,
    [switch]$Fetch,
    [switch]$Greedy,
    [switch]$Json
)

Test-ScoopInstalled | Out-Null

if ($Fetch) {
    brewMessage '==> Updating Scoop and buckets'
    Invoke-Scoop update | Out-Null
}

$outdated = @(Get-BrewOutdatedPackages)

if ($Packages) {
    $outdated = @($outdated | Where-Object { $Packages -contains $_.Name })
}
if (-not $Greedy) {
    $outdated = @($outdated | Where-Object { $_.Latest -ne 'current' })
}

if ($Json) {
    $outdated | ConvertTo-Json -Depth 4
    exit 0
}

if ($outdated.Count -eq 0) {
    brewMessage 'All packages are up to date.'
    exit 0
}

foreach ($row in $outdated) {
    $held = if ($row.Hold) { ' (pinned)' } else { '' }
    Write-Host "$($row.Name) $($row.Installed) -> $($row.Latest)$held"
}
brewMessage ''
brewMessage "Run 'brew upgrade' to update them all."
