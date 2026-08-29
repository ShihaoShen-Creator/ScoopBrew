# Usage: brew which <command>
# Summary: Show the path a command resolves to and which package provides it.
# Group: query
# Help: Resolves like a shell would, but with the Scoop shim directories always
#       searched first, so the answer does not depend on whether PATH has been
#       configured yet. `scoop which` by contrast only reports what PATH can
#       already resolve.
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Command,
    [switch]$Installed
)

Test-ScoopInstalled | Out-Null

$prepend = @((Get-BrewShimDir))
$globalRoot = Get-GlobalScoopRoot
if ($globalRoot) { $prepend += (Join-Path $globalRoot 'shims') }

$savedPath = $env:PATH
try {
    $env:PATH = (($prepend -join ';') + ';' + $env:PATH)
    $resolved = Get-Command $Command -ErrorAction SilentlyContinue | Select-Object -First 1
} finally {
    $env:PATH = $savedPath
}

if (-not $resolved) {
    brewMessage "No command '$Command' found."
    brewMessage 'Try: brew which-formula <command> to see which package would provide it.'
    exit 1
}

# Only report the owning package when it came from the Scoop shim directory.
$owner = $null
foreach ($dir in $prepend) {
    if ((Split-Path -Parent $resolved.Source) -ne $dir) { continue }
    $leaf = Split-Path -Leaf $resolved.Source
    foreach ($pkg in @(Get-BrewInstalledPackages)) {
        $manifest = (Resolve-BrewPackage $pkg.Name).Manifest
        if (-not $manifest) { continue }
        if (@(Get-BrewBinaries $manifest (Get-BrewArchitecture)) -contains $leaf) { $owner = $pkg; break }
    }
    break
}

Write-Output $resolved.Source
if ($owner) {
    brewMessage "  provided by: $($owner.Bucket)/$($owner.Name) $($owner.Version)"
}
