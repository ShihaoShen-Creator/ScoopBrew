# Usage: brew alias [<name> <command>]
# Summary: List or define Scoop command aliases.
# Group: meta
# Help: `brew alias` with no arguments lists aliases; with a name and a command
#       it defines one. Homebrew and Scoop share the same shape: an alias expands
#       to a full command line.
#
#   --no-rename   Redundant: Scoop has no interactive alias rename prompt.
param(
    [Parameter(Position = 0)][string]$Name,
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest,
    [switch]$NoRename
)

Test-ScoopInstalled | Out-Null

if ($NoRename) { brewWarn '--no-rename has no meaning for Scoop aliases.' }

if (-not $Name) { exit (Invoke-Scoop alias list) }

if (-not $Rest) {
    $rows = @(Invoke-Scoop -Capture alias list)
    $match = @($rows | Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s" })
    if ($match.Count -eq 0) { Abort-Brew "No alias named '$Name'." }
    foreach ($line in $match) { Write-Output ([string]$line) }
    exit 0
}

# `brew alias ll ls -la` becomes `scoop alias add ll ls -la`.
exit (Invoke-Scoop @(@('alias', 'add', $Name) + @($Rest)))
