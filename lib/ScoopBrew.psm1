# ScoopBrew: a brew-compatible CLI whose package engine is Scoop.
#
# Everything goes through the `scoop` command line, plus the two plain data
# formats Scoop documents on disk: bucket manifests (buckets/<name>/*.json) and
# `scoop export` for installed state. No Scoop PowerShell function is called, so
# a Scoop release that renames its internals cannot break this layer.

Set-StrictMode -Off

$script:BrewVersion = '0.1.0'
$script:BrewIndexVersion = 3
$script:BrewRoot = Split-Path -Parent $PSScriptRoot
$script:CommandsDir = Join-Path $script:BrewRoot 'commands'
$script:StateDir = if ($env:SCOOPBREW_STATE) { $env:SCOOPBREW_STATE } else { Join-Path $env:LOCALAPPDATA 'scoopbrew' }
$script:NoColor = [bool]$env:NO_COLOR

#region scoop discovery

function Find-ScoopInstallation {
    $roots = @()
    if ($env:SCOOP) { $roots += $env:SCOOP }
    if ($env:USERPROFILE) { $roots += (Join-Path $env:USERPROFILE 'scoop') }
    if ($env:ProgramData) { $roots += (Join-Path $env:ProgramData 'scoop') }

    # Respect root_path so a relocated Scoop is still found.
    foreach ($candidate in $roots) {
        $config = Join-Path $candidate 'config.json'
        if (Test-Path -LiteralPath $config) {
            try {
                $configured = (Get-Content -LiteralPath $config -Raw | ConvertFrom-Json).root_path
                if ($configured) { $roots += $configured }
            } catch { }
        }
    }

    foreach ($root in $roots) {
        $cli = Join-Path $root 'apps/scoop/current/bin/scoop.ps1'
        if (Test-Path -LiteralPath $cli) {
            return [pscustomobject]@{
                Root    = $root
                Cli     = (Get-Item -LiteralPath $cli).FullName
                Host    = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
            }
        }
        $shim = Join-Path $root 'shims/scoop.ps1'
        if (Test-Path -LiteralPath $shim) {
            return [pscustomobject]@{
                Root    = $root
                Cli     = (Get-Item -LiteralPath $shim).FullName
                Host    = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
            }
        }
    }
    return $null
}

$script:Scoop = Find-ScoopInstallation

# Per-process memo: several commands resolve every installed package, and each
# lookup would otherwise re-enumerate the buckets or re-launch `scoop export`.
$script:Memo = @{}

#endregion

#region output

function Write-BrewRaw {
    param([string]$Message, [string]$Color)
    if ($Color -and -not $script:NoColor) { Write-Host $Message -ForegroundColor $Color }
    else { Write-Host $Message }
}

function brewMessage { param([string]$Message) Write-BrewRaw $Message $null }
function brewSuccess { param([string]$Message) Write-BrewRaw $Message 'DarkGreen' }
function brewWarn { param([string]$Message) Write-BrewRaw "Warning: $Message" 'DarkYellow' }
function brewError { param([string]$Message) Write-BrewRaw "Error: $Message" 'Red' }

function Abort-Brew {
    param([string]$Message, [int]$ExitCode = 1)
    brewError $Message
    exit $ExitCode
}

function Write-BrewTextFile {
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Path,
        [Parameter(Position = 1)][object[]]$Content
    )

    # Windows PowerShell's `Set-Content -Encoding UTF8` writes a BOM, which
    # shows up in diffs and breaks readers that expect plain UTF-8. Blank lines
    # are meaningful here, so they must survive.
    $lines = @()
    foreach ($line in @($Content)) { $lines += [string]$line }

    # .NET's working directory does not follow PowerShell's location, and the
    # target may not exist yet, so resolve without requiring it.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $absolute = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    [System.IO.File]::WriteAllText($absolute, (($lines -join "`r`n") + "`r`n"), $utf8NoBom)
}

function Write-BrewTable {
    param([object[]]$Rows, [string[]]$Properties, [string[]]$Headers)
    if (-not $Rows -or $Rows.Count -eq 0) { return }

    $widths = @()
    for ($i = 0; $i -lt $Properties.Count; $i++) {
        $title = if ($Headers) { $Headers[$i] } else { $Properties[$i] }
        $max = $title.Length
        foreach ($row in $Rows) {
            $len = ([string]$row.($Properties[$i])).Length
            if ($len -gt $max) { $max = $len }
        }
        $widths += $max
    }

    $fmt = ''
    for ($i = 0; $i -lt $Properties.Count; $i++) {
        if ($i -gt 0) { $fmt += '  ' }
        $fmt += ('{{{0},-{1}}}' -f $i, $widths[$i])
    }

    if ($Headers) { Write-Host ($fmt -f $Headers) -ForegroundColor 'DarkGray' }
    foreach ($row in $Rows) {
        $values = for ($i = 0; $i -lt $Properties.Count; $i++) { [string]$row.($Properties[$i]) }
        Write-Host ($fmt -f $values)
    }
}

#endregion

#region scoop cli

function Test-ScoopInstalled {
    if ($script:Scoop) { return $true }
    Abort-Brew @"
Scoop is not installed. Install it first:
    powershell -Command "iwr get.scoop.sh | iex"
See https://scoop.sh for options. Set `$env:SCOOP if Scoop lives outside `$env:USERPROFILE\scoop.
"@
    return $false
}

function Get-BrewScoopRoot {
    Test-ScoopInstalled | Out-Null
    return $script:Scoop.Root
}

function Get-BrewScoopCoreDir {
    Test-ScoopInstalled | Out-Null
    $candidate = Join-Path (Get-BrewScoopRoot) 'apps/scoop/current'
    if (Test-Path -LiteralPath $candidate) { return (Get-Item -LiteralPath $candidate).FullName }
    return (Split-Path -Parent (Split-Path -Parent $script:Scoop.Cli))
}

function Get-BrewScoopVersion {
    Test-ScoopInstalled | Out-Null
    $changelog = Join-Path (Get-BrewScoopCoreDir) 'CHANGELOG.md'
    if (Test-Path -LiteralPath $changelog) {
        $match = Select-String -Pattern '^## \[(v[\d.]+)\]' -Path $changelog | Select-Object -First 1
        if ($match) { return ($match.Matches.Groups[1].Value -replace '^v', '') }
    }
    return 'unknown'
}

