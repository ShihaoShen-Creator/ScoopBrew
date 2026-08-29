# Requires Pester (ships with Windows PowerShell 5.1).
# Run:  powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester windows/test"
#
# These tests read the local Scoop install and its buckets. They never install,
# uninstall or update anything, so they are safe to run repeatedly and offline
# once the main bucket is present.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Off

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulePath = Join-Path $repoRoot 'windows\lib\ScoopBrew.psm1'
$brewScript = Join-Path $repoRoot 'windows\bin\brew.ps1'

Import-Module $modulePath -DisableNameChecking -Force

function Invoke-Brew {
    param([string[]]$Arguments)

    $output = & 'powershell' '-NoProfile' '-ExecutionPolicy' 'Bypass' '-File' $brewScript @Arguments 2>&1
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Text     = (@($output) -join "`n")
    }
}

Describe 'Scoop discovery' {
    It 'finds a Scoop installation' {
        { Get-BrewScoopRoot } | Should Not Throw
        (Get-BrewScoopRoot) | Should Not BeNullOrEmpty
    }

    It 'reports a Scoop version' {
        (Get-BrewScoopVersion) | Should Match '^\d+\.\d+'
    }

    It 'lists the main bucket with manifests' {
        $main = @(Get-BrewBuckets) | Where-Object { $_.Name -eq 'main' }
        @($main).Count | Should Be 1
        $main[0].Packages | Should BeGreaterThan 0
    }
}

Describe 'Compare-BrewVersion' {
    It 'detects a newer patch version' {
        Compare-BrewVersion '1.2.3' '1.2.4' | Should Be 1
    }

    It 'detects an older version' {
        Compare-BrewVersion '2.0' '1.9' | Should Be -1
    }

    It 'treats equal versions as equal' {
        Compare-BrewVersion '26.02' '26.02' | Should Be 0
    }

    It 'compares multi-digit segments numerically, not as text' {
        Compare-BrewVersion '1.9' '1.10' | Should Be 1
    }

    It 'never reports an update for the moving "current" version' {
        Compare-BrewVersion 'current' 'current' | Should Be 0
        Compare-BrewVersion '1.0' 'current' | Should Be 0
    }

    It 'does not rank a pre-release suffix above the matching release' {
        Compare-BrewVersion '1.0' '1.0-rc2' | Should Be 0
    }

    It 'returns equal when either side is missing' {
        Compare-BrewVersion '' '1.0' | Should Be 0
        Compare-BrewVersion '1.0' '' | Should Be 0
    }
}

Describe 'manifest field helpers' {
    It 'turns an absent stanza into an empty array, not a single blank entry' {
        # `@($null)` has Count 1, which made every missing stanza look present.
        @(ConvertTo-BrewList $null).Count | Should Be 0
        @(ConvertTo-BrewList '').Count | Should Be 0
    }

    It 'keeps every element of a real list' {
        @(ConvertTo-BrewList @('a', 'b')).Count | Should Be 2
    }

    It 'formats an object-shaped license as identifier plus URL' {
        $license = [pscustomobject]@{ identifier = 'MIT'; url = 'https://example.invalid/lic' }
        Format-BrewLicense $license | Should Be 'MIT (https://example.invalid/lic)'
    }

    It 'passes a plain string license through unchanged' {
        Format-BrewLicense 'Apache-2.0' | Should Be 'Apache-2.0'
    }

    It 'separates package names from options' {
        @(Get-BrewNameArgs @('7zip', '--global', '--no-cache')).Count | Should Be 1
        @(Get-BrewFlagArgs @('7zip', '--no-cache'))[0] | Should Be '--no-cache'
    }

    It 'reports no names when the token parameter was never bound' {
        @(Get-BrewNameArgs $null).Count | Should Be 0
        @(Get-BrewFlagArgs $null).Count | Should Be 0
    }
}

