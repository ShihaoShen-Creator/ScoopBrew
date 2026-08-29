# Usage: brew which-formula <command>
# Summary: Find which packages shim an executable.
# Group: query
# Help: Searches the `bin` stanza of every manifest in the added buckets. The
#       extension is optional: `which-formula git` matches git.exe.
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Command,
    [switch]$Installed
)

Test-ScoopInstalled | Out-Null

$leaf = Split-Path -Leaf $Command
$stem = [System.IO.Path]::GetFileNameWithoutExtension($leaf)

$installedNames = @(Get-BrewInstalledPackages | ForEach-Object { $_.Name })

$index = Get-BrewPackageIndex
if ($Installed) { $index = @($index | Where-Object { $installedNames -contains $_.Name }) }

$found = 0
foreach ($entry in $index) {
    foreach ($binary in $entry.Binaries) {
        $binaryStem = [System.IO.Path]::GetFileNameWithoutExtension($binary)
        if ($binary -eq $leaf -or $binaryStem -eq $stem) {
            $mark = if ($installedNames -contains $entry.Name) { ' [installed]' } else { '' }
            Write-Host "$($entry.Bucket)/$($entry.Name)$mark $binary"
            $found = 1
            break
        }
    }
}

if ($found -eq 0) {
    brewMessage "No package in the added buckets provides '$Command'."
    brewMessage 'Try `brew search` for a name, or add a bucket with `brew tap <user>/<repo>`.'
    exit 1
}