# Run Scoop. Output is not redirected by default so that progress, colours and
# interactive prompts survive; -Capture opts in to receiving the text, and
# -PassThru returns the exit code together with the redirected output.
function Invoke-Scoop {
    param(
        [switch]$Capture,
        [switch]$PassThru,
        [Parameter(ValueFromRemainingArguments = $true)][object[]]$ScoopArgs
    )

    Test-ScoopInstalled | Out-Null

    # ValueFromRemainingArguments collects a passed array as ONE element, so
    # flatten before stringifying or Scoop sees 'install 7zip' as one argument.
    $argList = @()
    foreach ($arg in @($ScoopArgs)) {
        if ($null -eq $arg) { continue }
        if ($arg -is [System.Collections.IEnumerable] -and $arg -isnot [string]) {
            foreach ($inner in $arg) {
                if ($null -ne $inner -and [string]$inner -ne '') { $argList += [string]$inner }
            }
            continue
        }
        if ([string]$arg -ne '') { $argList += [string]$arg }
    }

    if ($Capture) {
        return & $script:Scoop.Host '-NoProfile' '-NoLogo' '-ExecutionPolicy' 'Bypass' '-File' $script:Scoop.Cli @argList
    }

    # Windows PowerShell joins an argument array with spaces and escapes
    # nothing, so quote anything the child parser would split on.
    $quoted = @($argList | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    })
    $argumentList = @('-NoProfile', '-NoLogo', '-ExecutionPolicy', 'Bypass', '-File', $script:Scoop.Cli) + $quoted

    if ($PassThru) {
        # `scoop checkup` always exits 0 and reports through Write-Host, which
        # only becomes readable output when the child console is redirected.
        $outFile = [System.IO.Path]::GetTempFileName()
        $errFile = [System.IO.Path]::GetTempFileName()
        try {
            $process = Start-Process -FilePath $script:Scoop.Host `
                -ArgumentList $argumentList `
                -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $outFile -RedirectStandardError $errFile
            $output = @()
            if ((Get-Item -LiteralPath $outFile).Length -gt 0) {
                $output = @(Get-Content -LiteralPath $outFile)
            }
            return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output }
        } finally {
            Remove-Item -LiteralPath @($outFile, $errFile) -Force -ErrorAction SilentlyContinue
        }
    }

    $process = Start-Process -FilePath $script:Scoop.Host `
        -ArgumentList $argumentList -NoNewWindow -Wait -PassThru
    return $process.ExitCode
}

function Get-ScoopJson {
    <#
        Run a Scoop command that prints JSON (`export`, `cat`) and return the
        parsed object, or $null when the command failed.
    #>
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$ScoopArgs)

    $text = @(Invoke-Scoop -Capture @($ScoopArgs)) -join "`n"
    if (-not $text.Trim()) { return $null }
    try { return $text | ConvertFrom-Json } catch { return $null }
}

