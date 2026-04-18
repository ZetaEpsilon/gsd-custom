# gsd-custom

Soft fork overrides for `gsd-build/get-shit-done`.

This repo intentionally contains only local customizations, keeping upstream folder paths so patches can be reapplied cleanly.

## Upstream

- Source: https://github.com/gsd-build/get-shit-done
- Local install root: `~/.claude`
- Patch root: `~/.claude/gsd-local-patches`

## What this repo stores

- `agents/...` overrides
- `get-shit-done/...` overrides
- `skills/...` custom slash-command skills synced into `~/.claude/skills` by `scripts/pull.ps1`
- No full upstream source tree

## Daily workflow

1. Edit files in `~/.claude/gsd-local-patches`.
2. Commit and push this repo.
3. Pull on other machines and keep using GSD normally.

## After upstream updates

1. Update GSD normally from upstream.
2. Pull this repo:
   - `powershell -ExecutionPolicy Bypass -File scripts/pull.ps1`
3. In your Claude session, run `/gsd-reapply-patches` when prompted by GSD update flow.

## Custom commands

- `/gsd-code-review-cross <phase>` — cross-AI post-execution code review (Codex/Gemini/Claude/etc.)
- `/gsd-execute-phase <phase> --cross-review` — run cross-AI review automatically after built-in code review
