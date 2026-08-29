# Usage: brew commands
# Summary: List all commands provided by the Scoop backend.
# Help: Prints every brew subcommand implemented for Windows, with the summary
#       declared by each command.
param([switch]$IncludeAliases, [switch]$Quiet)

$entries = @()
foreach ($file in (Get-ChildItem $CommandsDir -Filter 'brew-*.ps1' | Sort-Object Name)) {
    $name = $file.BaseName -replace '^brew-', ''
    $summary = ''
    $group = 'commands'
    foreach ($line in (Get-Content -LiteralPath $file.FullName)) {
        if ($line -match '^#\s*Summary:\s*(.+)$') { $summary = $Matches[1].Trim() }
        elseif ($line -match '^#\s*Group:\s*(.+)$') { $group = $Matches[1].Trim() }
        elseif ($line -notmatch '^#') { break }
    }
    $entries += [pscustomobject]@{ Group = $group; Command = "brew $name"; Summary = $summary }
}

if ($Quiet) {
    foreach ($entry in $entries) { Write-Output $entry.Command }
    exit 0
}

brewMessage 'Homebrew commands, Scoop backend:'
brewMessage ''

foreach ($section in ($entries | Group-Object Group | Sort-Object Name)) {
    brewMessage $section.Name
    $width = ($section.Group | ForEach-Object { $_.Command.Length } | Measure-Object -Maximum).Maximum
    foreach ($entry in $section.Group) {
        $fmt = ('{{0,-{0}}}  {{1}}' -f $width)
        Write-Host ($fmt -f $entry.Command, $entry.Summary)
    }
    brewMessage ''
}

if ($IncludeAliases) {
    brewMessage 'Aliases (same meaning as on Homebrew):'
    $aliases = Get-BrewCommandAliases
    $aliasRows = @()
    foreach ($key in $aliases.Keys) {
        $aliasRows += [pscustomobject]@{ Alias = "brew $key"; Resolves = "brew $($aliases[$key])" }
    }
    Write-BrewTable -Rows $aliasRows -Properties @('Alias', 'Resolves') -Headers @('Alias', 'Resolves')
}
