# Usage: brew deps [<package>...]
# Summary: List the dependencies of a package.
# Group: query
# Help: Resolves the recursive `depends` graph from Scoop manifests, in the
#       order Scoop would install them.
#
#   --1                 Only direct dependencies.
#   --tree              Show the nested dependency tree.
#   --include-suggested Include the manifest's `suggest` recommendations.
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Packages,
    [switch]$Direct,
    [switch]$Tree,
    [switch]$IncludeSuggested
)

Test-ScoopInstalled | Out-Null

if (-not $Packages) { Abort-Brew 'This command requires a package name.' }

foreach ($query in $Packages) {
    $pkg = Resolve-BrewPackage $query
    if (-not $pkg) { brewError "No available package named '$query'."; exit 1 }

    $deps = @(Get-BrewDependencies -Name $pkg.Name -Optional:$IncludeSuggested)
    if ($Direct) { $deps = @($deps | Where-Object { $_.Direct }) }

    if ($deps.Count -eq 0) {
        brewMessage "$($pkg.Name): no dependencies"
        continue
    }

    if ($Tree) {
        brewMessage "$($pkg.Name)@$($pkg.Version)"
        foreach ($dep in ($deps | Where-Object { $_.Package -eq $pkg.Name } | Sort-Object Name)) {
            brewMessage "==> $($dep.Name)"
            foreach ($sub in ($deps | Where-Object { $_.Package -eq $dep.Name } | Sort-Object Name)) {
                brewMessage "  ==> $($sub.Name)"
            }
        }
        continue
    }

    foreach ($dep in $deps | Select-Object -ExpandProperty Name -Unique) { Write-Output $dep }
}
