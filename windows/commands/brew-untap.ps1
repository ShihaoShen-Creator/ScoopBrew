# Usage: brew untap <bucket>
# Summary: Remove a Scoop bucket.
# Group: lifecycle
# Help: Accepts both `bucket` and `user/repo` forms; the repository name is used
#       as the bucket name, matching `brew tap`.
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
    # `user/repo` names a bucket by its repository half, matching brew tap.
    $candidate = if ($name -match '/') { ($name -split '/')[-1] } else { $name }

    if ($added -contains $candidate) { $targets += $candidate }
    elseif ($added -contains $name) { $targets += $name }
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
