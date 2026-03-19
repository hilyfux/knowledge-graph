#!/bin/bash
# scan-project.sh — Pre-scan project structure for init skill
# Outputs .claude/graph-scan.json with modules, dependencies, git signals.
# The LLM then only generates CLAUDE.md CONTENT, not does the scanning.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

OUTPUT="$CLAUDE_PROJECT_DIR/.claude/graph-scan.json"
SKIP='.git|node_modules|dist|build|.next|__pycache__|.venv|vendor|target|.claude'

cd "$CLAUDE_PROJECT_DIR" || exit 1

# --- Modules: directories with 3+ files ---
MODULES=$(find . -type f \
  -not -path './.git/*' -not -path '*/node_modules/*' \
  -not -path '*/dist/*' -not -path '*/build/*' \
  -not -path '*/.next/*' -not -path '*/__pycache__/*' \
  -not -path '*/.venv/*' -not -path '*/vendor/*' \
  -not -path '*/target/*' -not -path '*/.claude/*' \
  2>/dev/null | sed 's|^\./||' | xargs -I{} dirname {} | sort | uniq -c | sort -rn | awk '$1 >= 3 {print $2}' | head -30)

# --- Existing CLAUDE.md files ---
EXISTING=$(find . -name "CLAUDE.md" -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | sed 's|^\./||' | sort)

# --- Dependencies: extract cross-directory imports ---
DEPS=""
for mod in $MODULES; do
  # JS/TS imports
  IMPORTS=$(grep -rhoP "(?:import\s+.*from\s+['\"]|require\(['\"])(\.[^'\"]+)" "$mod" 2>/dev/null | grep -oP '\.[^"'"'"']+' | sort -u)
  # Python imports (relative)
  IMPORTS="$IMPORTS"$'\n'$(grep -rhoP "from\s+(\.\S+)" "$mod" 2>/dev/null | grep -oP '\.\S+' | sort -u)

  for imp in $IMPORTS; do
    # Resolve relative path to directory
    TARGET=$(cd "$mod" 2>/dev/null && realpath --relative-to="$CLAUDE_PROJECT_DIR" "$imp" 2>/dev/null | xargs dirname 2>/dev/null)
    [ -z "$TARGET" ] && continue
    [ "$TARGET" = "$mod" ] && continue  # skip self-references
    # Check target is a known module
    echo "$MODULES" | grep -q "^$TARGET$" && DEPS="$DEPS{\"from\":\"$mod\",\"to\":\"$TARGET\"},"
  done
done
DEPS_JSON="[${DEPS%,}]"
[ -z "$DEPS" ] && DEPS_JSON="[]"

# --- Git signals ---
COCHANGE_JSON="[]"
FIXES=""
CONVENTIONS=""
if command -v git &>/dev/null && git rev-parse --git-dir &>/dev/null; then
  # Co-change files
  COCHANGE_JSON=$(git log --pretty=format: --name-only -50 2>/dev/null | grep -v '^$' | sort | uniq -c | sort -rn | head -10 | awk '{print $2}' | jq -R . | jq -s . 2>/dev/null || echo "[]")

  # Fix/bug/revert history
  FIXES=$(git log --oneline --all --grep='fix\|bug\|revert\|broken' -10 2>/dev/null | head -10)

  # Commit message convention detection
  RECENT_MSGS=$(git log --pretty=format:'%s' -20 2>/dev/null)
  if echo "$RECENT_MSGS" | grep -qP '^(feat|fix|chore|docs|refactor|test|perf)(\(.+\))?:'; then
    CONVENTIONS="conventional-commits"
  fi
fi

# --- Project type detection ---
PROJECT_TYPE="unknown"
[ -f "package.json" ] && PROJECT_TYPE="js/ts"
[ -f "Cargo.toml" ] && PROJECT_TYPE="rust"
[ -f "go.mod" ] && PROJECT_TYPE="go"
[ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ] && PROJECT_TYPE="python"
[ -f "pom.xml" ] || [ -f "build.gradle" ] && PROJECT_TYPE="java"

# --- File counts ---
TOTAL_FILES=$(find . -type f -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/.claude/*' 2>/dev/null | wc -l | tr -d ' ')
TOTAL_DIRS=$(echo "$MODULES" | wc -l | tr -d ' ')

# --- Assemble ---
jq -n \
  --arg type "$PROJECT_TYPE" \
  --argjson files "$TOTAL_FILES" \
  --argjson dirs "$TOTAL_DIRS" \
  --argjson deps "$DEPS_JSON" \
  --argjson cochange "$COCHANGE_JSON" \
  --arg fixes "${FIXES:-}" \
  --arg conventions "${CONVENTIONS:-}" \
  --arg modules "$(echo "$MODULES" | tr '\n' '|')" \
  --arg existing "$(echo "$EXISTING" | tr '\n' '|')" \
  '{
    project_type: $type,
    total_files: $files,
    total_dirs: $dirs,
    modules: ($modules | split("|") | map(select(. != ""))),
    existing_claude_md: ($existing | split("|") | map(select(. != ""))),
    dependencies: $deps,
    cochange_files: $cochange,
    recent_fixes: $fixes,
    conventions: $conventions
  }' > "$OUTPUT"

echo "$TOTAL_FILES files, $TOTAL_DIRS modules scanned"
exit 0