Describe 'package resolution against the main bucket' {
    It 'resolves a known package and reports its bucket and version' {
        $pkg = Resolve-BrewPackage 'git'
        $pkg | Should Not BeNullOrEmpty
        $pkg.Bucket | Should Be 'main'
        $pkg.Version | Should Not BeNullOrEmpty
    }

    It 'resolves a bucket-qualified name' {
        $pkg = Resolve-BrewPackage 'main/git'
        $pkg.Name | Should Be 'git'
        $pkg.Bucket | Should Be 'main'
    }

    It 'returns nothing for an unknown package' {
        Resolve-BrewPackage 'definitely-not-a-package-name-xyz' | Should BeNullOrEmpty
    }

    It 'reports a missing dependency list for a package with one' {
        $deps = @(Get-BrewDependencies 'apimtemplate')
        $deps.Name -contains 'azure-cli' | Should Be $true
    }

    It 'finds a reverse dependency' {
        $dependents = @(Get-BrewDependents 'git')
        $dependents.Name -contains 'git-tfs' | Should Be $true
    }

    It 'reads the manifest file the package came from' {
        $pkg = Resolve-BrewPackage 'git'
        $pkg.Path | Should Match 'git\.json$'
        Test-Path -LiteralPath $pkg.Path | Should Be $true
    }

    It 'lists the executables a package shims' {
        $bins = @(Get-BrewBinaries (Resolve-BrewPackage '7zip').Manifest (Get-BrewArchitecture))
        $bins -contains '7z.exe' | Should Be $true
    }
}

Describe 'Expand-BrewTapName' {
    It 'splits a three-part reference into tap and bucket-qualified name' {
        $expanded = Expand-BrewTapName 'ShihaoShen-Creator/ScoopBucket/vscode-exploration'
        $expanded.Tap | Should Be 'ShihaoShen-Creator/ScoopBucket'
        $expanded.Bucket | Should Be 'shihao'
        $expanded.Name | Should Be 'shihao/vscode-exploration'
        $expanded.Url | Should Be 'https://github.com/ShihaoShen-Creator/ScoopBucket'
    }

    It 'derives owner-repo for an unmapped tap and keeps a version pin' {
        $expanded = Expand-BrewTapName 'user/repo/app@1.2.3'
        $expanded.Bucket | Should Be 'user-repo'
        $expanded.Name | Should Be 'user-repo/app@1.2.3'
    }

    It 'ignores plain and bucket-qualified names' {
        Expand-BrewTapName 'git' | Should BeNullOrEmpty
        Expand-BrewTapName 'main/git' | Should BeNullOrEmpty
    }

    It 'ignores URLs' {
        Expand-BrewTapName 'https://github.com/user/repo/app' | Should BeNullOrEmpty
    }
}

Describe 'tap map' {
    It 'parses the bundled map completely' {
        $map = Get-BrewTapMap
        $map.ByRepo.Count | Should Be 12
        foreach ($entry in $map.ByRepo.Values) {
            $entry.Local | Should Match '^[a-z0-9-]+$'
        }
    }

    It 'resolves user/repo case-insensitively' {
        (Resolve-BrewTapName 'SHIHAOSHEN-CREATOR/scoopbucket').Local | Should Be 'shihao'
    }

    It 'resolves the shortname' {
        $resolved = Resolve-BrewTapName 'shihao'
        $resolved.Repo | Should Be 'ShihaoShen-Creator/ScoopBucket'
        $resolved.Url | Should Be 'https://github.com/ShihaoShen-Creator/ScoopBucket'
    }

    It 'resolves a bare repository name' {
        (Resolve-BrewTapName 'ScoopBucket').Local | Should Be 'shihao'
    }

    It 'answers a spelling that is both a shortname and a repository name' {
        (Resolve-BrewTapName 'extras').Repo | Should Be 'ScoopInstaller/Extras'
    }

    It 'applies the owner-repo convention to an unmapped user/repo' {
        $resolved = Resolve-BrewTapName 'microsoft/winget-cli'
        $resolved.Local | Should Be 'microsoft-winget-cli'
        $resolved.Url | Should Be 'https://github.com/microsoft/winget-cli'
    }

    It 'returns nothing for an unmapped bare name' {
        Resolve-BrewTapName 'winget-cli' | Should BeNullOrEmpty
    }

    It 're-parses when the map path changes and falls back to the convention' {
        try {
            $env:SCOOPBREW_TAP_MAP = Join-Path $env:TEMP 'scoopbrew-no-such-tap-map.json'
            $map = Get-BrewTapMap
            $map.Path | Should Be $env:SCOOPBREW_TAP_MAP
            $map.ByRepo.Count | Should Be 0
            (Resolve-BrewTapName 'microsoft/winget-cli').Local | Should Be 'microsoft-winget-cli'
        } finally {
            Remove-Item Env:\SCOOPBREW_TAP_MAP -ErrorAction SilentlyContinue
        }
        # The memo is keyed by path, so the bundled map returns once the
        # override is gone.
        (Get-BrewTapMap).ByRepo.Count | Should Be 12
    }
}

