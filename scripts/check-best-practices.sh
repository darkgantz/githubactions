#!/usr/bin/env bash
set -euo pipefail

ERRORS=0

fail() {
  echo "::error::$1"
  ERRORS=$((ERRORS + 1))
}

warn() {
  echo "::warning::$1"
}

info() {
  echo "::notice::$1"
}

# --- Section 4.6 & 13.1: No hardcoded secrets ---
echo "Checking for hardcoded secrets..."

SECRET_PATTERNS=(
  '(password|passwd|pwd)\s*[:=]\s*["\x27][^"\x27${}]+'
  '(api[_-]?key|apikey)\s*[:=]\s*["\x27][^"\x27${}]+'
  '(secret|client[_-]?secret)\s*[:=]\s*["\x27][^"\x27${}]+'
  '(private[_-]?key)\s*[:=]\s*["\x27][^"\x27${}]+'
  '(jwt[_-]?secret)\s*[:=]\s*["\x27][^"\x27${}]+'
  '(database[_-]?password|db[_-]?password)\s*[:=]\s*["\x27][^"\x27${}]+'
  'ghp_[A-Za-z0-9]{36}'
  'ghs_[A-Za-z0-9]{36}'
  'sk-[A-Za-z0-9]{32,}'
)

for pattern in "${SECRET_PATTERNS[@]}"; do
  while IFS= read -r file; do
    [[ "$file" == *node_modules* ]] && continue
    [[ "$file" == *.git* ]] && continue
    [[ "$file" == *package-lock* ]] && continue
    [[ "$file" == *cspell-dict* ]] && continue
    [[ "$file" == *BEST_PRACTICES* ]] && continue

    if grep -qiE "$pattern" "$file" 2>/dev/null; then
      fail "Possible hardcoded secret in $file (Section 4.6/13.1: Never hardcode credentials)"
    fi
  done < <(git diff --name-only --diff-filter=ACMR HEAD~1 2>/dev/null || git ls-files)
done

# --- Section 17: Commit message conventions ---
echo "Checking commit messages..."

VALID_PREFIXES="^(feat|fix|refactor|test|docs|chore|ci|build|perf|style|revert):"

LAST_COMMIT_MSG=$(git log -1 --pretty=%s 2>/dev/null || echo "")
if [[ -n "$LAST_COMMIT_MSG" ]]; then
  if ! echo "$LAST_COMMIT_MSG" | grep -qE "$VALID_PREFIXES"; then
    fail "Last commit message does not follow conventional format: '$LAST_COMMIT_MSG' (Section 17: Use feat:, fix:, refactor:, etc.)"
  fi
fi

# --- Section 18: PR description validation ---
echo "Checking PR description..."

if [[ -n "${GITHUB_PULL_REQUEST_BODY:-}" ]]; then
  PR_BODY="$GITHUB_PULL_REQUEST_BODY"

  MISSING=()
  [[ ! "$PR_BODY" =~ [Cc]hanged|\.[Cc]hange ]] && MISSING+=("What changed?")
  [[ ! "$PR_BODY" =~ [Ww]hy|[Rr]eason ]] && MISSING+=("Why?")
  [[ ! "$PR_BODY" =~ [Tt]est|[Vv]erif ]] && MISSING+=("How was it tested?")

  if [[ ${#MISSING[@]} -gt 0 ]]; then
    for item in "${MISSING[@]}"; do
      fail "PR description missing: $item (Section 18: PR should explain What/Why/How tested)"
    done
  fi
else
  info "GITHUB_PULL_REQUEST_BODY not set, skipping PR description check"
fi

# --- Section 32: Architecture red flags ---
echo "Checking for architecture red flags..."

CHANGED_FILES=$(git diff --name-only --diff-filter=ACMR HEAD~1 2>/dev/null || echo "")

if [[ -n "$CHANGED_FILES" ]]; then
  # Check for SQL string concatenation (Section 13.4)
  for file in $CHANGED_FILES; do
    [[ "$file" == *node_modules* ]] && continue
    [[ "$file" == *.java ]] || continue

    if grep -qE '"\s*\+\s*.*SELECT|"SELECT\s*"\s*\+|"\s*\+\s*.*INSERT|"INSERT\s*"\s*\+' "$file" 2>/dev/null; then
      fail "SQL string concatenation detected in $file (Section 13.4: Use prepared statements)"
    fi
  done

  # Check for entities exposed directly (Section 4.3)
  for file in $CHANGED_FILES; do
    [[ "$file" == *node_modules* ]] && continue
    [[ "$file" == *.java ]] || continue

    if grep -qE '@Entity' "$file" 2>/dev/null; then
      if grep -qE '@RestController|@Controller' "$file" 2>/dev/null; then
        fail "JPA Entity found in controller file $file (Section 4.3: Do not expose entities directly)"
      fi
    fi
  done
fi

# --- Section 2.4: No silently ignored errors ---
echo "Checking for silently ignored errors..."

if [[ -n "$CHANGED_FILES" ]]; then
  for file in $CHANGED_FILES; do
    [[ "$file" == *node_modules* ]] && continue
    [[ "$file" == *.java ]] || continue

    if grep -qE 'catch\s*\(.*\)\s*\{\s*\}' "$file" 2>/dev/null; then
      fail "Silent empty catch block found in $file (Section 2.4: Never silently ignore errors)"
    fi
  done
fi

# --- Section 4.6: Environment variables for config ---
echo "Checking for environment variable usage..."

if [[ -n "$CHANGED_FILES" ]]; then
  for file in $CHANGED_FILES; do
    [[ "$file" == *node_modules* ]] && continue
    [[ "$file" == *.java ]] || continue

    if grep -qE 'jdbc:postgresql://[^"]*"' "$file" 2>/dev/null; then
      if ! grep -qE '\$\{.*\}' "$file" 2>/dev/null; then
        warn "Database URL may be hardcoded in $file (Section 4.6: Use environment variables)"
      fi
    fi
  done
fi

# --- Summary ---
echo ""
echo "================================"
if [[ $ERRORS -gt 0 ]]; then
  echo "FAILED: $ERRORS error(s) found"
  echo "Fix the issues above to comply with BEST_PRACTICES_SPRING_VUE_MICROSERVICES.md"
  echo "================================"
  exit 1
else
  echo "PASSED: All best practices checks passed"
  echo "================================"
  exit 0
fi
