# Usage: brew tap-info [<bucket>]
# Summary: Show information about added or known Scoop buckets.
# Group: query
# Help: Options:
#   --installed    Only list buckets that are added.
#   --available    Only list buckets known to Scoop but not added.
#   --json         Emit machine-readable output.
param(
    [Parameter(Position = 0)][string]$Name,
    [switch]$Installed,
    [switch]$Available,
    [switch]$Json
)

Test-ScoopInstalled | Out-Null

$added = @(Get-BrewBuckets)

if ($Name) {
    # Resolve the name the way `brew tap` does, keeping the literal name as a
    # fallback for buckets added outside the tap map.
    $candidates = @()
    $resolved = Resolve-BrewTapName -Name $Name
    if ($resolved) { $candidates += $resolved.Local }
    if ($candidates -notcontains $Name) { $candidates += $Name }

    $match = @()
    foreach ($candidate in $candidates) {
        $match = @($added | Where-Object { $_.Name -eq $candidate })
        if ($match.Count -gt 0) { break }
    }
    if ($match.Count -eq 0) {
        foreach ($candidate in $candidates) {
            $known = Get-BrewKnownBucket $candidate
            if ($known) {
                brewMessage "$candidate (not added)"
                brewMessage "  URL: https://github.com/$($known.repo)"
                brewMessage "  Maintainer: $($known.name)"
                brewMessage ''
                brewMessage "Add it with: brew tap $candidate"
                exit 0
            }
        }
        Abort-Brew "Unknown bucket: $Name"
    }

    $bucket = $match[0]

    Write-BrewRaw "==> $($bucket.Name)" 'Cyan'
    brewMessage "  Path:     $($bucket.Path)"
    brewMessage "  Source:   $($bucket.Source)"
    brewMessage "  Packages: $($bucket.Packages)"
    $fromHere = @(Get-BrewInstalledPackages | Where-Object { $_.Bucket -eq $bucket.Name })
    if ($fromHere.Count -gt 0) { brewMessage "  Installed from this bucket: $($fromHere.Name -join ', ')" }
    exit 0
}

$rows = $added
if ($Available) {
    $knownNames = @(Get-BrewKnownBuckets.PSObject.Properties.Name)
    $rows = @($knownNames | Where-Object { $added.Name -notcontains $_ } | ForEach-Object {
        $known = Get-BrewKnownBucket $_
        [pscustomobject]@{ Name = $_; Source = "https://github.com/$($known.repo)"; Path = $null; Packages = 0 }
    })
    if ($Json) { $rows | ConvertTo-Json -Depth 4; exit 0 }
    if ($rows.Count -eq 0) { brewMessage 'Every known bucket is already added.'; exit 0 }
    brewMessage '==> Known buckets, not added'
    Write-BrewTable -Rows $rows -Properties @('Name', 'Source') -Headers @('Name', 'Source')
    exit 0
}

if ($Json) { $rows | ConvertTo-Json -Depth 4; exit 0 }

if ($rows.Count -eq 0) { brewMessage 'No buckets are added.'; exit 0 }
Write-BrewTable -Rows $rows -Properties @('Name', 'Packages', 'Source') -Headers @('Name', 'Packages', 'Source')