function Get-BrewArchitecture {
    if ($env:SCOOPBREW_ARCH -in @('32bit', '64bit', 'arm64')) { return $env:SCOOPBREW_ARCH }
    if ([Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE') -eq 'ARM64') { return 'arm64' }
    if ([Environment]::Is64BitOperatingSystem) { return '64bit' }
    return '32bit'
}

#endregion

#region scoop directories

function Get-BrewAppsDir {
    param([switch]$Global)
    if ($Global) { return (Join-Path (Get-GlobalScoopRoot) 'apps') }
    return (Join-Path (Get-BrewScoopRoot) 'apps')
}

function Get-BrewShimDir {
    param([switch]$Global)
    if ($Global) { return (Join-Path (Get-GlobalScoopRoot) 'shims') }
    return (Join-Path (Get-BrewScoopRoot) 'shims')
}

function Get-BrewBucketsDir { Join-Path (Get-BrewScoopRoot) 'buckets' }
function Get-BrewCacheDir {
    if ($env:SCOOP_CACHE) { return $env:SCOOP_CACHE }
    Join-Path (Get-BrewScoopRoot) 'cache'
}

function Get-GlobalScoopRoot {
    if ($env:SCOOP_GLOBAL) { return $env:SCOOP_GLOBAL }
    if ($env:ProgramData) { return (Join-Path $env:ProgramData 'scoop') }
    return $null
}

function Get-BrewBucketDir {
    param([string]$Name)
    $root = Join-Path (Get-BrewBucketsDir) $Name
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    # Newer buckets keep manifests in a `bucket` subdirectory.
    $nested = Join-Path $root 'bucket'
    if (Test-Path -LiteralPath $nested) { return $nested }
    return $root
}

#endregion

#region package data

function Get-BrewBuckets {
    Test-ScoopInstalled | Out-Null
    if ($script:Memo.ContainsKey('buckets')) { return $script:Memo['buckets'] }

    $rows = @()
    $root = Get-BrewBucketsDir
    foreach ($dir in @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue)) {
        $manifestDir = Get-BrewBucketDir -Name $dir.Name
        $count = 0
        if ($manifestDir) { $count = @(Get-ChildItem $manifestDir -Filter '*.json' -Recurse -ErrorAction SilentlyContinue).Count }

        $source = $null
        $gitConfig = Join-Path $dir.FullName '.git/config'
        if (Test-Path -LiteralPath $gitConfig) {
            $config = Get-Content -LiteralPath $gitConfig -Raw -ErrorAction SilentlyContinue
            if ($config -match 'url\s*=\s*(\S+)') { $source = $Matches[1] }
        }
        $known = Get-BrewKnownBucket $dir.Name
        if (-not $source -and $known -and $known.repo) { $source = "https://github.com/$($known.repo)" }

        $rows += [pscustomobject]@{
            Name     = $dir.Name
            Source   = $source
            Path     = $dir.FullName
            Packages = $count
        }
    }

    $script:Memo['buckets'] = $rows
    return $rows
}

function Get-BrewKnownBuckets {
    Test-ScoopInstalled | Out-Null
    if ($script:Memo.ContainsKey('knownBuckets')) { return $script:Memo['knownBuckets'] }

    $file = Join-Path (Get-BrewScoopRoot) 'apps/scoop/current/buckets.json'
    $known = $null
    if (Test-Path -LiteralPath $file) {
        try { $known = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json } catch { $known = $null }
    }
    $script:Memo['knownBuckets'] = $known
    return $known
}

function Get-BrewKnownBucket {
    param([string]$Name)

    $known = Get-BrewKnownBuckets
    if (-not $known) { return $null }
    return $known.$Name
}

function Get-BrewExportedApps {
    param([switch]$Refresh)

    Test-ScoopInstalled | Out-Null
    if (-not $Refresh -and $script:Memo.ContainsKey('export')) { return $script:Memo['export'] }

    $export = Get-ScoopJson export
    $apps = if ($export) { @($export.apps) } else { @() }
    $script:Memo['export'] = $apps
    return $apps
}

function Reset-BrewBucketCache {
    # A bucket added or removed mid-run invalidates everything derived from the
    # bucket listings memoised earlier in this process.
    $script:Memo.Remove('buckets')
    $script:Memo.Remove('manifestPaths')
    $script:Memo.Remove('index')
}

function Format-BrewDate {
    <#
        `scoop export` prints ASP.NET style "/Date(<ms>)/", a PowerShell 7 JSON
        reader may hand back a DateTime, and a plain parse yields ISO-8601.
        Reduce all of them to one local format.
    #>
    param([object]$Value)

    if ($null -eq $Value) { return '' }
    if ($Value -is [DateTime]) { return $Value.ToLocalTime().ToString('yyyy-MM-dd HH:mm') }

    $text = [string]$Value
    if (-not $text) { return '' }

    if ($text -match '/Date\((\d+)\)/') {
        return [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$Matches[1]).LocalDateTime.ToString('yyyy-MM-dd HH:mm')
    }

    $parsed = [DateTime]::MinValue
    if ([DateTime]::TryParse($text, [ref]$parsed)) { return $parsed.ToString('yyyy-MM-dd HH:mm') }
    return $text
}

function Get-BrewInstalledPackages {
    param(
        [string]$Query,
        [switch]$Refresh
    )

    $rows = @()
    foreach ($app in Get-BrewExportedApps -Refresh:$Refresh) {
        if ($Query -and $app.Name -notmatch $Query) { continue }

        # Scoop joins every marker into one string, e.g.
        # "Deprecated package, Global install".
        $info = [string]$app.Info

        $updated = Format-BrewDate -Value $app.Updated

        $rows += [pscustomobject]@{
            Name       = $app.Name
            Version    = [string]$app.Version
            Bucket     = [string]$app.Source
            Global     = ($info -like '*Global install*')
            Hold       = ($info -like '*Held package*')
            Failed     = ($info -like '*Install failed*')
            Deprecated = ($info -like '*Deprecated package*')
            Updated    = $updated
        }
    }
    return $rows
}

function Get-BrewManifestPathMap {
    <#
        "bucket/name" -> manifest file, built from one enumeration per run.
        A name can exist both under `bucket` and `deprecated`; the live one wins.
    #>
    if ($script:Memo.ContainsKey('manifestPaths')) { return $script:Memo['manifestPaths'] }

    $map = @{}
    foreach ($dir in @(Get-ChildItem (Get-BrewBucketsDir) -Directory -ErrorAction SilentlyContinue)) {
        $files = @(Get-ChildItem $dir.FullName -Filter '*.json' -Recurse -ErrorAction SilentlyContinue)
        foreach ($file in $files) {
            if ($file.Name -eq 'manifests.json') { continue }
            $deprecated = $file.FullName -like '*\deprecated\*'
            $key = "$($dir.Name)/$($file.BaseName)"

            $existing = $map[$key]
            if ($existing -and -not $existing.Deprecated) { continue }

            $map[$key] = [pscustomobject]@{
                Path       = $file.FullName
                Deprecated = $deprecated
                Name       = $file.BaseName
                Bucket     = $dir.Name
            }
        }
    }

    $script:Memo['manifestPaths'] = $map
    return $map
}

function Get-BrewManifestFile {
    param([string]$Name, [string]$Bucket)

    $map = Get-BrewManifestPathMap

    if ($Bucket) {
        $hit = $map["$Bucket/$Name"]
        if ($hit) { return $hit.Path }
        return $null
    }

    foreach ($bucket in @(Get-BrewBuckets | ForEach-Object { $_.Name })) {
        $hit = $map["$bucket/$Name"]
        if ($hit) { return $hit.Path }
    }
    return $null
}

function Get-BrewManifest {
    param([string]$Name, [string]$Bucket)

    $path = Get-BrewManifestFile -Name $Name -Bucket $Bucket
    if (-not $path) { return $null }
    try { return [System.IO.File]::ReadAllText($path) | ConvertFrom-Json } catch { return $null }
}

function Get-BrewPackageIndex {
    <#
        Flattened view of every manifest in every added bucket, used by search,
        uses, options and which-formula. Parsed once per run, and cached on disk
        between runs because reading every manifest costs seconds.
    #>
    param([switch]$Refresh)

    Test-ScoopInstalled | Out-Null
    if (-not $Refresh -and $script:Memo.ContainsKey('index')) { return $script:Memo['index'] }

    if (-not (Test-Path -LiteralPath $script:StateDir)) {
        New-Item -ItemType Directory -Path $script:StateDir -Force | Out-Null
    }

    $cachePath = Join-Path $script:StateDir 'manifest-index.json'
    $key = Get-BrewIndexKey

    if (-not $Refresh -and (Test-Path -LiteralPath $cachePath)) {
        try {
            $cached = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
            if ($cached.key -eq $key) {
                $packages = @($cached.packages)
                $script:Memo['index'] = $packages
                return $packages
            }
        } catch { }
    }

    $arch = Get-BrewArchitecture
    $packages = @()

    foreach ($entry in @((Get-BrewManifestPathMap).Values | Sort-Object Name)) {
        try { $manifest = [System.IO.File]::ReadAllText($entry.Path) | ConvertFrom-Json } catch { continue }
        if (-not $manifest.version) { continue }

        $packages += [pscustomobject]@{
            Name        = $entry.Name
            Bucket      = $entry.Bucket
            Version     = [string](Get-BrewManifestVersion $manifest $arch)
            Description = [string]$manifest.description
            Homepage    = [string](Get-BrewManifestScalar $manifest 'homepage' $arch)
            License     = Format-BrewLicense $manifest.license
            Depends     = @(Get-BrewManifestDepends $manifest $arch)
            Suggest     = @(Get-BrewSuggest $manifest)
            Binaries    = @(Get-BrewBinaries $manifest $arch)
            Deprecated  = [bool]$entry.Deprecated
        }
    }

    Write-BrewTextFile -Path $cachePath -Content @(
        [pscustomobject]@{ key = $key; packages = $packages } | ConvertTo-Json -Depth 6 -Compress
    )

    $script:Memo['index'] = $packages
    return $packages
}

function Get-BrewIndexKey {
    <#
        Keyed on the bucket commit as well as the file count: `brew update`
        usually changes manifest versions without changing how many manifests
        exist, and a stale index would make `brew outdated` report wrongly.
    #>
    $parts = @("index$script:BrewIndexVersion", (Get-BrewArchitecture))

    foreach ($bucket in @(Get-BrewBuckets)) {
        $headFile = Join-Path $bucket.Path '.git/HEAD'
        $head = 'unversioned'
        if (Test-Path -LiteralPath $headFile) {
            $head = (Get-Content -LiteralPath $headFile -Raw).Trim()
            if ($head -like 'ref:*') {
                $refPath = Join-Path (Join-Path $bucket.Path '.git') ($head -replace '^ref:\s*', '')
                if (Test-Path -LiteralPath $refPath) { $head = (Get-Content -LiteralPath $refPath -Raw).Trim() }
            }
        }
        $parts += "$($bucket.Name)=$($bucket.Packages),$head"
    }

    return ($parts -join ';')
}

#endregion

#region manifest field helpers
# These mirror the parts of Scoop's manifest schema that a caller can express
# either at the top level or inside `architecture.<arch>`.

function Get-BrewManifestScalar {
    param([object]$Manifest, [string]$Property, [string]$Architecture)

    if ($null -eq $Manifest) { return $null }
    $arch = $Manifest.architecture
    if ($arch -and $arch.$Architecture -and $null -ne $arch.$Architecture.$Property) {
        return [string]$arch.$Architecture.$Property
    }
    if ($null -ne $Manifest.$Property) { return [string]$Manifest.$Property }
    return $null
}

function Get-BrewManifestVersion {
    param([object]$Manifest, [string]$Architecture)

    # `-` in a manifest version means "take the version from the URL".
    $version = [string]$Manifest.version
    if ($version -eq '-') { return $null }
    return $version
}

function Get-BrewManifestDepends {
    param([object]$Manifest, [string]$Architecture)

    $deps = @()
    if ($null -ne $Manifest.depends) { $deps += @($Manifest.depends) }
    $arch = $Manifest.architecture
    if ($arch -and $arch.$Architecture -and $null -ne $arch.$Architecture.depends) {
        $deps += @($arch.$Architecture.depends)
    }
    return ConvertTo-BrewList $deps
}

function Get-BrewBinaries {
    <#
        Bare executable names a manifest shims. `bin` may be a string, an array
        of strings, or an array of [source, shimName] pairs, and may be
        overridden per architecture.
    #>
    param([object]$Manifest, [string]$Architecture)

    if ($null -eq $Manifest) { return @() }

    $entries = @()
    if ($null -ne $Manifest.bin) { $entries += @($Manifest.bin) }
    $arch = $Manifest.architecture
    if ($arch -and $arch.$Architecture -and $null -ne $arch.$Architecture.bin) {
        $entries = @($arch.$Architecture.bin)
    }

    $names = @()
    foreach ($entry in $entries) {
        if ($null -eq $entry) { continue }
        $raw = if ($entry -is [System.Array]) { if ($entry.Count -gt 1) { $entry[1] } else { $entry[0] } } else { [string]$entry }
        $leaf = Split-Path -Leaf ([string]$raw)
        if ($leaf) { $names += $leaf }
    }
    return ConvertTo-BrewList $names
}

function ConvertTo-BrewList {
    <#
        Normalise a stanza that may be absent, a single string or an array into
        a real string array. `@($null)` has Count 1, which would otherwise make
        every missing stanza look present.
    #>
    param([object]$Value)

    if ($null -eq $Value) { return @() }
    return @($Value | ForEach-Object { if ($null -ne $_) { [string]$_ } } | Where-Object { $_ -ne '' })
}

function Get-BrewNameArgs {
    <#
        Package names from a token list. An unbound
        ValueFromRemainingArguments parameter is $null, and `@($null)` has
        Count 1, which would otherwise read as one empty package name.
    #>
    param([object]$Tokens)

    if ($null -eq $Tokens) { return @() }
    return @($Tokens | ForEach-Object { if ($null -ne $_) { [string]$_ } } |
        Where-Object { $_ -ne '' -and $_ -notmatch '^-' })
}

function Get-BrewFlagArgs {
    param([object]$Tokens)

    if ($null -eq $Tokens) { return @() }
    return @($Tokens | ForEach-Object { if ($null -ne $_) { [string]$_ } } |
        Where-Object { $_ -ne '' -and $_ -match '^-' })
}

function Format-BrewLicense {
    param([object]$License)

    if ($null -eq $License) { return $null }
    if ($License -is [string]) { return $License }

    $identifier = [string]$License.identifier
    $url = [string]$License.url
    if ($identifier -and $url) { return "$identifier ($url)" }
    if ($identifier) { return $identifier }
    return [string]$License
}

function Get-BrewSuggest {
    param([object]$Manifest)

    if ($null -eq $Manifest -or $null -eq $Manifest.suggest) { return @() }
    $values = @()
    foreach ($property in $Manifest.suggest.PSObject.Properties) { $values += @($property.Value) }
    return ConvertTo-BrewList $values
}

function Get-BrewVersionCore {
    <#
        The leading dotted-number run of a version: `1.0-rc2` and `5.2.1.Final`
        both reduce to a comparable core, and any trailing label is dropped so
        that a pre-release never outranks the release it belongs to.
    #>
    param([string]$Value)

    if (-not $Value) { return $null }
    $text = $Value -replace '^[vV]', ''
    if ($text -match '^(\d+(?:\.\d+)*)') { return $Matches[1] }
    return $null
}

function Compare-BrewVersion {
    <#
        Return 1 when Latest is newer than Installed, -1 when older, 0 when the
        numeric cores match. Scoop version strings are free-form
        (`2.55.0.5`, `1.2.3-rc1`, `current`); anything without a comparable core
        is reported as equal so no phantom update is offered.
    #>
    param([string]$Installed, [string]$Latest)

    if (-not $Installed -or -not $Latest) { return 0 }
    if ($Installed -eq $Latest) { return 0 }
    if ($Latest -eq 'current' -or $Installed -eq 'current') { return 0 }

    $left = @((Get-BrewVersionCore $Installed) -split '\.')
    $right = @((Get-BrewVersionCore $Latest) -split '\.')

    if (-not $left[0] -or -not $right[0]) { return 0 }

    $count = [Math]::Max($left.Count, $right.Count)
    for ($i = 0; $i -lt $count; $i++) {
        $installedPart = if ($i -lt $left.Count) { [int64]$left[$i] } else { 0 }
        $latestPart = if ($i -lt $right.Count) { [int64]$right[$i] } else { 0 }
        if ($latestPart -gt $installedPart) { return 1 }
        if ($latestPart -lt $installedPart) { return -1 }
    }

    return 0
}

#endregion

#region tap map

function Get-BrewTapMap {
    <#
        The tap map pins GitHub repositories to lowercase local bucket names.
        It ships next to this module; `$env:SCOOPBREW_TAP_MAP` may point at a
        different file (the tests do). Memoised per path, so switching the env
        var re-parses without re-importing the module.
    #>
    $path = if ($env:SCOOPBREW_TAP_MAP) { $env:SCOOPBREW_TAP_MAP } else { Join-Path (Join-Path $script:BrewRoot 'lib') 'tap-map.json' }

    $cached = $script:Memo['tapMap']
    if ($cached -and $cached.Path -eq $path) { return $cached }

    $byRepo = @{}
    $byRepoName = @{}
    $byLocal = @{}

    if (Test-Path -LiteralPath $path) {
        $raw = $null
        try { $raw = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { $raw = $null }

        if ($raw) {
            foreach ($property in $raw.PSObject.Properties) {
                if ($property.Name -notmatch '^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$') { continue }
                $repo = $property.Name
                $local = ([string]$property.Value).ToLowerInvariant()
                if (-not $local) { continue }
                if ($byLocal.ContainsKey($local)) {
                    brewWarn "tap map: '$repo' and '$($byLocal[$local].Repo)' both claim the name '$local'; keeping the first."
                    continue
                }

                $entry = [pscustomobject]@{
                    Repo  = $repo
                    Local = $local
                    Url   = "https://github.com/$repo"
                }
                $byRepo[$repo.ToLowerInvariant()] = $entry
                $repoKey = $repo.Substring($repo.IndexOf('/') + 1).ToLowerInvariant()
                if (-not $byRepoName.ContainsKey($repoKey)) { $byRepoName[$repoKey] = @() }
                $byRepoName[$repoKey] += $entry
                $byLocal[$local] = $entry
            }
        }
    }

    $map = [pscustomobject]@{ Path = $path; ByRepo = $byRepo; ByRepoName = $byRepoName; ByLocal = $byLocal }
    $script:Memo['tapMap'] = $map
    return $map
}

function Resolve-BrewTapName {
    <#
        Translate a tap reference into the local bucket it maps to. A
        `user/repo` form always resolves: through the tap map when listed,
        otherwise by the `owner-repo` lowercase convention. A bare name may be
        a shortname or a repository name; several repositories sharing a name
        resolve only with -ForAdd, which aborts and lists the candidates, while
        read-only callers silently get $null.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$ForAdd
    )

    $trimmed = $Name.Trim() -replace '\.git$', ''

    if ($trimmed -match '^(?<user>[a-zA-Z0-9._-]+)/(?<repo>[a-zA-Z0-9._-]+)$') {
        $user = $Matches['user']
        $repo = $Matches['repo']

        $map = Get-BrewTapMap
        $hit = $map.ByRepo["$user/$repo".ToLowerInvariant()]
        if ($hit) { return $hit }
        return [pscustomobject]@{
            Repo  = "$user/$repo"
            Local = "$user-$repo".ToLowerInvariant()
            Url   = "https://github.com/$user/$repo"
        }
    }

    if ($trimmed -match '^[a-zA-Z0-9._-]+$') {
        $map = Get-BrewTapMap
        $lower = $trimmed.ToLowerInvariant()

        if ($map.ByLocal.ContainsKey($lower)) { return $map.ByLocal[$lower] }

        if ($map.ByRepoName.ContainsKey($lower)) {
            $candidates = @($map.ByRepoName[$lower])
            if ($candidates.Count -eq 1) { return $candidates[0] }
            if ($ForAdd) {
                Abort-Brew "Ambiguous tap '$trimmed': matches $($candidates.Repo -join ', '). Use the full user/repo form or one of the local names: $($candidates.Local -join ', ')."
            }
        }
    }

    return $null
}

#endregion

#region package resolution

function Resolve-BrewPackage {
    param([Parameter(Mandatory = $true)][string]$Query)

    Test-ScoopInstalled | Out-Null

    $name = $Query
    $bucket = $null
    $version = $null

    if ($Query -match '^(?:(?<bucket>[a-zA-Z0-9._-]+)/)?(?<app>[a-zA-Z0-9._-]+)(?:@(?<version>.+))?$') {
        $name = $Matches['app']
        $bucket = $Matches['bucket']
        $version = $Matches['version']
    }

    $arch = Get-BrewArchitecture
    $manifest = $null

    if ($bucket) {
        $manifest = Get-BrewManifest -Name $name -Bucket $bucket
        if (-not $manifest) {
            # The bucket part may be a mapped tap's repository name while the
            # bucket itself is added under its local name.
            $mapped = Resolve-BrewTapName -Name $bucket
            if ($mapped -and $mapped.Local -ne $bucket.ToLowerInvariant()) {
                $retry = Get-BrewManifest -Name $name -Bucket $mapped.Local
                if ($retry) {
                    $manifest = $retry
                    $bucket = $mapped.Local
                }
            }
        }
    } else {
        $buckets = @(Get-BrewBuckets)
        for ($i = 0; $i -lt $buckets.Count; $i++) {
            $candidate = Get-BrewManifest -Name $name -Bucket $buckets[$i].Name
            if ($candidate) {
                if (-not $manifest) {
                    $manifest = $candidate
                    $bucket = $buckets[$i].Name
                }
            }
        }
    }

    if (-not $manifest) { return $null }

    [pscustomobject]@{
        Name     = $name
        Bucket   = $bucket
        Version  = if ($version) { $version } else { [string](Get-BrewManifestVersion $manifest $arch) }
        Manifest = $manifest
        Path     = Get-BrewManifestFile -Name $name -Bucket $bucket
    }
}

function Expand-BrewTapName {
    <#
        Homebrew allows three-part `<user>/<tap>/<name>` references. Scoop
        addresses packages as `<bucket>/<name>` and stores taps under their
        local bucket name, so report the tap to add when missing together with
        the two-part equivalent. The bucket part is the tap's local name per
        Resolve-BrewTapName. Returns $null for anything else, including URLs,
        which match no segment class because of `:` and `//`.
    #>
    param([string]$Name)

    if ($Name -match '^(?<user>[a-zA-Z0-9._-]+)/(?<repo>[a-zA-Z0-9._-]+)/(?<app>[a-zA-Z0-9._-]+(?:@.+)?)$') {
        $user = $Matches['user']
        $repo = $Matches['repo']
        $app = $Matches['app']

        $tap = Resolve-BrewTapName -Name "$user/$repo"
        return [pscustomobject]@{
            Tap    = "$user/$repo"
            Bucket = $tap.Local
            Name   = "$($tap.Local)/$app"
            Url    = $tap.Url
        }
    }
    return $null
}

function Search-BrewPackages {
    param([string]$Pattern, [string]$By = 'name')

    $index = @(Get-BrewPackageIndex)
    if (-not $Pattern) { return @($index | Sort-Object Name) }

    $regex = "(?i)$Pattern"
    $byName = @($index | Where-Object { $_.Name -match $regex })

    if ($By -eq 'name') { return @($byName | Sort-Object Name) }

    $byDesc = @($index | Where-Object { $_.Description -match $regex } | Sort-Object Name)
    $extra = @($byDesc | Where-Object { $byName.Name -notcontains $_.Name })
    return @(@($byName) + $extra)
}

function Get-BrewDependencies {
    param([Parameter(Mandatory = $true)][string]$Name, [switch]$Optional)

    $arch = Get-BrewArchitecture
    $seen = @()
    $tree = @()
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue($Name)

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if ($seen -contains $current) { continue }
        $seen += $current

        $pkg = Resolve-BrewPackage $current
        if (-not $pkg) { continue }

        $deps = @(Get-BrewManifestDepends $pkg.Manifest $arch)
        if ($Optional) { $deps += @(Get-BrewSuggest $pkg.Manifest) }

        foreach ($dep in $deps) {
            $queue.Enqueue($dep)
            $tree += [pscustomobject]@{
                Package = $current
                Name    = $dep
                Direct  = ($current -eq $Name)
            }
        }
    }

    return $tree
}

