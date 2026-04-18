<purpose>
Execute a trivial task inline without subagent overhead. No PLAN.md, no Task spawning,
no research, no plan checking. Just: understand → do → commit → log.

For tasks like: fix a typo, update a config value, add a missing import, rename a
variable, commit uncommitted work, add a .gitignore entry, bump a version number.

Use /gsd-quick for anything that needs multi-step planning or research.
</purpose>

<process>

<step name="parse_task">
Parse `$ARGUMENTS` for the task description.

If empty, ask:
```
What's the quick fix? (one sentence)
```

Store as `$TASK`.
</step>

<step name="scope_check">
**Before doing anything, verify this is actually trivial.**

A task is trivial if it can be completed in:
- ≤ 3 file edits
- ≤ 1 minute of work
- No new dependencies or architecture changes
- No research needed

If the task seems non-trivial (multi-file refactor, new feature, needs research),
say:

```
This looks like it needs planning. Use /gsd-quick instead:
  /gsd-quick "{task description}"
```

And stop.
</step>

<step name="execute_inline">

**Multi-AI classification (before execution):**

1. Check Codex availability and config:
   ```bash
   command -v codex >/dev/null 2>&1 && CODEX_OK=true || CODEX_OK=false
   CODEX_ENABLED=$(node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" \
     config-get routing.codex_enabled 2>/dev/null || echo "true")
   ```

2. Classify the task:
   - Contains file paths or code references → code task → try Codex
   - Is a question, explanation, or content task → non-code → Opus inline

3. **If code task AND CODEX_OK AND CODEX_ENABLED=true:**
   a. Dirty-file precondition: identify task files from $TASK context.
      Check each with `git diff --name-only`. If ANY task file is dirty,
      skip Codex and fall through to Opus inline. Log:
      `"Task file '{f}' is dirty — executing inline as Opus"`
   b. Snapshot:
      ```bash
      CODEX_BASE_SHA=$(git rev-parse HEAD)
      PRE_CODEX_DIRTY=$(git diff --name-only 2>/dev/null | sort)
      PRE_CODEX_UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null \
        | grep -v '^\.artifacts/' | sort)
      ```
   c. Build Codex prompt from $TASK
   d. Dispatch via codex-dispatch helper
   e. On success: selective commit — stage ONLY declared task files
      (`git add {task_files}`, NOT `git add -A`), then proceed to log_to_state
   f. On failure/escalation: task-scoped rollback (Case A + Case B
      from execute-plan route_task_by_ai), then fall back to Opus inline below

4. **If non-code task OR Codex unavailable:**
   Do the work directly (current behavior):
   - Read the relevant file(s)
   - Make the change(s)
   - Verify the change works (run existing tests if applicable, or do a quick sanity check)

**No PLAN.md.** Just do it.
</step>

<step name="commit">
Commit the change atomically:

```bash
git add -A
git commit -m "fix: {concise description of what changed}"
```

Use conventional commit format: `fix:`, `feat:`, `docs:`, `chore:`, `refactor:` as appropriate.

**Note:** If the task was handled by Codex with selective staging in execute_inline,
the commit was already made there. Skip this step in that case.
</step>

<step name="log_to_state">
If `.planning/STATE.md` exists, append to the "Quick Tasks Completed" table.
If the table doesn't exist, skip this step silently.

```bash
# Check if STATE.md has quick tasks table
if grep -q "Quick Tasks Completed" .planning/STATE.md 2>/dev/null; then
  # Append entry — workflow handles the format
  echo "| $(date +%Y-%m-%d) | fast | $TASK | ✅ |" >> .planning/STATE.md
fi
```
</step>

<step name="done">
Report completion:

```
✅ Done: {what was changed}
   Commit: {short hash}
   Files: {list of changed files}
```

No next-step suggestions. No workflow routing. Just done.
</step>

</process>

<guardrails>
- NEVER spawn a Task/subagent — this runs inline
- NEVER create PLAN.md or SUMMARY.md files
- NEVER run research or plan-checking
- If the task takes more than 3 file edits, STOP and redirect to /gsd-quick
- If you're unsure how to implement it, STOP and redirect to /gsd-quick
</guardrails>

<success_criteria>
- [ ] Task completed in current context (no subagents)
- [ ] Atomic git commit with conventional message
- [ ] STATE.md updated if it exists
- [ ] Total operation under 2 minutes wall time
</success_criteria>
