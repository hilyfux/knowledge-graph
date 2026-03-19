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
# Strategy: find all relative import paths, resolve to target directories
DEPS=""
for mod in $MODULES; do
  # JS/TS: extract relative paths from import/require
  IMPORTS=$(grep -rhoE "(from\s+['\"]\.\.?/[^'\"]+|require\(['\"]\.\.?/[^'\"]+)" "$mod" 2>/dev/null | grep -oE '\.\.?/[^"'"'"')+]+' | sort -u)
  # Python: relative imports
  PY_IMPORTS=$(grep -rhoE "from\s+\.\S+" "$mod" 2>/dev/null | grep -oE '\.\S+' | sort -u)

  for imp in $IMPORTS; do
    # Resolve: if mod=src/api and imp=../auth → target=src/auth
    TARGET=$(cd "$CLAUDE_PROJECT_DIR/$mod" 2>/dev/null && cd "$imp" 2>/dev/null && pwd) || continue
    TARGET="${TARGET#$CLAUDE_PROJECT_DIR/}"
    # Only keep the directory part
    [ -d "$CLAUDE_PROJECT_DIR/$TARGET" ] || TARGET=$(dirname "$TARGET")
    [ "$TARGET" = "$mod" ] && continue
    echo "$MODULES" | grep -q "^$TARGET$" && DEPS="$DEPS{\"from\":\"$mod\",\"to\":\"$TARGET\"},"
  done

  # Python relative imports use dots: from .utils → same dir, from ..models → parent
  for imp in $PY_IMPORTS; do
    DOTS=$(echo "$imp" | grep -oE '^\\.+' | wc -c)
    DOTS=$((DOTS - 1))
    TARGET="$mod"
    for i in $(seq 1 $DOTS); do TARGET=$(dirname "$TARGET"); done
    [ "$TARGET" = "$mod" ] && continue
    echo "$MODULES" | grep -q "^$TARGET$" && DEPS="$DEPS{\"from\":\"$mod\",\"to\":\"$TARGET\"},"
  done
done
DEPS_JSON=$(echo "[${DEPS%,}]" | jq -c 'unique' 2>/dev/null || echo "[]")

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
  if echo "$RECENT_MSGS" | grep -qE '^(feat|fix|chore|docs|refactor|test|perf)(\(.+\))?:'; then
    CONVENTIONS="conventional-commits"
  fi
fi

# --- Project type detection ---
PROJECT_TYPE="unknown"
if [ -f "package.json" ] || [ -f "tsconfig.json" ] || find . -maxdepth 4 \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) -not -path "*/node_modules/*" 2>/dev/null | head -1 | grep -q .; then
  PROJECT_TYPE="js/ts"
elif [ -f "Cargo.toml" ]; then
  PROJECT_TYPE="rust"
elif [ -f "go.mod" ]; then
  PROJECT_TYPE="go"
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ]; then
  PROJECT_TYPE="python"
elif [ -f "pom.xml" ] || [ -f "build.gradle" ]; then
  PROJECT_TYPE="java"
fi

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
