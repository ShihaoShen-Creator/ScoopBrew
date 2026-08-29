# Usage: brew developer [status|on|off]
# Summary: Control which Scoop channel updates follow.
# Group: meta
# Help: Homebrew's developer mode makes `brew update` track the latest commits
#       rather than the last stable release. Scoop has the same switch: its
#       `scoop_branch` setting chooses which branch of `scoop_repo` is checked
#       out on update.
#
#   on    track the development branch
#   off   track the released branch
param(
    [Parameter(Position = 0)][string]$Action
)

Test-ScoopInstalled | Out-Null

$branch = @(Invoke-Scoop -Capture config scoop_branch) -join ''
$branch = $branch.Trim()
$repo = @(Invoke-Scoop -Capture config scoop_repo) -join ''
$repo = $repo.Trim()

switch ($Action) {
    { $_ -in @($null, 'status') } {
        brewMessage "developer mode: $(if ($branch -and $branch -ne 'master') { 'on' } else { 'off' })"
        brewMessage "Scoop branch: $(if ($branch) { $branch } else { 'master (default)' })"
        brewMessage "Scoop repository: $(if ($repo) { $repo } else { 'ScoopInstaller/Scoop (default)' })"
        brewMessage ''
        brewMessage 'Note: Homebrew developer mode also enables extra deprecation'
        brewMessage 'warnings and stricter audits. Scoop has no such flag, so only'
        brewMessage 'the update channel is controlled here.'
        exit 0
    }

    'on' {
        brewMessage "==> Tracking the 'develop' branch of Scoop"
        exit (Invoke-Scoop config scoop_branch develop)
    }

    'off' {
        brewMessage "==> Tracking the released 'master' branch of Scoop"
        exit (Invoke-Scoop config scoop_branch master)
    }

    default {
        Abort-Brew "Unknown developer subcommand: $Action (expected status, on or off)"
    }
}
