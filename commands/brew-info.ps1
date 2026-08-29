# Usage: brew info [<package>...]
# Summary: Display information about a package from its Scoop manifest.
# Group: query
# Help: Reads the manifest directly, so this works offline for any added bucket.
#
#   --json    Emit the manifest and installation state as JSON.
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Packages,
    [switch]$Json
)

Test-ScoopInstalled | Out-Null

if (-not $Packages) {
    brewMessage "ScoopBrew $BrewVersion (Scoop $(Get-BrewScoopVersion))"
    brewMessage "Packages installed: $(@(Get-BrewInstalledPackages).Count)"
    brewMessage "Packages available: $(@(Get-BrewPackageIndex).Count)"
    brewMessage "Buckets: $((Get-BrewBuckets | ForEach-Object { $_.Name }) -join ', ')"
    exit 0
}

$failed = 0
$results = @()

foreach ($query in $Packages) {
    $pkg = Resolve-BrewPackage $query
    if (-not $pkg) {
        brewError "No available package or cask named '$query'."
        $prefix = $query.Substring(0, [Math]::Min(3, $query.Length))
        $hint = @(Search-BrewPackages -Pattern "^$([regex]::Escape($prefix))")
        if ($hint.Count -gt 0) {
            brewMessage ''
            brewMessage 'Did you mean?'
            foreach ($h in $hint | Select-Object -First 5) { brewMessage "    $($h.Bucket)/$($h.Name)" }
        }
        $failed = 1
        continue
    }

    $anchor = '^' + [regex]::Escape($pkg.Name) + '$'
    $installed = @(Get-BrewInstalledPackages -Query $anchor)
    $state = [pscustomobject]@{
        Name        = $pkg.Name
        Bucket      = $pkg.Bucket
        Version     = $pkg.Version
        Description = [string]$pkg.Manifest.description
        Homepage    = [string]$pkg.Manifest.homepage
        License     = Format-BrewLicense $pkg.Manifest.license
        Depends     = @(ConvertTo-BrewList $pkg.Manifest.depends)
        Suggest     = @(Get-BrewSuggest $pkg.Manifest)
        Notes       = @(ConvertTo-BrewList $pkg.Manifest.notes)
        Installed   = ($installed.Count -gt 0)
        Current     = if ($installed.Count -gt 0) { $installed[0].Version } else { $null }
        Path        = if ($installed.Count -gt 0) { Get-BrewPackagePath -Name $pkg.Name -Global:($installed[0].Global -eq $true) } else { $null }
        Held        = if ($installed.Count -gt 0) { $installed[0].Hold } else { $false }
    }
    $results += $state

    if ($Json) { continue }

    $tag = if ($state.Installed) { 'installed' } else { 'not installed' }
    brewMessage ''
    Write-BrewRaw "==> $($state.Name): $($state.Version) ($tag, bucket $($state.Bucket))" 'Cyan'
    if ($state.Description) { brewMessage $state.Description }
    if ($state.Homepage) { brewMessage $state.Homepage }
    if ($state.Installed) { brewMessage $state.Path }

    $source = Get-BrewKnownBucket $state.Bucket
    if ($source -and $source.repo) {
        brewMessage "From: https://github.com/$($source.repo)/blob/master/bucket/$($state.Name).json"
    }
    if ($state.License) { brewMessage "License: $($state.License)" }
    if ($state.Current -and $state.Current -ne $state.Version) {
        brewWarn "Outdated: installed $($state.Current), manifest has $($state.Version). Run 'brew upgrade $($state.Name)'."
    }
    if ($state.Depends.Count -gt 0) { brewMessage "Depends on: $($state.Depends -join ', ')" }
    if ($state.Suggest.Count -gt 0) { brewMessage "Recommended: $($state.Suggest -join ', ')" }
    foreach ($note in $state.Notes) { brewMessage "Notes: $note" }
}

if ($Json) {
    $results | ConvertTo-Json -Depth 6
}

exit $failed
