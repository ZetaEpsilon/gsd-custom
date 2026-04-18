<purpose>
Research how to implement a phase. Spawns gsd-phase-researcher with phase context.

Standalone research command. For most workflows, use `/gsd-plan-phase` which integrates research automatically.
</purpose>

<available_agent_types>
Valid GSD subagent types (use exact names — do not fall back to 'general-purpose'):
- gsd-phase-researcher — Researches technical approaches for a phase
</available_agent_types>

<process>

## Step 0: Resolve Model Profile

@$HOME/.claude/get-shit-done/references/model-profile-resolution.md

Resolve model for:
- `gsd-phase-researcher`

## Step 1: Normalize and Validate Phase

@$HOME/.claude/get-shit-done/references/phase-argument-parsing.md

```bash
PHASE_INFO=$(node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" roadmap get-phase "${PHASE}")
```

If `found` is false: Error and exit.

## Step 2: Check Existing Research

```bash
ls .planning/phases/*${PHASE}*/*RESEARCH.md 2>/dev/null || true
```

This glob matches both padded (`01-slug/01-RESEARCH.md`) and unpadded (`1-slug/RESEARCH.md`)
naming conventions, consistent with how `init.cjs` detects research files via
`f.endsWith('-RESEARCH.md') || f === 'RESEARCH.md'`.

If exists: Offer update/view/skip options.

## Step 3: Gather Phase Context

```bash
INIT=$(node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" init phase-op "${PHASE}")
if [[ "$INIT" == @file:* ]]; then INIT=$(cat "${INIT#@file:}"); fi
# Extract: phase_dir, padded_phase, phase_number, state_path, requirements_path, context_path
AGENT_SKILLS_RESEARCHER=$(node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" agent-skills gsd-researcher 2>/dev/null)
```

## Step 3.5: Gemini Research (MANDATORY — Primary Researcher)

Gemini is the primary researcher. It ALWAYS runs. This is not optional.

```bash
command -v gemini >/dev/null 2>&1 && GEMINI_OK=true || GEMINI_OK=false
```

**If `GEMINI_OK=false`:** Display error and fall back to Opus researcher (Step 4):
```
WARNING: Gemini CLI not found on PATH — cannot run mandatory research.
Install gemini CLI to enable Gemini-first research pipeline.
Falling back to Opus researcher.
```
Skip to Step 4.

**If `GEMINI_OK=true` (expected path):**

