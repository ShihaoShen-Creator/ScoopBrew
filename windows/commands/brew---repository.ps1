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

$rows = @(Get-BrewBuckets | Where-Object { $_.Name -eq $Bucket })
if ($rows.Count -eq 0) { Abort-Brew "Bucket '$Bucket' is not added." }

Write-Output $rows[0].Path
