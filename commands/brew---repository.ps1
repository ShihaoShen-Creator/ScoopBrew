# Usage: brew --repository [<bucket>]
# Summary: Print the Scoop core directory, or a bucket's git checkout.
# Group: path
# Help: Homebrew's repository is the git checkout holding taps and formulae. The
#       closest Scoop equivalents are its core installation and, per bucket, the
#       cloned bucket repository.
param(
    [Parameter(Position = 0)][string]$Bucket
)

Test-ScoopInstalled | Out-Null

if (-not $Bucket) {
    Write-Output (Get-BrewScoopRoot)
    exit 0
}

# Resolve the name the way `brew tap` does, keeping the literal name as a
# fallback for buckets added outside the tap map.
$candidates = @()
$resolved = Resolve-BrewTapName -Name $Bucket
if ($resolved) { $candidates += $resolved.Local }
if ($candidates -notcontains $Bucket) { $candidates += $Bucket }

$rows = @()
foreach ($candidate in $candidates) {
    $rows = @(Get-BrewBuckets | Where-Object { $_.Name -eq $candidate })
    if ($rows.Count -gt 0) { break }
}
if ($rows.Count -eq 0) { Abort-Brew "Bucket '$Bucket' is not added." }

Write-Output $rows[0].Path