function Get-BrewDependents {
    param([Parameter(Mandatory = $true)][string]$Name)

    return @(Get-BrewPackageIndex | Where-Object { $_.Depends -contains $Name } | Sort-Object Name)
}

function Get-BrewOutdatedPackages {
    $rows = @()
    foreach ($installed in Get-BrewInstalledPackages) {
        $pkg = Resolve-BrewPackage $installed.Name
        if (-not $pkg -or -not $pkg.Version) { continue }
        if ((Compare-BrewVersion $installed.Version $pkg.Version) -gt 0) {
            $rows += [pscustomobject]@{
                Name      = $installed.Name
                Installed = $installed.Version
                Latest    = $pkg.Version
                Bucket    = $pkg.Bucket
                Hold      = $installed.Hold
            }
        }
    }
    return $rows
}

function Get-BrewPackagePath {
    param([Parameter(Mandatory = $true)][string]$Name, [switch]$Global)

    $apps = if ($Global) { Get-BrewAppsDir -Global } else { Get-BrewAppsDir }
    $dir = Join-Path (Join-Path $apps $Name) 'current'
    if (Test-Path -LiteralPath $dir) { return $dir }
    return $null
}

#endregion

#region unsupported commands

$script:BrewUnsupportedReasonRuby = 'the Scoop backend ships no Ruby runtime'
$script:BrewUnsupportedReasonBottle = 'Scoop has no bottle concept: manifests point at upstream archives directly'