Describe 'tap map ambiguity' {
    It 'lists candidates instead of guessing a bucket' {
        # The only disk write in the suite. Pester 3.4 has no AfterAll, so the
        # cleanup lives in a finally block.
        $mapPath = Join-Path $env:TEMP 'scoopbrew-test-tap-map.json'
        try {
            @{
                'alpha/widget'  = 'widget'
                'beta/widget'   = 'beta-widget'
                'gamma/collide' = 'gamma-collide'
                'delta/collide' = 'delta-collide'
            } | ConvertTo-Json | Set-Content -LiteralPath $mapPath -Encoding UTF8
            $env:SCOOPBREW_TAP_MAP = $mapPath

            # A shortname wins over an ambiguous repository name.
            (Resolve-BrewTapName 'widget').Repo | Should Be 'alpha/widget'

            # The resolution phase reports nothing for an ambiguous bare name;
            # -ForAdd aborts, which runs through the subprocess below because
            # Abort-Brew exits the process.
            Resolve-BrewTapName 'collide' | Should BeNullOrEmpty

            $result = Invoke-Brew @('tap', 'collide')
            $result.ExitCode | Should Not Be 0
            $result.Text | Should Match 'Ambiguous tap'
            $result.Text | Should Match 'gamma/collide'
            $result.Text | Should Match 'delta/collide'
            # The abort happens before any `scoop bucket add` runs.
            $result.Text | Should Not Match 'Adding bucket'
        } finally {
            Remove-Item Env:\SCOOPBREW_TAP_MAP -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $mapPath -ErrorAction SilentlyContinue
        }
    }
}

Describe 'resolution remap' {
    It 'remaps a repository-name bucket to the mapped local bucket' {
        $shihao = @(Get-BrewBuckets | Where-Object { $_.Name -eq 'shihao' })
        if ($shihao.Count -eq 0) { Set-TestInconclusive }

        $dir = Get-BrewBucketDir -Name 'shihao'
        $manifests = @(Get-ChildItem $dir -Filter '*.json' -Recurse)
        if ($manifests.Count -eq 0) { Set-TestInconclusive }
        $app = [System.IO.Path]::GetFileNameWithoutExtension($manifests[0].Name)

        $pkg = Resolve-BrewPackage "ScoopBucket/$app"
        $pkg | Should Not BeNullOrEmpty
        $pkg.Bucket | Should Be 'shihao'
        $pkg.Name | Should Be $app
    }

    It 'leaves an unmapped bucket-qualified name unresolved' {
        Resolve-BrewPackage 'not-a-bucket/git' | Should BeNullOrEmpty
    }
}

Describe 'installed package inventory' {
    It 'returns an array even when nothing is installed' {
        # A single-element result collapses to a scalar without @() at the call
        # site, which broke .Count checks.
        $installed = @(Get-BrewInstalledPackages)
        $installed | Should Not BeNullOrEmpty
    }

    It 'reports the owning bucket for installed packages' {
        foreach ($pkg in @(Get-BrewInstalledPackages)) {
            $pkg.Bucket | Should Not BeNullOrEmpty
            $pkg.Version | Should Not BeNullOrEmpty
        }
    }
}

