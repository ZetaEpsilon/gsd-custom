---
name: gsd-code-review-cross
description: "Run cross-AI post-execution code review for a phase using external CLIs (Codex, Gemini, Claude, etc.)"
argument-hint: "<phase-number> [--gemini] [--claude] [--codex] [--coderabbit] [--opencode] [--qwen] [--cursor] [--all] [--files=file1,file2,...]"
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
---

<objective>
Run a cross-AI code review over phase implementation changes and synthesize consensus findings.

This is a post-execution advisory review (not plan review):
- Resolves changed file scope (`--files` override > SUMMARY.md > git diff fallback)
- Invokes external AI CLIs with a shared review prompt
- Writes `{padded_phase}-REVIEW-CROSS.md` in the phase directory

Use after `/gsd-execute-phase` when you want second-opinion code scrutiny before shipping.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/code-review-cross.md
</execution_context>

<context>
Phase: first positional argument in `$ARGUMENTS` (required).

Optional reviewer filters:
- `--gemini`
- `--claude`
- `--codex`
- `--coderabbit`
- `--opencode`
- `--qwen`
- `--cursor`
- `--all`

Optional scope override:
- `--files=file1,file2,...`
</context>

<process>
Execute the cross code-review workflow from
@$HOME/.claude/get-shit-done/workflows/code-review-cross.md end-to-end.
</process>