$script:BrewUnsupportedCommands = [ordered]@{
    'typecheck'                = "Homebrew runs Sorbet over its Ruby core; $script:BrewUnsupportedReasonRuby"
    'style'                    = "Homebrew runs RuboCop over its Ruby core; $script:BrewUnsupportedReasonRuby"
    'rubocop'                  = "Homebrew runs RuboCop over its Ruby core; $script:BrewUnsupportedReasonRuby"
    'tests'                    = "RSpec drives Homebrew Ruby internals; $script:BrewUnsupportedReasonRuby"
    'test'                     = "RSpec drives Homebrew Ruby internals; $script:BrewUnsupportedReasonRuby"
    'lgtm'                     = "a bundle of Homebrew style and type checks; $script:BrewUnsupportedReasonRuby"
    'verify'                   = "a bundle of Homebrew checks; $script:BrewUnsupportedReasonRuby"
    'irb'                      = "opens the Homebrew vendored Ruby console; $script:BrewUnsupportedReasonRuby"
    'ruby'                     = "runs the Homebrew vendored Ruby; $script:BrewUnsupportedReasonRuby"
    'rubydoc'                  = "generates YARD docs for the Homebrew Ruby API; $script:BrewUnsupportedReasonRuby"
    'debugger'                 = "attach to a Ruby process; $script:BrewUnsupportedReasonRuby"
    'prof'                     = "Ruby profiling of the brew process; $script:BrewUnsupportedReasonRuby"
    'edit'                     = 'opens a Homebrew Ruby file in $EDITOR; Scoop manifests are JSON, edit them in the bucket clone'
    'create'                   = 'writes a Homebrew Formula; Scoop manifests are JSON, see scoop create'
    'vendor-gems'              = "updates the Homebrew bundled gems; $script:BrewUnsupportedReasonRuby"
    'install-bundler-gems'     = "installs the Homebrew Bundler gems; $script:BrewUnsupportedReasonRuby"
    'bottle'                   = $script:BrewUnsupportedReasonBottle
    'dispatch-build-bottle'    = $script:BrewUnsupportedReasonBottle
    'unbottled'                = $script:BrewUnsupportedReasonBottle
    'test-bot'                 = "drives Homebrew CI VMs; $script:BrewUnsupportedReasonRuby"
    'pr-pull'                  = "part of the Homebrew bottle release pipeline; $script:BrewUnsupportedReasonBottle"
    'pr-upload'                = "part of the Homebrew bottle release pipeline; $script:BrewUnsupportedReasonBottle"
    'pr-publish'               = "part of the Homebrew bottle release pipeline; $script:BrewUnsupportedReasonBottle"
    'pr-automerge'             = "part of the Homebrew bottle release pipeline; $script:BrewUnsupportedReasonBottle"
    'release'                  = "cuts a Homebrew/brew release; $script:BrewUnsupportedReasonRuby"
    'tap-new'                  = 'creates a Homebrew tap template; Scoop buckets are created with scoop bucket add <name> <repo>'
    'generate-formula-api'     = 'publishes the Homebrew JSON API; Scoop reads bucket manifests directly'
    'generate-cask-api'        = 'publishes the Homebrew JSON API; Scoop reads bucket manifests directly'
    'generate-internal-api'    = 'publishes the Homebrew JSON API; Scoop reads bucket manifests directly'
    'generate-man-completions' = "regenerates Homebrew manpages and completions; $script:BrewUnsupportedReasonRuby"
    'audit'                    = 'audits Homebrew Formulae and Casks against Homebrew rules; Scoop validates manifests against its JSON schema'
    'linkage'                  = 'inspects Mach-O and ELF dynamic dependencies; Windows PE inspection is out of scope'
    'link'                     = 'Scoop shims replace keg symlinks: run scoop reset <package> to rebuild them'
    'unlink'                   = 'Scoop shims replace keg symlinks: run scoop shim rm <command> to drop them'
    'sandbox-exec'             = 'wraps the macOS seatbelt sandbox; Windows has no equivalent in Scoop'
    'shellenv'                 = 'prints POSIX shell initialisation; Scoop publishes its shim directory through PATH instead'
    'services'                 = 'Homebrew talks to launchd and systemd; a Windows service backend (Task Scheduler or SCM) is not implemented'
    'command-not-found-init'   = 'installs a shell handler for missed commands; not applicable to PowerShell'
    'analytics'                = 'reports Homebrew usage statistics; Scoop collects none'
    'readall'                  = 'validates every Formula in a tap by loading it in Ruby'
    'mcp-server'               = "exposes Homebrew internals over MCP; $script:BrewUnsupportedReasonRuby"
    'trust'                    = 'Homebrew verifies detached tap signatures; Scoop buckets rely on git and manifest hashes'
    'untrust'                  = 'Homebrew verifies detached tap signatures; Scoop buckets rely on git and manifest hashes'
    'vulns'                    = 'matches Formula versions against OSV advisories; the nearest Scoop check is scoop checkup'
    'livecheck'                = 'probes upstream releases for Homebrew Formulae; Scoop manifests declare checkver, run scoop checkver in a bucket clone'
    'migrate'                  = 'renames Cellar directories after a tap migration; Scoop reinstalls into a new app directory'
    'vendor-install'           = "installs Homebrew build toolchains; $script:BrewUnsupportedReasonRuby"
    'setup-ruby'               = "installs the Homebrew private Ruby; $script:BrewUnsupportedReasonRuby"
    'postinstall'              = 'runs a Formula post-install block; Scoop executes a manifest post_install only during installation, so reinstall the package to run it again'
    'formulae'                 = 'lists installed Homebrew Formulae; use brew list'
    'casks'                    = 'Scoop has no separate GUI package namespace; use brew search or brew install --cask'
    'advisory-match'           = 'matches Homebrew security advisories to Formulae; Scoop manifests carry no advisory feed'
    'as-console-user'          = 're-executes a command as the console user via macOS APIs; not applicable to Windows'
    'benchmark'                = "runs Ruby benchmark suites against Homebrew internals; $script:BrewUnsupportedReasonRuby"
    'bump'                     = 'opens pull requests to update Homebrew Formula versions; Scoop buckets are updated by their own maintainers'
    'bump-formula-pr'          = 'opens pull requests to update Homebrew Formula versions; Scoop buckets are updated by their own maintainers'
    'bump-cask-pr'             = 'opens pull requests to update Homebrew Cask versions; Scoop buckets are updated by their own maintainers'
    'bump-unversioned-casks'   = 'opens pull requests to update Homebrew Cask versions; Scoop buckets are updated by their own maintainers'
    'bump-revision'            = 'increments a Formula revision; Scoop manifests have no revision field, they pin a version and hash'
    'bump-compatibility-version' = "edits Homebrew source constants; $script:BrewUnsupportedReasonRuby"
    'completions'              = 'regenerates bash, fish and zsh completions from Homebrew Ruby command definitions; PowerShell completion for ScoopBrew is not generated'
    'contributions'            = "graphs Homebrew contributor statistics; $script:BrewUnsupportedReasonRuby"
    'determine-test-runners'   = "assigns Homebrew CI runners to bottle jobs; $script:BrewUnsupportedReasonBottle"
    'extract'                  = "moves bottles between Homebrew repositories; $script:BrewUnsupportedReasonBottle"
    'formula'                  = "loads and evaluates a Homebrew Formula in Ruby; $script:BrewUnsupportedReasonRuby"
    'formula-analytics'        = "queries the Homebrew analytics API; Scoop collects no usage data"
    'generate-advisories-api'  = 'publishes the Homebrew advisories API; Scoop reads bucket manifests directly'
    'generate-analytics-api'   = 'publishes the Homebrew analytics API; Scoop collects no usage data'
    'generate-cask-ci-matrix'  = 'builds the Homebrew Cask CI matrix; there is no Cask CI here'
    'generate-vulns-advisories' = 'publishes the Homebrew vulnerability feed; the nearest Scoop check is scoop checkup'
    'generate-zap'             = 'generates Cask zap stanzas from a running macOS installation; Scoop manifests declare uninstaller scripts instead'
    'gist-logs'                = 'uploads Homebrew install logs to a gist; Scoop writes no such log bundle'
    'nodenv-sync'              = 'synchronises nodenv shims with Homebrew Node installs; use the versions bucket instead: brew tap versions then brew install nodejs-lts'
    'pyenv-sync'               = 'synchronises pyenv shims with Homebrew Python installs; Scoop installs Python directly: brew install python'
    'rbenv-sync'               = 'synchronises rbenv shims with Homebrew Ruby installs; Scoop has no Ruby version manager integration'
    'version-install'          = 'installs a specific Formula version into a separate Cellar directory; Scoop installs a named version with scoop install bucket/app@version'
    'sh'                       = "opens an interactive shell configured for Homebrew's build environment; $script:BrewUnsupportedReasonRuby"
    'unpack'                   = "unpacks a bottle or source archive for inspection; $script:BrewUnsupportedReasonBottle"
    'update-if-needed'         = 'internal Homebrew throttled auto-update; Scoop updates when you run brew update'
    'update-report'            = 'internal reporting of what changed during a Homebrew update'
    'update-reset'             = 'hard-resets Homebrew git checkouts; for Scoop run: scoop update scoop, or remove and re-add a bucket with scoop bucket rm then scoop bucket add'
    'update-license-data'      = 'refreshes Homebrew SPDX license data; Scoop validates licenses through its manifest schema'
    'update-maintainers'       = "refreshes Homebrew CODEOWNERS-derived maintainer lists; $script:BrewUnsupportedReasonRuby"
    'update-perl-resources'    = 'refreshes Homebrew Perl module resources; Scoop has no Perl resource pipeline'
    'update-python-resources'  = 'refreshes Homebrew Python wheel resources; Scoop has no Python resource pipeline'
    'update-portable-ruby'     = "builds and vendors Homebrew's private Ruby interpreter; $script:BrewUnsupportedReasonRuby"
    'update-sponsors'          = "refreshes Homebrew sponsor lists; $script:BrewUnsupportedReasonRuby"
    'update-test'              = "runs Homebrew's own update integration tests; $script:BrewUnsupportedReasonRuby"
    'which-update'             = 'updates the Homebrew command-not-found shell integration; not applicable to PowerShell'
    '--env'                    = 'reports the compiler and SDK environment Homebrew would build with; Scoop installs prebuilt archives, so there is no build environment'
}

