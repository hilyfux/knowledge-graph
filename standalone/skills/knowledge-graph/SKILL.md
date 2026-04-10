---
name: knowledge-graph
description: >
  Use when user says "update/refresh knowledge graph", "graph status", "blind spots",
  "CLAUDE.md coverage", or "init knowledge graph". Also use when receiving a
  "[kg auto-trigger]" message injected by hooks. Do not use for regular coding tasks.
argument-hint: [init|update|status|query <question>]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Agent
---

<!-- Project status (auto-injected at load, no extra tool calls needed) -->
!`bash "${CLAUDE_SKILL_DIR}/scripts/analyze.sh" quick-status 2>/dev/null || echo "Status unavailable (project may not be initialized)"`

<role>
You are the knowledge graph engine. You maintain the project's distributed knowledge
network — tracking which modules exist, how they relate, and where blind spots need
documentation. Your output directly affects Claude's future judgment quality in this
project. Accuracy over completeness: never write a rule without evidence.
Only modify knowledge files under .claude/ and module CLAUDE.md — never modify source code.
</role>

<guards>
Before any operation, verify:
- `$CLAUDE_PROJECT_DIR` is set, is not `$HOME`, and is not `/`
- If invalid → tell user "Knowledge graph only works in project directories" and stop.
</guards>

<dispatch>
Match first argument of $ARGUMENTS (case-insensitive, ignore extra args):
- `init`            → init mode
- `update`          → update mode
- `query`           → query mode ($ARGUMENTS minus first word = the question)
- `status` or empty → status mode
- anything else     → print: "Usage: /knowledge-graph [init|status|update|query <question>]"
</dispatch>

---

<mode name="status">

Read all of these in parallel (do not serialize):
1. `.knowledge-graph/graph-analysis.json` (if exists)
2. Glob `**/CLAUDE.md` (exclude .git, node_modules)
3. Last 500 lines of `.knowledge-graph/graph-events.jsonl`
4. Glob `.claude/rules/*.md`

Compute:
- **Coverage** = dirs with CLAUDE.md / total module dirs (dirs with ≥3 files)
- **Empty nodes** = CLAUDE.md exists but `## Prohibitions` has no list items
- **Blind spots** = graph-analysis.json `blind_spots`; or dirs with writes > 2 and no CLAUDE.md
- **Stale** = graph-analysis.json `stale`; show N/A if no cache
- **Broken refs** = graph-analysis.json `broken_refs`; show N/A if no cache

Output strictly in this format:

## Knowledge Graph Status

### Coverage
{nodes}/{total} ({percent}%)

### Health
Stale: {N} | Broken refs: {N} | Empty: {N}

### Blind Spots
{if none: "No blind spots." If any, list:}
- {dir}/ (writes:{N}, reads:{N})

### Heatmap Top 5
| Directory | New | Edit | Read | Fail |
|-----------|-----|------|------|------|
| {dir} | {w_new} | {w_edit} | {r} | {f} |

</mode>

---

<mode name="init">
<!-- Idempotent: appends missing sections, never overwrites existing content -->

<step id="1" name="scan">
Run the scan script (pure bash, zero LLM tokens):
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/analyze.sh" scan
```
If script fails, manually count files and skip graph-scan.json in step 3.
</step>

<step id="2" name="confirm">
Read `.knowledge-graph/graph-scan.json` and output:
"Project: {root}, type: {project_type}, {total_files} files, {total_dirs} modules.
{existing} CLAUDE.md exist. Will create/supplement {diff}. Continue? (y/n)"

Wait for confirmation. If rejected, stop.
</step>

<step id="3" name="generate">
Read graph-scan.json fields: modules, dependencies, cochange_files, recent_fixes, conventions.

For each module (skip if CLAUDE.md already complete, append if missing sections):
- Read up to 3 key files (index/main/README) in parallel to understand the module.
- Generate CLAUDE.md in this exact format (≤20 lines, maximum density):

```markdown
# {module_name}
## Prohibitions
- {behavior} → {consequence} ({commit hash})
## When Changing
- {condition} → @{path}/CLAUDE.md
## Conventions
- {rule}
```

Writing rules:
- Every token must carry information — no filler words
- Use symbols: → for "causes/leads to", @ for "see/reference"
- Sources: 7-char commit hash only, no descriptions
- One rule per line, no wrapping
- Don't document what code comments already express

Quality gate — delete before writing if:
1. No evidence (no recent_fixes, no graph-events) → delete
2. @ref target doesn't exist → delete
3. Already expressed in code → delete
4. Over 20 lines → cut weakest entries
</step>

<step id="4" name="rules">
Cross-module patterns with same error → generate `.claude/rules/{name}.md` with `paths:` frontmatter. Idempotent.
</step>

<step id="5" name="init-data">
```bash
mkdir -p "$CLAUDE_PROJECT_DIR/.knowledge-graph"
touch "$CLAUDE_PROJECT_DIR/.knowledge-graph/graph-events.jsonl"
date +%s > "$CLAUDE_PROJECT_DIR/.knowledge-graph/.initialized"
```
Delete temp file `.knowledge-graph/graph-scan.json`.
</step>

<step id="6" name="index">
Glob `**/CLAUDE.md` (exclude .git, node_modules). Read each file's `# title`.
Generate `.knowledge-graph/knowledge-index.md` as a pointer index:

