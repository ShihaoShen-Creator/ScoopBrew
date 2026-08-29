# Usage: brew command <command>
# Summary: Print the script that implements a brew command.
# Group: meta
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Name
)

$local = Join-Path $CommandsDir "brew-$Name.ps1"
if (Test-Path -LiteralPath $local) {
    Write-Output (Get-Item -LiteralPath $local).FullName
    exit 0
}

$external = Get-Command "brew-$Name*" -ErrorAction SilentlyContinue |
    Where-Object { (Split-Path -Parent $_.Source) -ne $CommandsDir } |
    Select-Object -First 1
if ($external) {
    Write-Output $external.Source
    exit 0
}

Abort-Brew "Unknown command: brew $Name"