# Homebrew's HOMEBREW_INTERNAL_COMMAND_ALIASES, kept with the same meaning so
# muscle memory transfers. Note `up` is update, not upgrade.
$script:BrewCommandAliases = [ordered]@{
    'ls'           = 'list'
    'homepage'     = 'home'
    '-S'           = 'search'
    'up'           = 'update'
    'ln'           = 'link'
    'instal'       = 'install'
    'uninstal'     = 'uninstall'
    'post_install' = 'postinstall'
    'rm'           = 'uninstall'
    'remove'       = 'uninstall'
    'abv'          = 'info'
    'dr'           = 'doctor'
    '--repo'       = '--repository'
    'environment'  = '--env'
    '--config'     = 'config'
    'lc'           = 'livecheck'
    'tc'           = 'typecheck'
    'x'            = 'exec'
}

function Get-BrewCommandAlias {
    param([string]$Name)
    if ($script:BrewCommandAliases.Contains($Name)) { return $script:BrewCommandAliases[$Name] }
    return $null
}

function Get-BrewCommandAliases {
    return $script:BrewCommandAliases
}

function Get-BrewUnsupportedCommand {
    param([string]$Name)
    if ($script:BrewUnsupportedCommands.Contains($Name)) { return $script:BrewUnsupportedCommands[$Name] }
    return $null
}

