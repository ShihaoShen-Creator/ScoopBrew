# Usage: brew --taps
# Summary: Print the names of added Scoop buckets, one per line.
# Group: path
param()

Test-ScoopInstalled | Out-Null

foreach ($bucket in @(Get-BrewBuckets)) { Write-Output $bucket.Name }
