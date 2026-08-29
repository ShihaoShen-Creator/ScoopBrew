# Usage: brew update
# Summary: Fetch the newest definitions from Scoop and every bucket.
# Group: lifecycle
# Help: Homebrew's `update` refreshes tap git repositories; the Scoop backend
#       updates Scoop itself plus all added buckets.
#
#   --force    Run the update even when it looks unnecessary.
param(
    [switch]$Force,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Tokens
)

Test-ScoopInstalled | Out-Null

$exit = Invoke-Scoop update
if ($exit -ne 0) { exit $exit }

$outdated = @(Get-BrewOutdatedPackages)
if ($outdated.Count -eq 0) {
    brewSuccess 'Already up-to-date.'
    exit 0
}

Write-BrewRaw "==> Outdated packages ($($outdated.Count))" 'Cyan'
foreach ($row in $outdated) {
    $held = if ($row.Hold) { ' (pinned)' } else { '' }
    Write-Host "$($row.Name) $($row.Installed) -> $($row.Latest)$held"
}
brewMessage ''
brewMessage "Run 'brew upgrade' to install them."
