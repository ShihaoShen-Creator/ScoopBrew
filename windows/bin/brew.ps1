#!/usr/bin/env pwsh
# brew - Homebrew command surface on top of Scoop.
#Requires -Version 5

param([Parameter(ValueFromRemainingArguments = $true)][object[]]$RawArgs)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

$tokens = @()
foreach ($token in @($RawArgs)) {
    if ($null -eq $token) { continue }
    if ($token -eq '--no-color') { $env:NO_COLOR = '1'; continue }
    if ($token -in @('--verbose', '--quiet', '--debug')) { continue }
    $tokens += [string]$token
}

Import-Module (Join-Path $PSScriptRoot '..\lib\ScoopBrew.psm1') -DisableNameChecking

$BrewCommandsDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'commands'

$command = if ($tokens.Count -gt 0) { $tokens[0] } else { $null }
$rest = @()
if ($tokens.Count -gt 1) { $rest = @($tokens | Select-Object -Skip 1) }

function Get-BrewCommandScript {
    param([string]$Name)

    $local = Join-Path $BrewCommandsDir "brew-$Name.ps1"
    if (Test-Path -LiteralPath $local) { return (Get-Item -LiteralPath $local).FullName }

    # Homebrew's external command contract: an executable named brew-<cmd>
    # anywhere on PATH is a valid command.
    foreach ($suffix in @('ps1', 'cmd', 'exe')) {
        $external = Get-Command "brew-$Name.$suffix" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $external -or -not $external.Source) { continue }
        if ((Split-Path -Parent $external.Source) -eq $BrewCommandsDir) { continue }
        return $external.Source
    }
    return $null
}

function Get-BrewCommandHeader {
    param([string]$Path)

    $header = [ordered]@{ Usage = $null; Summary = $null; Help = @() }
    $inHelp = $false
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line -match '^#\s*Usage:\s*(.+)$') { $header.Usage = $Matches[1].Trim(); continue }
        if ($line -match '^#\s*Summary:\s*(.+)$') { $header.Summary = $Matches[1].Trim(); continue }
        if ($line -match '^#\s*Help:\s*(.*)$') {
            $inHelp = $true
            if ($Matches[1]) { $header.Help += $Matches[1] }
            continue
        }
        if ($inHelp) {
            if ($line -match '^#\s?(.*)$') { $header.Help += $Matches[1] } else { $inHelp = $false }
        }
    }
    return $header
}

function Show-BrewUsage {
    brewMessage 'Usage: brew <command> [<options>] [<package>]'
    brewMessage ''
    brewMessage 'The Homebrew command surface, backed by Scoop on Windows.'
    brewMessage "Run 'brew help <command>' for details, or 'brew commands' for the full list."
}

function Show-BrewVersion {
    Test-ScoopInstalled | Out-Null
    brewMessage "ScoopBrew $BrewVersion"
    brewMessage "Scoop $(Get-BrewScoopVersion) ($(Get-BrewScoopRoot))"
    brewMessage 'Homebrew command surface v6.0.20'
}

function Show-BrewCommandHelp {
    param([string]$Name, [string]$Path)

    $header = Get-BrewCommandHeader -Path $Path
    if ($header.Usage) { brewMessage "Usage: $($header.Usage)" } else { brewMessage "Usage: brew $Name" }
    if ($header.Summary) {
        brewMessage ''
        brewMessage "  $($header.Summary)"
    }
    if ($header.Help.Count -gt 0) {
        brewMessage ''
        foreach ($line in $header.Help) { brewMessage "  $line" }
    }
}

if (-not $command) {
    Show-BrewUsage
    exit 1
}

if ($command -in @('-h', '--help', '/?')) {
    if ($rest.Count -gt 0) {
        $target = Get-BrewCommandScript -Name $rest[0]
        if ($target) { Show-BrewCommandHelp -Name $rest[0] -Path $target; exit 0 }
    }
    Show-BrewUsage
    exit 0
}

if ($command -in @('-v', '--version', 'version')) {
    Show-BrewVersion
    exit 0
}

