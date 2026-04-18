$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Host "Updating gsd-custom overrides in $repoRoot..."
git -C $repoRoot pull --ff-only

$skillsRoot = Join-Path $repoRoot "skills"
$claudeRoot = Join-Path $HOME ".claude"
$claudeSkills = Join-Path $claudeRoot "skills"

if (Test-Path $skillsRoot) {
  Write-Host "Syncing custom skills to $claudeSkills..."
  New-Item -ItemType Directory -Path $claudeSkills -Force | Out-Null

  Get-ChildItem -Path $skillsRoot -Directory | ForEach-Object {
    $sourceDir = $_.FullName
    $destDir = Join-Path $claudeSkills $_.Name
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    Copy-Item -Path (Join-Path $sourceDir "*") -Destination $destDir -Recurse -Force
  }
}

Write-Host ""
Write-Host "Done. If you just updated GSD upstream, run /gsd-reapply-patches in Claude."
