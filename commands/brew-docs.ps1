# Usage: brew docs [<topic>]
# Summary: Open Scoop's documentation.
# Group: meta
# Help: Homebrew links to docs.brew.sh pages; the Scoop backend points at Scoop
#       instead and at the reference material shipped inside the Scoop install.
param(
    [Parameter(Position = 0)][string]$Topic
)

Test-ScoopInstalled | Out-Null

$coreDir = Get-BrewScoopCoreDir

if (-not $Topic) {
    $readme = Join-Path $coreDir 'README.md'
    brewMessage '==> https://scoop.sh'
    brewMessage "Local reference: $readme"
    Start-Process 'https://scoop.sh'
    exit 0
}

$local = @(
    [pscustomobject]@{ Topic = 'readme'; Path = (Join-Path $coreDir 'README.md') }
    [pscustomobject]@{ Topic = 'changelog'; Path = (Join-Path $coreDir 'CHANGELOG.md') }
    [pscustomobject]@{ Topic = 'schema'; Path = (Join-Path $coreDir 'schema.json') }
)

$match = @($local | Where-Object { $_.Topic -like "*$Topic*" })
if ($match.Count -eq 0) {
    brewError "No local Scoop documentation topic matching '$Topic'."
    brewMessage ''
    brewMessage 'Available topics:'
    foreach ($entry in $local) { brewMessage "  $($entry.Topic)" }
    brewMessage ''
    brewMessage 'Scoop keeps the rest of its reference material in its wiki; open https://scoop.sh'
    exit 1
}

foreach ($entry in $match) {
    if (Test-Path -LiteralPath $entry.Path) {
        brewMessage "==> $($entry.Path)"
        Start-Process $entry.Path
    }
}