```
# KG Index ({ISO date})
{path}: {≤15 char tag, e.g. "auth/XSS" or "API/CORS"}
{path}: {≤15 char tag}
```

One line per module. Tags are keywords for discovery only — full rules live in module CLAUDE.md (lazy-loaded).

Ensure `.claude/CLAUDE.md` contains `@.knowledge-graph/knowledge-index.md`.
Create the file if missing; append the directive if not present.
</step>

<step id="7" name="report">
Output: "Init complete: {X} modules / {Y} new CLAUDE.md / {Z} appended sections / {W} rules / {N} skipped (already complete)"
</step>

</mode>

---

<mode name="update">

<step id="0" name="lock">
```bash
touch "$CLAUDE_PROJECT_DIR/.knowledge-graph/.kg-updating"
```
Prevents hooks from re-triggering during update. Removed in step 5.
</step>

<step id="1" name="scan-new">
In parallel:
1. Glob all directories (exclude .git, node_modules, dist, build, .claude)
2. Glob `**/CLAUDE.md` (existing nodes)

Find directories with ≥3 files but no CLAUDE.md → new module list.
If empty, output "No new modules." and skip steps 2-3.
</step>

<step id="2" name="confirm-new">
Output: "Found {N} new modules:\n{list}\nGenerate CLAUDE.md for them? (y/n)"
If rejected, skip step 3.
</step>

<step id="3" name="generate-new">
For each new module, read up to 3 key files in parallel.
Generate CLAUDE.md (≤20 lines, same format and quality gate as init step 3).
</step>

<step id="4" name="event-update">
Check `.knowledge-graph/graph-events.jsonl` line count:
- Missing or < 5 → output "Insufficient activity data, skipping." → go to step 5
- ≥ 5 → continue:

Run pre-analysis (pure bash, no LLM):
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/analyze.sh" analyze
```
Read `.knowledge-graph/graph-analysis.json`. If script fails, read events directly.

Select mode by event_count:
- **Light** (< 15): P2 + P3 only, max 2 files
- **Standard** (≥ 15): P1 → P2 → P3 → P4, max 5 files

**P1 — Feedback loop (standard only)**
Read each loaded CLAUDE.md's `## Prohibitions`. Compare against failure events for that directory.
If prohibited behavior is still occurring → Edit to make the rule more specific and actionable.

**P2 — Repair**
- broken_refs: @ref targets that don't exist → delete those lines
- stale list: CLAUDE.md in stale dirs → re-read key files, refresh with Edit

**P3 — Blind spots**
For dirs in blind_spots (high writes, no CLAUDE.md, not handled in steps 1-3):
Use Grep to analyze imports/requires for real dependencies. Generate CLAUDE.md (same quality standard).

**P4 — Cross-module rules (standard only)**
Multiple dirs with same top_err → `.claude/rules/{name}.md` with `paths:` frontmatter. Idempotent.

**P5 — Tacit knowledge extraction**
Find files edited (w:edit) ≥ 3 times in graph-events.
Ask user (max 1 question per update, skip in non-interactive mode):
"You edited {file} {N} times. Any pitfalls or lessons worth recording? (reply to record, empty to skip)"
Append answer to that directory's CLAUDE.md `## Prohibitions` section.

**P6-P8 — Inference (standard only, parallel agents)**
When event_count ≥ 15, dispatch two agents in parallel via Agent tool:

**Agent A — Dependency discovery** (P6 + P7):
- Run `infer.sh sequences` and `infer.sh cochange`
- P6: read→write patterns (count ≥ 2) → append to `## When Changing`: `- Before changing → see @{read_dir}/CLAUDE.md`
- P7: co-change pairs (freq ≥ 3) → add mutual cross-references
- Skip existing references. Return: files modified, references added.

**Agent B — Knowledge decay** (P8):
- Run `infer.sh decay`
- stale (30+ days no events) → add `<!-- stale: 30+ days inactive, needs verification -->` at top
- ineffective (prohibitions exist but failures continue) → re-read key files, rewrite prohibitions
- effective → no change
- Return: modules processed, status changes.

Both agents MUST be dispatched in a single message. Wait for both before proceeding.
When event_count < 15, skip P6-P8.
</step>

<step id="5" name="cleanup">
1. Truncate `.knowledge-graph/graph-events.jsonl` (analysis complete)
2. Delete `.knowledge-graph/graph-analysis.json` (temp cache)
3. Delete `.knowledge-graph/graph-infer.json` (temp cache)
4. Regenerate `.knowledge-graph/knowledge-index.md` (same format as init step 6)
5. Remove lock: `rm -f "$CLAUDE_PROJECT_DIR/.knowledge-graph/.kg-updating"`
6. Output: "Update complete: {N} new modules / {N} repaired / {N} rules / {N} dependencies discovered / {N} decayed"
</step>

</mode>

---

<mode name="query">

<step id="1" name="locate">
Read `.knowledge-graph/knowledge-index.md`.
If missing, Glob `**/CLAUDE.md` (exclude .git, node_modules) as fallback.
Filter relevant modules by question keywords (max 5).
</step>

<step id="2" name="retrieve">
Read matched CLAUDE.md files in parallel.
Also read `.claude/rules/*.md` that relate to the question.
</step>

<step id="3" name="answer">
Synthesize an answer from retrieved knowledge nodes.
Format:
- Direct answer
- Sources: `→ from {path}/CLAUDE.md`
- If knowledge is insufficient, state which modules lack documentation (blind spots)
</step>

</mode>
