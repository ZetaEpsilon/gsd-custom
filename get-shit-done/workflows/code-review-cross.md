<purpose>
Cross-AI post-execution code review for a phase. Combines deterministic file scoping from code-review with external CLI reviewers (Codex, Gemini, Claude, etc.), then synthesizes consensus findings into a single artifact.

Use after /gsd-execute-phase or as a deeper advisory check before shipping.
</purpose>

<required_reading>
Read all files referenced by the invoking prompt's execution_context before starting.
</required_reading>

<process>

<step name="initialize">
Parse arguments and load phase context:

```bash
PHASE_ARG="${1}"
INIT=$(gsd-sdk query init.phase-op "${PHASE_ARG}")
if [[ "$INIT" == @file:* ]]; then INIT=$(cat "${INIT#@file:}"); fi
```

Parse from init JSON: `phase_found`, `phase_dir`, `phase_number`, `phase_name`, `padded_phase`, `commit_docs`.

If `phase_found` is false:
```
Error: Phase ${PHASE_ARG} not found. Run /gsd-progress to see available phases.
```
Exit.

Parse optional flags from `$ARGUMENTS`:
- `--gemini`
- `--claude`
- `--codex`
- `--coderabbit`
- `--opencode`
- `--qwen`
- `--cursor`
- `--all`
- `--files=file1,file2,...` (explicit file scope override)
</step>

<step name="detect_clis">
Check which external AI CLIs are available:

```bash
command -v gemini >/dev/null 2>&1 && echo "gemini:available" || echo "gemini:missing"
command -v claude >/dev/null 2>&1 && echo "claude:available" || echo "claude:missing"
command -v codex >/dev/null 2>&1 && echo "codex:available" || echo "codex:missing"
command -v coderabbit >/dev/null 2>&1 && echo "coderabbit:available" || echo "coderabbit:missing"
command -v opencode >/dev/null 2>&1 && echo "opencode:available" || echo "opencode:missing"
command -v qwen >/dev/null 2>&1 && echo "qwen:available" || echo "qwen:missing"
command -v cursor >/dev/null 2>&1 && echo "cursor:available" || echo "cursor:missing"
```

Reviewer selection rules:
- If one or more reviewer flags were provided, use only those requested and available CLIs.
- `--all` means all available CLIs.
- If no reviewer flags were provided, use all available CLIs.

Runtime self-skip rules for independence:
- If running inside Claude Code (`CLAUDE_CODE_ENTRYPOINT` set), skip `claude`.
- If running inside Cursor agent (`CURSOR_SESSION_ID` set), skip `cursor`.
- If running in Antigravity (`ANTIGRAVITY_AGENT=1`), skip none.
- Otherwise, skip only the current runtime CLI if the runtime can self-identify.

If no eligible external CLI remains, display:
```
No eligible external AI CLI available for cross review.
Install at least one of: gemini, codex, claude, opencode, qwen, cursor.
```
Exit.
</step>

<step name="compute_file_scope">
Determine files to review with precedence:

1. `--files=` override (highest precedence)
2. Extract `key_files.created` + `key_files.modified` from phase `*-SUMMARY.md`
3. Git diff fallback using phase commits

**Tier 1 — --files override**

If `--files=` is present:
```bash
IFS=',' read -ra REVIEW_FILES <<< "${FILES_OVERRIDE}"
```

Trim empty entries and keep only existing files.

**Tier 2 — SUMMARY-based scope**

If no `--files=` override, parse each `*-SUMMARY.md` file in `phase_dir` and extract:
- `key_files.created[]`
- `key_files.modified[]`

If SUMMARY files exist but extract to zero files, continue to fallback.

**Tier 3 — Git diff fallback**

If still zero files:
```bash
PHASE_COMMITS=$(git log --oneline --all --grep="${PADDED_PHASE}" --format="%H" 2>/dev/null)
```

If commits exist, derive a safe diff base from the earliest commit for this phase:
- Preferred: `earliest_commit^`
- If parent doesn't exist (repo root commit): use `earliest_commit`

Then:
```bash
git diff --name-only "${DIFF_BASE}..HEAD" -- . \
  ':!.planning/' ':!ROADMAP.md' ':!STATE.md' \
  ':!*-SUMMARY.md' ':!*-VERIFICATION.md' ':!*-PLAN.md' \
  ':!package-lock.json' ':!yarn.lock' ':!Gemfile.lock' ':!poetry.lock'
```

**Post-filtering for all tiers**

Remove:
- `.planning/**`
- planning/report artifacts (`*-PLAN.md`, `*-SUMMARY.md`, `*-VERIFICATION.md`)
- deleted/nonexistent files

