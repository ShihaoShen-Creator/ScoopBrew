# Usage: brew doctor
# Summary: Check that the Scoop backend is set up correctly.
# Group: meta
# Help: Runs ScoopBrew's own environment checks, then Scoop's `checkup`.
param([switch]$Legacy)

$problems = 0

function Add-Problem {
    param([string]$Level, [string]$Check, [object]$Detail)
    $script:problems++
    Write-BrewRaw "$Level $Check" $(if ($Level -eq 'Error:') { 'Red' } else { 'DarkYellow' })
    foreach ($line in @($Detail)) { brewMessage "  $line" }
}

Test-ScoopInstalled | Out-Null

Write-BrewRaw '==> Checking the Scoop backend' 'Cyan'

$root = Get-BrewScoopRoot

if (-not (Test-Path -LiteralPath (Join-Path $root 'apps/scoop/current/bin/scoop.ps1'))) {
    Add-Problem 'Error:' 'Scoop core is broken.' 'Reinstall Scoop: powershell -Command "iwr get.scoop.sh | iex"'
}

if ($env:SCOOP -and $env:SCOOP -ne $root) {
    Add-Problem 'Warning:' 'SCOOP points somewhere unexpected.' "SCOOP=$env:SCOOP but the resolved root is $root"
}

# Scoop's SQLite manifest cache needs an ADO driver it fetches from NuGet.
# ScoopBrew never uses it, so its absence is not a problem.
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
    Add-Problem 'Error:' 'git is not on PATH.' 'Buckets are git repositories, so `brew tap` and `brew update` need git. Try: brew install git'
}

$shimDir = Get-BrewShimDir
$shimOnPath = @($env:PATH -split ';') | Where-Object {
    if (-not $_) { return $false }
    try { (Get-Item -LiteralPath $_ -ErrorAction SilentlyContinue).FullName -eq (Get-Item -LiteralPath $shimDir).FullName } catch { $false }
}
if (@($shimOnPath).Count -eq 0) {
    Add-Problem 'Warning:' 'Scoop shims are not on PATH.' @(
        "Installed programs cannot be launched until $shimDir is on PATH.",
        ('Add it with: [Environment]::SetEnvironmentVariable("Path", $env:Path + ";' + $shimDir + '", "User")'),
        'Then open a new terminal.'
    )
}

$buckets = @(Get-BrewBuckets)
if ($buckets.Count -eq 0) {
    Add-Problem 'Error:' 'No bucket is added.' "Nothing can be found or installed. Try: brew tap main"
} else {
    $empty = @($buckets | Where-Object { $_.Packages -eq 0 })
    if ($empty.Count -gt 0) {
        Add-Problem 'Warning:' 'Bucket contains no manifests.' ($empty | ForEach-Object { "$($_.Name): run 'brew untap $($_.Name)' then 'brew tap $($_.Name)'" })
    }
    if ($buckets.Name -notcontains 'main') {
        Add-Problem 'Warning:' 'The main bucket is not added.' 'Most packages live there. Try: brew tap main'
    }
}

$installed = @(Get-BrewInstalledPackages)
$failed = @($installed | Where-Object { $_.Failed })
if ($failed.Count -gt 0) {
    Add-Problem 'Warning:' 'Some packages failed to install.' ($failed | ForEach-Object { "$($_.Name) $($_.Version): try 'brew reinstall $($_.Name)'" })
}

$deprecated = @($installed | Where-Object { $_.Deprecated })
if ($deprecated.Count -gt 0) {
    Add-Problem 'Warning:' 'Some packages are deprecated.' ($deprecated | ForEach-Object { "$($_.Name) $($_.Version)" })
}

Write-BrewRaw '==> Running scoop checkup' 'Cyan'
$checkup = Invoke-Scoop -PassThru checkup

# `scoop checkup` exits 0 no matter what it finds, so the problem count has
# to be read off its output.
$checkupProblems = 0
foreach ($line in @($checkup.Output)) {
    if ($line -match '^(WARN|ERROR)\b') { Write-BrewRaw $line 'DarkYellow' } else { brewMessage $line }
    if ($line -match 'Found (\d+) potential') { $checkupProblems = [int]$Matches[1] }
}

if ($problems -eq 0 -and $checkupProblems -eq 0 -and $checkup.ExitCode -eq 0) {
    brewSuccess 'Your system is ready to brew.'
    exit 0
}

$summary = "$problems problem(s) found by ScoopBrew"
if ($checkupProblems -gt 0) { $summary += " and $checkupProblems by 'scoop checkup'" }
elseif ($checkup.ExitCode -ne 0) { $summary += ", and 'scoop checkup' failed" }
Write-BrewRaw "Please note those warnings. Unusual problems should be reported to the ScoopBrew issue tracker." 'Yellow'
brewMessage $summary
exit 1