#endregion

#region argument translation

$script:BrewUnsupportedFlags = [ordered]@{
    '--HEAD'                  = 'Scoop has no build-from-source mode; install the released version instead.'
    '--devel'                 = 'Scoop manifests pin release versions only.'
    '--with-'                 = 'Scoop manifests have no build options.'
    '--without-'              = 'Scoop manifests have no build options.'
    '--build-from-source'     = 'Scoop never compiles from source.'
    '--display-times'         = 'Timing is reported by PowerShell, not by brew.'
    '--formula'               = 'Redundant: every Scoop app is a formula.'
    '--ignore-pinned'         = 'Use brew unpin first.'
    '--locked'                = 'Scoop has no lockfile concept.'
    '--caskroom'              = 'Scoop has no separate Caskroom directory.'
    '--env=std'               = 'Scoop does not alter the compiler environment.'
    '--skip-reloc'            = 'Scoop does not relocate binaries.'
    '--force-bottle'          = 'Scoop has no bottles.'
    '--bottle'                = 'Scoop has no bottles.'
    '--build-bottle'          = 'Scoop has no bottles.'
    '--bintray'               = 'Scoop has no bottles.'
}

function Convert-BrewFlags {
    param([string[]]$Flags, [string[]]$Allowed)

    $accepted = @()
    $dropped = @()

    foreach ($flag in $Flags) {
        if ($flag -notmatch '^-') { $accepted += $flag; continue }

        $name = ($flag -split '=')[0]
        if ($Allowed -contains $name) { $accepted += $flag; continue }
        if ($script:BrewUnsupportedFlags.Contains($name)) { $dropped += $name; continue }
        if ($name -like '--with-*' -or $name -like '--without-*') { $dropped += $name; continue }

        $accepted += $flag
    }

    return [pscustomobject]@{ Accepted = $accepted; Dropped = $dropped }
}