if ($command -eq 'help') {
    if ($rest.Count -gt 0) {
        $targetName = $rest[0]
        $target = Get-BrewCommandScript -Name $targetName
        if (-not $target) { Abort-Brew "No such command: $targetName" }
        Show-BrewCommandHelp -Name $targetName -Path $target
        exit 0
    }
    Show-BrewUsage
    exit 0
}

if ($command -match '[\\/]' -or $command -like '*..*' -or $command -notmatch '^[a-zA-Z0-9@_.-]+$') {
    Abort-Brew "Invalid command name: $command"
}

$alias = Get-BrewCommandAlias -Name $command
if ($alias) { $command = $alias }

$scriptPath = Get-BrewCommandScript -Name $command
if (-not $scriptPath) {
    $reason = Get-BrewUnsupportedCommand -Name $command
    if ($reason) {
        brewError "brew $command is not supported by the Scoop backend."
        brewMessage ''
        brewMessage "  $reason"
        exit 1
    }

    $available = Get-ChildItem $BrewCommandsDir -Filter 'brew-*.ps1' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.BaseName -replace '^brew-', '' }

    brewError "Unknown command: brew $command"
    $near = @($available | Where-Object { $_ -like "$command*" } | Select-Object -First 5)
    if ($near.Count -eq 0) { $near = @($available | Where-Object { $_ -like "*$command*" } | Select-Object -First 5) }
    if ($near.Count -gt 0) {
        brewMessage ''
        brewMessage 'Did you mean one of these?'
        foreach ($n in $near) { brewMessage "    brew $n" }
    }
    brewMessage ''
    brewMessage "Run 'brew commands' for the full list."
    exit 1
}

if ($rest.Count -eq 1 -and $rest[0] -in @('-h', '--help', '/?')) {
    Show-BrewCommandHelp -Name $command -Path $scriptPath
    exit 0
}

function Get-BrewScriptLayout {
    <#
        Positional metadata is not exposed for script parameters on Windows
        PowerShell 5.1 (Position and ValueFromRemainingArguments come back
        null), so read them from the AST instead.
    #>
    param([string]$Path)

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $Path, [ref]$tokens, [ref]$parseErrors)

    $layout = [pscustomobject]@{
        Positional = @()
        Remaining  = $null
    }

    $blocks = @($ast.FindAll({
        param($node) $node -is [System.Management.Automation.Language.ParamBlockAst]
    }, $true))
    if ($blocks.Count -eq 0) { return $layout }

    $ordered = @()
    foreach ($param in $blocks[0].Parameters) {
        $name = $param.Name.VariablePath.UserPath
        $position = $null

        foreach ($attr in @($param.Attributes)) {
            if ($attr -isnot [System.Management.Automation.Language.AttributeAst]) { continue }
            if ($attr.TypeName.Name -notmatch '^Parameter$') { continue }

            # PowerShell 5.1 populates neither Name nor Expression on
            # NamedArguments here, so read the attribute source instead.
            $text = $attr.Extent.Text
            if ($text -match 'Position\s*=\s*(-?\d+)') { $position = [int]$Matches[1] }
            if ($text -match 'ValueFromRemainingArguments\s*=\s*\$true') { $layout.Remaining = $name }
        }

        if ($null -ne $position) {
            $ordered += [pscustomobject]@{ Position = $position; Name = $name }
        }
    }

    $layout.Positional = @($ordered | Sort-Object Position | ForEach-Object { $_.Name })
    return $layout
}