Describe 'command surface' {
    It 'gives every command a Usage and Summary header' {
        $commandsDir = Join-Path $repoRoot 'windows\commands'
        foreach ($file in (Get-ChildItem $commandsDir -Filter 'brew-*.ps1')) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            $text | Should Match '#\s*Usage:'
            $text | Should Match '#\s*Summary:'
        }
    }

    It 'has no command with a parse error' {
        foreach ($file in (Get-ChildItem (Join-Path $repoRoot 'windows') -Recurse -Include '*.ps1', '*.psm1')) {
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $file.FullName, [ref]$null, [ref]$errors) | Out-Null
            if ($errors) { $errors.Count | Should Be 0 }
        }
    }

    It 'never uses a bare + concatenation as an array element' {
        # PowerShell binds ',' tighter than '+', so @(a, 'b' + $x + 'c', d)
        # parses as (a, 'b') + $x + ('c', d): the concatenation is torn apart
        # and the array never even appears in the parse tree. The signature of
        # the torn form is a '+' whose operand is a comma-built array.
        foreach ($file in (Get-ChildItem (Join-Path $repoRoot 'windows') -Recurse -Include '*.ps1', '*.psm1')) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $file.FullName, [ref]$null, [ref]$null)
            $torn = @($ast.FindAll({
                param($node)
                if ($node -isnot [System.Management.Automation.Language.BinaryExpressionAst]) { return $false }
                if ($node.Operator -ne 'Plus') { return $false }
                foreach ($operand in @($node.Left, $node.Right)) {
                    # A parenthesised @(...) is an ArrayExpressionAst and is a
                    # deliberate array concatenation; only a bare comma-built
                    # ArrayLiteralAst betrays a torn concatenation.
                    if ($operand -is [System.Management.Automation.Language.ArrayLiteralAst] -and $operand.Elements.Count -gt 1) {
                        return $true
                    }
                }
                return $false
            }, $true))
            if ($torn.Count -gt 0) {
                throw "$($file.Name): '+' concatenation torn apart by a comma; wrap the concatenation in parentheses"
            }
        }
    }

    It 'binds GNU long options to script switches' {
        # PowerShell ignores `--desc` as a parameter name, so the dispatcher has
        # to translate it; without that, options were silently treated as names.
        $result = Invoke-Brew @('search', '--desc', 'browser')
        $result.ExitCode | Should Be 0
        $result.Text | Should Match '==> Packages'
    }

    It 'answers --version from the entry point' {
        $result = Invoke-Brew @('--version')
        $result.ExitCode | Should Be 0
        $result.Text | Should Match 'ScoopBrew'
        $result.Text | Should Match 'Scoop v?\d'
    }

    It 'explains a Homebrew command that has no Scoop equivalent' {
        $result = Invoke-Brew @('typecheck')
        $result.ExitCode | Should Not Be 0
        $result.Text | Should Match 'not supported by the Scoop backend'
    }

    It 'rejects a genuine typo with a suggestion, not an explanation' {
        $result = Invoke-Brew @('insatll')
        $result.ExitCode | Should Not Be 0
        $result.Text | Should Match 'Unknown command'
    }

    It 'reports a usage error instead of a .NET binding exception' {
        $result = Invoke-Brew @('which')
        $result.ExitCode | Should Not Be 0
        $result.Text | Should Match 'Usage: brew which'
    }

    It 'runs doctor through the captured scoop checkup' {
        # Machine state decides the verdict, so only assert the flow: the
        # checkup section ran and a final summary was reached.
        $result = Invoke-Brew @('doctor')
        $result.ExitCode | Should Match '^[01]$'
        $result.Text | Should Match '==> Running scoop checkup'
        $result.Text | Should Match '(ready to brew|problem\(s\))'
    }
}

Describe 'unsupported command coverage' {
    It 'covers every command Homebrew itself ships' {
        $repoCommands = @()
        foreach ($dir in @('Library\Homebrew\cmd', 'Library\Homebrew\dev-cmd')) {
            $full = Join-Path $repoRoot $dir
            if (-not (Test-Path -LiteralPath $full)) { continue }
            $repoCommands += @(Get-ChildItem $full -Filter "*.rb" | ForEach-Object { $_.BaseName })
        }
        $repoCommands = @($repoCommands | Sort-Object -Unique)

        $implemented = @(Get-ChildItem (Join-Path $repoRoot 'windows\commands') -Filter 'brew-*.ps1' |
            ForEach-Object { $_.BaseName -replace '^brew-', '' })

        # Handled by the entry point rather than a command file.
        $implemented += @('--version', '--help', 'help', 'version', 'commands')

        $silent = @($repoCommands | Where-Object {
            $implemented -notcontains $_ -and -not (Get-BrewUnsupportedCommand -Name $_)
        })

        if ($silent.Count -gt 0) {
            throw "commands with neither an implementation nor a reason: $($silent -join ', ')"
        }
        $silent.Count | Should Be 0
    }
}
