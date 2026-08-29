# Usage: brew install <package> [...]
# Summary: Install packages using the Scoop backend.
# Group: lifecycle
# Help: Options:
#   -g, --global      Install for all users (needs an elevated shell).
#   --cask            Treat the names as GUI apps, adding the `extras` bucket
#                     first, which is where Scoop keeps them.
#   --dry-run         Show the Scoop command without running it.
#
# A tap-qualified name `user/tap/app` adds the tap's bucket first when it is
# missing, then installs `tap/app`. Anything else Scoop understands is passed
# through untouched, so a URL or a path to a local manifest JSON works exactly
# as it does with `scoop install`.
param(
    [Alias('g')][switch]$Global,
    [switch]$Cask,
    [switch]$DryRun,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Tokens
)

Test-ScoopInstalled | Out-Null

$names = @(Get-BrewNameArgs $Tokens)
$flags = @(Get-BrewFlagArgs $Tokens)

if ($names.Count -eq 0) { Abort-Brew 'This command requires a package name.' }

$allowed = @('--no-cache', '--insecure', '--check-hash-only', '--verbose', '--use-cache', '--arch', '--global')
$parsed = Convert-BrewFlags -Flags $flags -Allowed $allowed
Show-DroppedFlags -Dropped $parsed.Dropped

$scoopArgs = @('install')
if ($Global) { $scoopArgs += '--global' }
$scoopArgs += @($parsed.Accepted)

# Scoop keeps GUI applications in a separate bucket, which is not installed by
# default. Add it before resolving names so `--cask` can find anything.
if ($Cask) {
    if (@(Get-BrewBuckets | ForEach-Object { $_.Name }) -notcontains 'extras') {
        brewMessage "==> Adding the 'extras' bucket for GUI applications"
        $added = Invoke-Scoop bucket add extras
        if ($added -ne 0) { Abort-Brew "Could not add the 'extras' bucket." }
        Reset-BrewBucketCache
    }
}

# Homebrew refuses to install anything when one name cannot be resolved, so do
# the same instead of leaving a half-installed request behind. URLs and local
# manifests have no name to look up, so Scoop handles those itself.
$missing = @()
for ($i = 0; $i -lt $names.Count; $i++) {
    $name = $names[$i]
    if ($name -match '^(ht|f)tps?://|\\\\' -or $name.EndsWith('.json') -or (Test-Path -LiteralPath $name)) { continue }

    # Homebrew's `<user>/<tap>/<name>` form becomes Scoop's `<bucket>/<name>`;
    # add the tap's bucket first when it is missing, the way --cask adds
    # `extras`. The bucket part is the tap's local name per the tap map.
    $expanded = Expand-BrewTapName $name
    if ($expanded) {
        if (@(Get-BrewBuckets | ForEach-Object { $_.Name }) -notcontains $expanded.Bucket) {
            $message = "==> Adding bucket '$($expanded.Bucket)'"
            $tapArgs = @('bucket', 'add', $expanded.Bucket)
            if (-not (Get-BrewKnownBucket $expanded.Bucket)) {
                $tapArgs += $expanded.Url
                $message += " from $($expanded.Url)"
            }
            brewMessage $message
            $added = Invoke-Scoop @($tapArgs)
            if ($added -ne 0) { Abort-Brew "Could not add the '$($expanded.Tap)' tap." }
            Reset-BrewBucketCache
        }
        $names[$i] = $expanded.Name
        $name = $expanded.Name
    }

    if (-not (Resolve-BrewPackage $name)) { $missing += $name }
}

if ($missing.Count -gt 0) {
    foreach ($name in $missing) { brewError "No available package named '$name'." }
    brewMessage ''
    brewMessage "Search for it with 'brew search <term>'."
    brewMessage "Scoop's GUI application bucket is added by 'brew tap extras' or 'brew install --cask'."
    exit 1
}

$scoopArgs += $names

if ($DryRun) {
    brewMessage "Would run: scoop $($scoopArgs -join ' ')"
    exit 0
}

brewMessage "==> Installing $($names.Count) package(s) with Scoop"
$exit = Invoke-Scoop @($scoopArgs)
if ($exit -eq 0) {
    foreach ($name in $names) {
        $info = Resolve-BrewPackage $name
        if ($info -and $info.Manifest.notes) {
            $notes = @(ConvertTo-BrewList $info.Manifest.notes)
            if ($notes.Count -gt 0) {
                Write-BrewRaw "==> Notes for $name" 'Cyan'
                foreach ($note in $notes) { brewMessage $note }
            }
        }
    }
    brewSuccess "Installed: $($names -join ', ')"
}
exit $exit
