# Usage: brew tap [<user>/<repo>] [<git-url>]
# Summary: Add a Scoop bucket.
# Group: lifecycle
# Help: A Homebrew tap and a Scoop bucket are the same idea: a git repository of
#       package definitions. Names resolve through the tap map
#       (windows/lib/tap-map.json): `brew tap shihao`, `brew tap ScoopBucket`
#       and `brew tap ShihaoShen-Creator/ScoopBucket` all add the bucket
#       `shihao` from that repository. An unmapped `user/repo` is added as
#       `owner-repo` in lowercase. A second argument is an explicit clone URL
#       and wins over the map.
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

# Every reference resolves to a local bucket name: `user/repo` through the tap
# map (windows/lib/tap-map.json) or the `owner-repo` convention, and a bare
# name as a shortname or repository name from that map. An explicit URL wins.
$bucket = $Name
$scoopArgs = @('bucket', 'add')
$resolved = Resolve-BrewTapName -Name $Name -ForAdd
if ($resolved) {
    $bucket = $resolved.Local
    if (-not $Url) {
        $known = Get-BrewKnownBucket $bucket
        if (-not $known) { $Url = $resolved.Url }
    }
}

$scoopArgs += $bucket
if ($Url) { $scoopArgs += $Url }
if ($Tokens) { $scoopArgs += @(Get-BrewNameArgs $Tokens) }

if ($Url) {
    brewMessage "==> Adding bucket '$bucket' from $Url"
} elseif ($known) {
    brewMessage "==> Adding known bucket '$bucket'"
}

exit (Invoke-Scoop @($scoopArgs))
