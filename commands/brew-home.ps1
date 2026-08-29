# Usage: brew home [<package>...]
# Summary: Open a package's homepage in the default browser.
# Group: query
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Packages
)

Test-ScoopInstalled | Out-Null

if (-not $Packages) {
    Start-Process 'https://scoop.sh'
    brewMessage 'Opened https://scoop.sh'
    exit 0
}

$failed = 0
foreach ($query in $Packages) {
    $pkg = Resolve-BrewPackage $query
    if (-not $pkg) { brewError "No available package named '$query'."; $failed = 1; continue }

    $url = [string]$pkg.Manifest.homepage
    if (-not $url) { brewError "$($pkg.Name) has no homepage in its manifest."; $failed = 1; continue }

    brewMessage "==> $url"
    Start-Process $url
}
exit $failed
