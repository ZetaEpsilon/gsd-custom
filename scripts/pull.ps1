$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Host "Updating gsd-custom overrides in $repoRoot..."
git -C $repoRoot pull --ff-only

Write-Host ""
Write-Host "Done. If you just updated GSD upstream, run /gsd-reapply-patches in Claude."

