# Usage: brew autoremove
# Summary: Report that unneeded-dependency removal is not possible on Scoop.
# Group: lifecycle
# Help: Homebrew can remove dependencies that are no longer needed because every
#       Tab records whether a package was installed on request. Scoop's
#       install.json only stores architecture, url and bucket, so the backend
#       cannot tell a deliberately installed package from a pulled-in one, and
#       guessing would delete things you asked for.
param(
    [switch]$DryRun,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Tokens
)

Test-ScoopInstalled | Out-Null

brewMessage "The Scoop backend does not record why a package was installed."
brewMessage "install.json only stores 'architecture', 'url' and 'bucket', so brew cannot"
brewMessage "distinguish a package you asked for from one pulled in as a dependency."
brewMessage ''
brewMessage "Use 'brew leaves' to list installed packages nothing depends on, and"
brewMessage "remove the ones you do not want explicitly:"
brewMessage "    brew uninstall <package>"
exit 1
