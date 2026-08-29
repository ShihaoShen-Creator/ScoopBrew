# Usage: brew source [<package>...]
# Summary: Open a package's source repository in the browser.
# Group: query
# Help: The repository is derived from the manifest download URL, falling back
#       to its homepage. With no package, Scoop's own repository is opened.
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Packages
)

Test-ScoopInstalled | Out-Null

function Get-BrewSourceRepository {
    param([string]$Url, [string]$Homepage)

    foreach ($candidate in @($Url, $Homepage)) {
        if (-not $candidate) { continue }
        # GitHub release/archive and GitLab/Bitbucket project URLs all start
        # with the project path, so trim everything after the owner/repo pair.
        if ($candidate -match '^(?<base>https?://[^/]+/[^/]+/[^/?#]+)') {
            return ($Matches['base'] -replace '\.git$', '')
        }
    }
    return $null
}

if (-not $Packages) {
    $url = 'https://github.com/ScoopInstaller/Scoop'
    brewMessage "==> $url"
    Start-Process $url
    exit 0
}

$failed = 0
foreach ($query in $Packages) {
    $pkg = Resolve-BrewPackage $query
    if (-not $pkg) { brewError "No available package named '$query'."; $failed = 1; continue }

    $arch = Get-BrewArchitecture
    $url = Get-BrewManifestScalar $pkg.Manifest 'url' $arch
    $repo = Get-BrewSourceRepository -Url $url -Homepage ([string]$pkg.Manifest.homepage)

    if (-not $repo) {
        brewError "$($pkg.Name) has no recognisable source repository (owner/project) in its manifest."
        $failed = 1
        continue
    }

    brewMessage "==> $repo"
    Start-Process $repo
}
exit $failed
