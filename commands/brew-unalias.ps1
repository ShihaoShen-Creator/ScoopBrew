# Usage: brew unalias <name>
# Summary: Remove a Scoop command alias.
# Group: meta
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)][string[]]$Names
)

Test-ScoopInstalled | Out-Null

$exit = 0
foreach ($name in (Get-BrewNameArgs $Names)) {
    $code = Invoke-Scoop alias rm $name
    if ($code -ne 0) { $exit = $code }
}
exit $exit