function Show-DroppedFlags {
    param([string[]]$Dropped)

    foreach ($flag in $Dropped) {
        $reason = $script:BrewUnsupportedFlags[$flag]
        if (-not $reason) { $reason = 'Scoop has no equivalent option.' }
        brewWarn "$flag is not supported by the Scoop backend: $reason"
    }
}

#endregion

Export-ModuleMember -Function `
    Write-BrewRaw, brewMessage, brewSuccess, brewWarn, brewError, Abort-Brew, Write-BrewTable, Write-BrewTextFile, `
    Test-ScoopInstalled, Get-BrewScoopRoot, Get-BrewScoopCoreDir, Get-BrewScoopVersion, Invoke-Scoop, Get-ScoopJson, Get-BrewArchitecture, `
    Get-BrewAppsDir, Get-BrewShimDir, Get-BrewBucketsDir, Get-BrewCacheDir, Get-BrewBucketDir, Get-GlobalScoopRoot, `
    Get-BrewBuckets, Get-BrewKnownBuckets, Get-BrewKnownBucket, `
    Get-BrewInstalledPackages, Get-BrewPackageIndex, Get-BrewManifest, Get-BrewManifestFile, Reset-BrewBucketCache, `
    Search-BrewPackages, Resolve-BrewPackage, Expand-BrewTapName, Get-BrewDependencies, Get-BrewDependents, `
    Get-BrewTapMap, Resolve-BrewTapName, `
    Get-BrewOutdatedPackages, Get-BrewPackagePath, Compare-BrewVersion, Get-BrewVersionCore, `
    ConvertTo-BrewList, Format-BrewLicense, Get-BrewSuggest, Get-BrewManifestDepends, Get-BrewManifestVersion, `
    Get-BrewNameArgs, Get-BrewFlagArgs, Format-BrewDate, `
    Get-BrewBinaries, Get-BrewManifestScalar, `
    Convert-BrewFlags, Show-DroppedFlags, Get-BrewUnsupportedCommand, `
    Get-BrewCommandAlias, Get-BrewCommandAliases

Export-ModuleMember -Variable BrewVersion, BrewRoot, CommandsDir, StateDir, Scoop
