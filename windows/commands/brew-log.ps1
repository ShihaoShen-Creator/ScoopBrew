# Usage: brew log [<package>]
# Summary: Show the commit history of a bucket, or of one package manifest.
# Group: query
# Help: Buckets are git repositories, so this is `git log` over the bucket that
#       provides the package.
#
#   -n <N>      Only show N revisions.
#   --oneline   One line per revision.
param(
    [Parameter(Position = 0)][string]$Package,
    [Alias('n')][int]$Limit = 20,
    [switch]$Oneline
)

Test-ScoopInstalled | Out-Null

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Abort-Brew 'git is not on PATH, so bucket history cannot be read.'
}

$bucket = $null
$manifestFile = $null

if ($Package) {
    $pkg = Resolve-BrewPackage $Package
    if (-not $pkg) { Abort-Brew "No available package named '$Package'." }
    if (-not $pkg.Bucket) { Abort-Brew "$($pkg.Name) did not come from a bucket, so it has no history." }
    $bucket = $pkg.Bucket
    if ($pkg.Path) { $manifestFile = (Get-Item -LiteralPath $pkg.Path).Name }
}

$buckets = @(Get-BrewBuckets)
if (-not $bucket) { $bucket = $buckets[0].Name }

$row = @($buckets | Where-Object { $_.Name -eq $bucket })[0]
if (-not (Test-Path -LiteralPath (Join-Path $row.Path '.git'))) {
    Abort-Brew "Bucket '$bucket' is not a git checkout, so it has no history."
}

$gitArgs = @('-C', $row.Path, 'log', "-n$Limit")
if ($Oneline) { $gitArgs += '--oneline' }
if ($manifestFile) {
    Write-BrewRaw "==> $bucket/$Package" 'Cyan'
    $gitArgs += @('--', "bucket/$manifestFile")
} else {
    Write-BrewRaw "==> bucket '$bucket'" 'Cyan'
}

& git @gitArgs
exit $LASTEXITCODE
