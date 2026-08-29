# Usage: brew tab <package>
# Summary: Show the install record Scoop keeps for a package.
# Group: query
# Help: Scoop stores an `install.json` next to each installed version: the
#       architecture, the bucket or URL it came from, whether it is held, and
#       when it was last installed. That is the closest thing Homebrew's Tab has
#       to work with.
#
#   --installed        List installed packages with their recorded bucket.
#   --flatten          Emit one machine-readable line per package.
#   --include-manifest Include the stored manifest alongside the record.
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Packages,
    [switch]$Installed,
    [switch]$Flatten,
    [switch]$IncludeManifest
)

Test-ScoopInstalled | Out-Null

function Get-BrewInstallRecord {
    param([object]$Package)

    $appRoot = if ($Package.Global) { Get-BrewAppsDir -Global } else { Get-BrewAppsDir }
    $current = Join-Path (Join-Path $appRoot $Package.Name) 'current'
    $record = $null
    $recordPath = Join-Path $current 'install.json'
    if (Test-Path -LiteralPath $recordPath) {
        try { $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json } catch { $record = $null }
    }
    $manifest = $null
    $manifestPath = Join-Path $current 'manifest.json'
    if ($IncludeManifest -and (Test-Path -LiteralPath $manifestPath)) {
        try { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json } catch { $manifest = $null }
    }

    [pscustomobject]@{
        Package      = $Package.Name
        Version      = $Package.Version
        Architecture = [string]$record.architecture
        Bucket       = [string]$record.bucket
        Url          = [string]$record.url
        Held         = if ($record.hold -or $Package.Hold) { 'yes' } else { '' }
        Installed    = [string]$Package.Updated
        Global       = [bool]$Package.Global
        Manifest     = $manifest
    }
}

$targets = @()
if ($Installed -or -not $Packages) {
    $targets = @(Get-BrewInstalledPackages)
} else {
    $installedNames = @(Get-BrewInstalledPackages | ForEach-Object { $_.Name })
    foreach ($name in (Get-BrewNameArgs $Packages)) {
        $row = @($installedNames | Where-Object { $_ -eq $name })
        if ($row.Count -eq 0) {
            brewError "$name is not installed."
            brewMessage 'Homebrew only allows editing the tab of an installed package, and so does this.'
            exit 1
        }
        $targets += @(Get-BrewInstalledPackages -Query ('^' + [regex]::Escape($name) + '$'))
    }
}

if ($Flatten) {
    foreach ($pkg in $targets) {
        $record = Get-BrewInstallRecord -Package $pkg
        Write-Output "$($record.Package)`t$($record.Version)`t$($record.Bucket)`t$($record.Architecture)`t$($record.Installed)"
    }
    exit 0
}

$records = @($targets | ForEach-Object { Get-BrewInstallRecord -Package $_ })
if ($IncludeManifest) { $records | ConvertTo-Json -Depth 8; exit 0 }

Write-BrewTable -Rows $records -Properties @('Package', 'Version', 'Architecture', 'Bucket', 'Held', 'Installed') `
    -Headers @('Package', 'Version', 'Arch', 'Bucket', 'Held', 'Installed at')

brewMessage ''
brewMessage 'Homebrew also records whether a package was requested directly or pulled'
brewMessage 'in as a dependency, and `brew tab --installed-on-request` edits that.'
brewMessage 'Scoop stores no such field, so `brew autoremove` cannot be supported.'