Deduplicate file list.

If final scope is empty:
```
No source files to cross-review for phase ${PHASE_NUMBER}.
Skipping cross review.
```
Exit without creating REVIEW-CROSS.md.
</step>

<step name="build_prompt">
Build a structured prompt in `/tmp/gsd-code-review-cross-prompt-{phase}.md` with:

1. Project context
   - First ~80 lines of `.planning/PROJECT.md` (if exists)
   - Phase section from `.planning/ROADMAP.md` (if exists)

2. Review scope
   - Phase number/name
   - Exact list of files in scope

3. Code context
   - Unified diff for scoped files (prefer `${DIFF_BASE}..HEAD` when available)
   - If diff is unavailable, include current file contents for each scoped file

4. Instructions to reviewer:

```markdown
# Cross-AI Code Review Request

You are reviewing implemented code changes for a completed phase.
Focus on correctness and production risk.

Provide output in this exact structure:

1. Summary
2. Findings (severity-tagged):
   - `CRITICAL | HIGH | MEDIUM | LOW`
   - Include file path and line evidence where possible
   - Explain user impact and fix direction
3. Missing tests / verification gaps
4. Suggested next actions (ordered)
5. Overall risk: `LOW | MEDIUM | HIGH`

Review for:
- Behavioral regressions
- Security vulnerabilities
- Data integrity issues
- Race conditions / async bugs
- Error handling gaps
- Performance footguns
- Migration/deployment risk
```
</step>

<step name="invoke_reviewers">
Read optional model preferences from config:

```bash
GEMINI_MODEL=$(gsd-sdk query config-get review.models.gemini 2>/dev/null | jq -r '.' 2>/dev/null || true)
CLAUDE_MODEL=$(gsd-sdk query config-get review.models.claude 2>/dev/null | jq -r '.' 2>/dev/null || true)
CODEX_MODEL=$(gsd-sdk query config-get review.models.codex 2>/dev/null | jq -r '.' 2>/dev/null || true)
OPENCODE_MODEL=$(gsd-sdk query config-get review.models.opencode 2>/dev/null | jq -r '.' 2>/dev/null || true)
```

Invoke each selected CLI sequentially (avoid rate-limit spikes). Write outputs to:
- `/tmp/gsd-code-review-cross-{cli}-{phase}.md`

Use the same invocation style as `/gsd-review` for each CLI.

If one CLI fails, capture a short failure note in its output file and continue.
</step>

<step name="write_artifact">
Create `${phase_dir}/${padded_phase}-REVIEW-CROSS.md` with frontmatter:

```yaml
---
phase: {phase_number}
phase_name: "{phase_name}"
reviewed_at: {iso_timestamp}
reviewers: [list]
files_reviewed: {count}
status: clean|issues_found|partial|skipped
overall_risk: LOW|MEDIUM|HIGH
---
```

Body format:

```markdown
# Cross-AI Code Review — Phase {N}

## Scope
- Files reviewed: {count}
- Reviewers: {list}

## Per-Reviewer Output
### {Reviewer}
{raw reviewer output}

## Consensus Findings
### Critical/High
{merged high-priority items with source reviewers}

### Medium/Low
{merged lower-priority items}

### Test Gaps
{shared verification gaps}

## Recommended Actions
1. ...
2. ...

## Divergences
{where reviewers disagreed}
```

Status rules:
- `clean`: no substantive findings across reviewers
- `issues_found`: one or more actionable findings
- `partial`: some reviewers failed, but at least one completed
- `skipped`: no files / no reviewer available

If `commit_docs` is true and file was produced:
```bash
gsd-sdk query commit "docs: cross-ai code review for phase {N}" "${PHASE_DIR}/${PADDED_PHASE}-REVIEW-CROSS.md"
```
</step>

<step name="present_results">
Display concise summary:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 GSD ► CROSS CODE REVIEW COMPLETE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Phase {N}: reviewed by {count} external AI reviewer(s)
Status: {status}
Overall risk: {overall_risk}
Output: {padded_phase}-REVIEW-CROSS.md
```

If issues were found:
```
Cross-AI review surfaced actionable risks.
Address findings, then re-run:
  /gsd-code-review-cross {PHASE_NUMBER}
```

Always note this gate is advisory (non-blocking unless the user chooses to enforce it).
</step>

</process>

<success_criteria>
- [ ] Phase validated before execution
- [ ] File scope resolved via --files > SUMMARY > git diff fallback
- [ ] At least one external reviewer invoked (or explicit skip reason shown)
- [ ] REVIEW-CROSS.md created with consensus synthesis when review runs
- [ ] Non-blocking behavior preserved
</success_criteria>

