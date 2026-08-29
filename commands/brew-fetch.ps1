# Usage: brew fetch <package> [...]
# Summary: Download packages to Scoop's cache without installing them.
# Group: lifecycle
# Help: Options:
#   --no-checksums    Redundant: Scoop verifies hashes from the manifest.
#   --deps            Also download the dependencies.
#   --force           Redownload even when already cached.
param(
    [switch]$Deps,
    [switch]$Force,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Tokens
)

Test-ScoopInstalled | Out-Null

$names = @(Get-BrewNameArgs $Tokens)
$flags = @(Get-BrewFlagArgs $Tokens)
Show-DroppedFlags -Dropped @($flags | Where-Object { $_ -notin @('--force', '--deps') })

if ($names.Count -eq 0) { Abort-Brew 'This command requires a package name.' }

if ($Deps) {
    $expanded = @()
    foreach ($name in $names) {
        $expanded += @(Get-BrewDependencies -Name $name | ForEach-Object { $_.Name })
    }
    $names = @(@($names) + $expanded | Select-Object -Unique)
}

$scoopArgs = @('download')
if ($Force) { $scoopArgs += '--force' }
$scoopArgs += $names

exit (Invoke-Scoop @($scoopArgs))