function Split-BrewTokens {
    <#
        Separate GNU-style tokens into named parameters and positional values.
        A hashtable splat is required downstream: PowerShell passes array
        elements positionally, so an array splat cannot bind `-Desc` by name.
    #>
    param([string[]]$Tokens, [object]$Parameters, [object]$Layout)

    $bound = [ordered]@{}
    $positional = @()
    $pending = $null

    if (-not $Parameters) {
        return [pscustomobject]@{ Bound = $bound; Positional = @($Tokens) }
    }

    $aliases = @{}
    foreach ($parameter in $Parameters.Values) {
        foreach ($alias in @($parameter.Aliases)) {
            if ($alias -and -not $aliases.ContainsKey($alias)) { $aliases[$alias] = $parameter.Name }
        }
    }

    foreach ($token in $Tokens) {
        if ($pending) { $bound[$pending] = $token; $pending = $null; continue }

        if ($token -notmatch '^-{1,2}[a-zA-Z]') { $positional += $token; continue }

        $flag = $token
        $inline = $null
        if ($token -match '^--[^=]+=(.*)$') {
            $flag = $token.Substring(0, $token.IndexOf('='))
            $inline = $Matches[1]
        }

        $bare = $flag -replace '^-+', ''
        $camel = (($bare -split '-') | ForEach-Object {
            if ($_) { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }
        }) -join ''

        $name = $null
        if ($Parameters.ContainsKey($camel)) { $name = $camel }
        elseif ($Parameters.ContainsKey($bare)) { $name = $bare }
        elseif ($aliases.ContainsKey($bare)) { $name = $aliases[$bare] }

        if (-not $name) {
            # Not a brew option: keep it so passthrough commands can forward it.
            $positional += $token
            continue
        }

        $parameter = $Parameters[$name]
        if ($parameter.ParameterType.Name -eq 'SwitchParameter') { $bound[$name] = $true; continue }
        if ($null -ne $inline) { $bound[$name] = $inline; continue }

        $pending = $name
    }

    if ($pending) { $bound[$pending] = $true }

    return [pscustomobject]@{ Bound = $bound; Positional = $positional }
}

function Complete-BrewBinding {
    <#
        Give the leftover positional tokens their parameter names so everything
        travels in one hashtable splat.
    #>
    param([object]$Parameters, [object]$Bound, [string[]]$Positional, [object]$Layout)

    if (-not $Parameters -or $Positional.Count -eq 0) { return $Bound }

    $index = 0
    foreach ($name in @($Layout.Positional)) {
        if ($index -ge $Positional.Count) { break }
        if ($Bound.Contains($name)) { continue }

        $parameter = $Parameters[$name]
        if ($parameter.ParameterType.IsArray) {
            $Bound[$name] = @($Positional | Select-Object -Skip $index)
            return $Bound
        }

        $Bound[$name] = $Positional[$index]
        $index++
    }

    $left = @($Positional | Select-Object -Skip $index)
    if ($left.Count -eq 0) { return $Bound }

    # A command with a catch-all parameter keeps the rest, including
    # unrecognised options destined for Scoop.
    if ($Layout.Remaining) {
        $existing = @()
        if ($Bound.Contains($Layout.Remaining)) { $existing = @($Bound[$Layout.Remaining]) }
        $Bound[$Layout.Remaining] = @($existing + $left)
        return $Bound
    }

    Abort-Brew "Unexpected argument: $($left[0])"
}

$global:LASTEXITCODE = 0

$target = Get-Command -Name $scriptPath -CommandType ExternalScript -ErrorAction SilentlyContinue
$parameters = if ($target) { $target.Parameters } else { $null }

try {
    if (-not $parameters) {
        & $scriptPath @($rest)
    } else {
        $layout = Get-BrewScriptLayout -Path $scriptPath
        $split = Split-BrewTokens -Tokens $rest -Parameters $parameters -Layout $layout
        $bound = Complete-BrewBinding -Parameters $parameters -Bound $split.Bound `
            -Positional $split.Positional -Layout $layout

        if ($bound.Count -gt 0) { & $scriptPath @bound } else { & $scriptPath }
    }
} catch [System.Management.Automation.ParameterBindingException] {
    brewError "brew $command : $($_.Exception.Message)"
    $header = Get-BrewCommandHeader -Path $scriptPath
    if ($header.Usage) { brewMessage "Usage: $($header.Usage)" }
    brewMessage "Run 'brew help $command' for the full option list."
    exit 1
} catch {
    brewError "brew $command failed: $($_.Exception.Message)"
    exit 1
}

if ($null -eq $LASTEXITCODE) { exit 0 }
exit $LASTEXITCODE
