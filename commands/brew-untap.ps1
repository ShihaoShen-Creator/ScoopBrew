# Usage: brew untap <bucket>
# Summary: Remove a Scoop bucket.
# Group: lifecycle
# Help: Accepts a local bucket name, a tap map shortname or repository name, or
#       the `user/repo` form; all resolve to the local bucket the way
#       `brew tap` does.
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Names,
    [switch]$Force
)

Test-ScoopInstalled | Out-Null

if (-not $Names) { Abort-Brew 'This command requires a bucket name.' }

$added = @(Get-BrewBuckets | ForEach-Object { $_.Name })
$targets = @()
$missing = @()
foreach ($name in $Names) {
    # The mapped local name first, then the literal name, then the repository
    # half (the pre-tap-map convention); remove the first one that is added.
    $candidates = @()
    $resolved = Resolve-BrewTapName -Name $name
    if ($resolved) { $candidates += $resolved.Local }
    $candidates += $name
    if ($name -match '/') { $candidates += ($name -split '/')[-1] }

    $target = $null
    foreach ($candidate in $candidates) {
        if ($added -contains $candidate) { $target = $candidate; break }
    }
    if ($target) { $targets += $target }
    else { $missing += $name }
}

foreach ($name in $missing) { brewError "Bucket '$name' is not added." }
if ($missing.Count -gt 0 -or $targets.Count -eq 0) { exit 1 }

$removed = @()
$failed = @()
foreach ($bucket in $targets) {
    $installedFromBucket = @(Get-BrewInstalledPackages | Where-Object { $_.Bucket -eq $bucket })
    if ($installedFromBucket.Count -gt 0 -and -not $Force) {
        brewWarn "$($installedFromBucket.Count) installed package(s) come from '$bucket': $($installedFromBucket.Name -join ', ')"
        brewWarn 'They will stop receiving updates. Re-run with --force to untap anyway.'
        exit 1
    }

    $exit = Invoke-Scoop bucket rm $bucket
    if ($exit -eq 0) { $removed += $bucket } else { $failed += $bucket }
}

if ($removed.Count -gt 0) { brewSuccess "Untapped: $($removed -join ', ')" }
if ($failed.Count -gt 0) {
    brewError "Could not untap: $($failed -join ', ')"
    exit 1
}
exit 0
