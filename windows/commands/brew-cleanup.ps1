# Usage: brew cleanup [<package>...]
# Summary: Remove old versions of installed packages and stale downloads.
# Group: lifecycle
# Help: The deletion itself is delegated to `scoop cleanup`, which knows which
#       directory is the live one. Scoop has no dry run, so `--dry-run` reports
#       what would go without calling it.
#
#   -n, --dry-run         Show what would be removed.
#   -g, --global          Clean up global (all users) packages.
#   -s, --prune=<all|N>   Also drop cached downloads: all, or older than N days.
param(
    [Alias('n')][switch]$DryRun,
    [Alias('g')][switch]$Global,
    [Alias('s')][string]$Prune,
    [switch]$PrunePrefix,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Tokens
)

Test-ScoopInstalled | Out-Null

$names = @(Get-BrewNameArgs $Tokens)
if ($PrunePrefix) { brewWarn '--prune-prefix has no meaning for the Scoop backend.' }

$installed = @(Get-BrewInstalledPackages)
if ($installed.Count -eq 0) {
    brewMessage 'No packages are installed.'
    exit 0
}

# Report the removable versions before asking Scoop to delete them.
$victims = @()
foreach ($pkg in $installed) {
    if ($names.Count -gt 0 -and $names -notcontains $pkg.Name) { continue }
    if ($pkg.Global -ne [bool]$Global) { continue }

    $appRoot = if ($pkg.Global) { Get-BrewAppsDir -Global } else { Get-BrewAppsDir }
    $appPath = Join-Path $appRoot $pkg.Name
    $versions = @(Get-ChildItem -LiteralPath $appPath -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'current' -and $_.Name -ne $pkg.Version })

    foreach ($stale in $versions) {
        $bytes = (Get-ChildItem -LiteralPath $stale.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        $victims += [pscustomobject]@{ Package = $pkg.Name; Version = $stale.Name; Bytes = [int64]$bytes }
    }
}

if ($names.Count -gt 0) {
    $unknown = @($names | Where-Object { $installed.Name -notcontains $_ })
    foreach ($name in $unknown) { brewWarn "$name is not installed." }
}

if ($victims.Count -eq 0) {
    brewMessage 'No old versions to remove.'
} else {
    $totalMb = [Math]::Round((($victims | Measure-Object -Property Bytes -Sum).Sum / 1MB), 1)
    $label = if ($DryRun) { 'would be removed' } else { 'to remove' }
    brewMessage "==> Old versions $label : $($victims.Count), about $totalMb MB"
    foreach ($entry in $victims) { brewMessage "  $($entry.Package) $($entry.Version)" }

    if ($DryRun) {
        brewMessage '(dry run: nothing was removed)'
    } else {
        $cleanupArgs = @('cleanup')
        if ($Global) { $cleanupArgs += '--global' }
        if ($names.Count -gt 0) { $cleanupArgs += @($victims | ForEach-Object { $_.Package } | Select-Object -Unique) }
        else { $cleanupArgs += '--all' }
        $null = Invoke-Scoop @($cleanupArgs)
    }
}

if ($Prune) {
    $cache = Get-BrewCacheDir

    if ($Prune -eq 'all') {
        if ($DryRun) {
            $cacheFiles = @(Get-ChildItem $cache -File -ErrorAction SilentlyContinue)
            brewMessage "==> Would remove $($cacheFiles.Count) cached download(s)"
        } else {
            $null = Invoke-Scoop cache rm -a
        }
    } elseif ($Prune -match '^\d+$') {
        $cutoff = (Get-Date).AddDays(-[int]$Prune)
        $old = @(Get-ChildItem $cache -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff })
        $bytes = [Math]::Round(((($old | Measure-Object -Property Length -Sum).Sum) / 1MB), 1)
        if ($DryRun) {
            brewMessage "==> Would remove $($old.Count) cached download(s) older than $Prune days ($bytes MB)"
        } else {
            brewMessage "==> Removing $($old.Count) cached download(s) older than $Prune days ($bytes MB)"
            foreach ($file in $old) { Remove-Item -LiteralPath $file.FullName -Force }
        }
    } else {
        brewWarn "--prune expects 'all' or a number of days, got '$Prune'."
        exit 1
    }
}

exit 0