1. Build a comprehensive research prompt from the phase context. Include:
   - Phase description, goal, and success criteria
   - Requirements from ROADMAP.md
   - CONTEXT.md decisions (user's locked design choices)
   - Relevant codebase patterns and existing code structure
   - Specific questions to investigate: libraries, patterns, pitfalls, integration points

2. Write the prompt to a temp file and dispatch via pipe transport:
   ```bash
   mkdir -p .artifacts

   # Write the research prompt to the temp file that the dispatch command reads
   cat > /tmp/gsd-gemini-research-${PADDED_PHASE}.md << 'GEMINI_PROMPT_EOF'
   Research implementation approach for Phase ${PHASE_NUM}: ${PHASE_NAME}

   Phase goal: ${PHASE_GOAL}
   Requirements: [extracted from requirements_path]
   User decisions: [extracted from context_path]
   Codebase patterns: [extracted from state_path]

   Investigate:
   - Best libraries and patterns for this phase
   - Common pitfalls and how to avoid them
   - Integration points with existing codebase
   - Any constraints or gotchas

   Provide comprehensive, actionable findings with concrete recommendations.
   GEMINI_PROMPT_EOF

   cat /tmp/gsd-gemini-research-${PADDED_PHASE}.md | gemini \
     > .artifacts/${PADDED_PHASE}-research-task-00-gemini-result.txt 2>/dev/null
   GEMINI_EXIT=$?
   ```

3. **If `GEMINI_EXIT=0` (success):**
   - Read the Gemini output from `.artifacts/${PADDED_PHASE}-research-task-00-gemini-result.txt`
   - Check if this is an **explicit research phase** (see detection below)
   - **If explicit research phase:** Write Gemini output to artifacts, then proceed to Step 4
     to run Opus researcher alongside (both contribute to RESEARCH.md)
   - **If normal phase:** Write the research findings directly to RESEARCH.md at
     `.planning/phases/${PHASE}-{slug}/${PHASE}-RESEARCH.md`, format as standard GSD
     RESEARCH.md with proper sections, display: `"Phase ${PHASE_NUM}: Gemini research complete."`
     **Skip Step 4** — Gemini alone is sufficient. Proceed to Step 5.

4. **If `GEMINI_EXIT != 0` (failure):**
   ```
   WARNING: Gemini research failed (exit=$GEMINI_EXIT) — falling back to Opus researcher.
   ```
   Continue to Step 4 (Opus researcher runs alone).

**Explicit research phase detection:**
A phase requires both Gemini AND Opus research when ANY of these are true:
- `workflow.research` config is `true` (the existing research-enabled flag)
- The task routing specifies `ai="opus+gemini"` for research tasks in the plan
- The phase name/goal contains words like "research", "investigate", "explore", "compare", "evaluate"

Note: When this workflow is invoked via `plan-phase.md` (the common path in autonomous mode),
the detection above determines whether Opus also runs. When the "normal phase" branch applies
(none of the above are true), Gemini's output is written directly to RESEARCH.md and Opus
is skipped — keeping research fast for phases that don't need deep investigation.

Check the config flag:
```bash
RESEARCH_FLAGGED=$(node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" \
  config-get workflow.research 2>/dev/null || echo "true")
```

When detected, display: `"Phase ${PHASE_NUM}: Explicit research phase — running both Gemini and Opus researchers."`

## Step 4: Spawn Opus Researcher

This step runs in TWO cases:
1. **Explicit research phase** — Opus runs alongside Gemini (both contribute)
2. **Gemini failed/unavailable** — Opus runs as fallback

**If Gemini succeeded AND this is an explicit research phase:**
Include Gemini's findings as context so Opus validates, challenges, and builds on them:

```
Task(
  prompt="<objective>
Research implementation approach for Phase {phase}: {name}
</objective>

<files_to_read>
- {context_path} (USER DECISIONS from /gsd-discuss-phase)
- {requirements_path} (Project requirements)
- {state_path} (Project decisions and history)
</files_to_read>

${AGENT_SKILLS_RESEARCHER}

<gemini_research>
[Contents of Gemini's research output from Step 3.5]

NOTE: Gemini has already researched this phase. Validate, challenge, and build
on these findings. Do your own independent research on top. Synthesize both
perspectives into a single comprehensive RESEARCH.md.
</gemini_research>

<additional_context>
Phase description: {description}
</additional_context>

<output>
Write to: .planning/phases/${PHASE}-{slug}/${PHASE}-RESEARCH.md
</output>",
  subagent_type="gsd-phase-researcher",
  model="{researcher_model}"
)
```

**If Gemini failed or unavailable (fallback):**

```
Task(
  prompt="<objective>
Research implementation approach for Phase {phase}: {name}
</objective>

<files_to_read>
- {context_path} (USER DECISIONS from /gsd-discuss-phase)
- {requirements_path} (Project requirements)
- {state_path} (Project decisions and history)
</files_to_read>

${AGENT_SKILLS_RESEARCHER}

<additional_context>
Phase description: {description}
</additional_context>

<output>
Write to: .planning/phases/${PHASE}-{slug}/${PHASE}-RESEARCH.md
</output>",
  subagent_type="gsd-phase-researcher",
  model="{researcher_model}"
)
```

## Step 5: Handle Return

- `## RESEARCH COMPLETE` — Display summary, offer: Plan/Dig deeper/Review/Done
- `## CHECKPOINT REACHED` — Present to user, spawn continuation
- `## RESEARCH INCONCLUSIVE` — Show attempts, offer: Add context/Try different mode/Manual

</process>
