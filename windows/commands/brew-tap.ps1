# Usage: brew tap [<user>/<repo>] [<git-url>]
# Summary: Add a Scoop bucket.
# Group: lifecycle
# Help: A Homebrew tap and a Scoop bucket are the same idea: a git repository of
#       package definitions. `brew tap microsoft/winget-cli` adds the bucket
#       named `winget-cli` from that repository.
#
# Without arguments, lists the added buckets.
#
#   --repair    Redundant: Scoop buckets are plain git repositories.
#   --force-auto-update   Redundant: Scoop always reads the working tree.
param(
    [Parameter(Position = 0)][string]$Name,
    [Parameter(Position = 1)][string]$Url,
    [switch]$Repair,
    [switch]$ForceAutoUpdate,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Tokens
)

Test-ScoopInstalled | Out-Null

if (-not $Name) {
    $buckets = @(Get-BrewBuckets)
    if ($buckets.Count -eq 0) {
        brewMessage 'No buckets are added.'
        exit 0
    }
    Write-BrewTable -Rows $buckets -Properties @('Name', 'Packages', 'Source') -Headers @('Name', 'Packages', 'Source')
    exit 0
}

if ($Repair) { brewWarn '--repair has no meaning for Scoop buckets.' }
if ($ForceAutoUpdate) { brewWarn '--force-auto-update has no meaning for Scoop buckets.' }

# `brew tap <remote> <url>` form: the first argument is the bucket name.
# `brew tap <user>/<repo>` form: derive the name and build the clone URL.
$bucket = $Name
$scoopArgs = @('bucket', 'add')

if ($Name -match '^(?<user>[a-zA-Z0-9._-]+)/(?<repo>[a-zA-Z0-9._-]+)$') {
    $bucket = $Matches['repo']
    if (-not $Url) { $Url = "https://github.com/$($Matches['user'])/$($Matches['repo'])" }
}

$scoopArgs += $bucket
if ($Url) { $scoopArgs += $Url }
if ($Tokens) { $scoopArgs += @(Get-BrewNameArgs $Tokens) }

$known = Get-BrewKnownBucket $bucket
if (-not $Url -and -not $known -and $bucket -ne $Name) {
    brewMessage "==> Adding bucket '$bucket' from $Url"
} elseif (-not $Url -and $known) {
    brewMessage "==> Adding known bucket '$bucket'"
}

exit (Invoke-Scoop @($scoopArgs))
