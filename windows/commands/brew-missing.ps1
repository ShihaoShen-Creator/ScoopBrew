# Usage: brew missing
# Summary: List installed packages whose dependencies are not installed.
# Group: query
# Help: Scoop installs dependencies automatically, so an unmet dependency
#       usually means the dependency was removed by hand.
param()

Test-ScoopInstalled | Out-Null

$installedNames = @(Get-BrewInstalledPackages | ForEach-Object { $_.Name })
$found = 0

foreach ($pkg in $installedNames) {
    $deps = @(ConvertTo-BrewList (Resolve-BrewPackage $pkg).Manifest.depends)
    $absent = @($deps | Where-Object {
        $leaf = ($_ -split '/')[-1]
        $installedNames -notcontains $leaf
    })
    if ($absent.Count -eq 0) { continue }
    $found = 1
    Write-Host "$pkg $($absent -join ' ')"
}

if ($found -eq 0) { exit 0 }

brewMessage ''
brewMessage "Run 'brew install <package>' to install a missing dependency."
exit 1
