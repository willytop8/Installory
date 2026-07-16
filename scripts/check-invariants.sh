#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

SOURCE_DIRS=(Installory/Sources App/Sources)
ENTITLEMENTS="App/Installory.entitlements"

fail() {
    echo "✗ $*" >&2
    exit 1
}

require_file() {
    [ -f "$1" ] || fail "Required file is missing: $1"
}

# Report source matches while ignoring lines that contain comments only. This
# keeps invariant documentation such as "No Process() calls" from failing the
# check without attempting to implement a full Swift lexer in shell.
reject_swift_pattern() {
    local label="$1"
    local pattern="$2"
    local raw_matches
    local code_matches

    if command -v rg >/dev/null 2>&1; then
        raw_matches="$(rg -n --no-heading --glob '*.swift' "$pattern" "${SOURCE_DIRS[@]}" || true)"
    else
        raw_matches="$(find "${SOURCE_DIRS[@]}" -type f -name '*.swift' -exec grep -EnH "$pattern" {} + || true)"
    fi
    code_matches="$(printf '%s\n' "$raw_matches" | awk '
        {
            source = $0
            sub(/^[^:]+:[0-9]+:/, "", source)
            sub(/^[[:space:]]*/, "", source)
            if (source ~ /^\/\// || source ~ /^\/\*/ || source ~ /^\*/) next
            if (length(source) > 0) print $0
        }
    ')"

    if [ -n "$code_matches" ]; then
        echo "✗ $label found in production Swift source:" >&2
        printf '%s\n' "$code_matches" >&2
        exit 1
    fi
}

matches_pattern() {
    local pattern="$1"
    local file="$2"

    if command -v rg >/dev/null 2>&1; then
        rg -q "$pattern" "$file"
    else
        grep -Eq "$pattern" "$file"
    fi
}

count_pattern() {
    local pattern="$1"
    local file="$2"

    if command -v rg >/dev/null 2>&1; then
        rg -c "$pattern" "$file" || true
    else
        grep -Ec "$pattern" "$file" || true
    fi
}

command -v grep >/dev/null 2>&1 || fail "grep is required"
command -v find >/dev/null 2>&1 || fail "find is required"
command -v git >/dev/null 2>&1 || fail "git is required"

for directory in "${SOURCE_DIRS[@]}"; do
    [ -d "$directory" ] || fail "Production source directory is missing: $directory"
done

reject_swift_pattern \
    "Process() usage" \
    '(^|[^[:alnum:]_])Process[[:space:]]*\('
reject_swift_pattern \
    "Networking API usage" \
    '(^|[^[:alnum:]_])(URLSession|URLRequest|URLProtocol|NWConnection|NWListener|NWBrowser|NWPathMonitor|CFNetwork)([^[:alnum:]_]|$)|^[[:space:]]*import[[:space:]]+Network([^[:alnum:]_]|$)'

require_file project.yml
require_file "$ENTITLEMENTS"
/usr/bin/plutil -lint "$ENTITLEMENTS" >/dev/null

expected_entitlements=(
    com.apple.security.app-sandbox
    com.apple.security.files.bookmarks.app-scope
    com.apple.security.files.user-selected.read-write
)

for key in "${expected_entitlements[@]}"; do
    value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$ENTITLEMENTS" 2>/dev/null || true)"
    [ "$value" = "true" ] || fail "Entitlement '$key' must exist and equal true"

    escaped_key="${key//./\\.}"
    matches_pattern "^[[:space:]]*${escaped_key}:[[:space:]]*true[[:space:]]*$" project.yml || \
        fail "project.yml must declare entitlement '$key: true'"
done

entitlement_count="$(/usr/bin/plutil -p "$ENTITLEMENTS" | /usr/bin/grep -c ' => ')"
[ "$entitlement_count" -eq "${#expected_entitlements[@]}" ] || \
    fail "Entitlements changed: expected exactly ${#expected_entitlements[@]} approved keys, found $entitlement_count"

project_entitlement_count="$(count_pattern '^[[:space:]]*com\.apple\.security\.' project.yml)"
[ "${project_entitlement_count:-0}" -eq "${#expected_entitlements[@]}" ] || \
    fail "project.yml entitlement set changed: expected exactly ${#expected_entitlements[@]} approved keys"

# The entitlement authorizes explicit save-panel destinations, but every
# persistent scanning bookmark must remain read-only.
matches_pattern '\.securityScopeAllowOnlyReadAccess' App/Sources/FolderAccessManager.swift || \
    fail "Scanning bookmarks must retain securityScopeAllowOnlyReadAccess"

require_file scripts/regenerate-xcode.sh
[ -x scripts/regenerate-xcode.sh ] || fail "scripts/regenerate-xcode.sh must be executable"
git check-ignore -q Installory.xcodeproj || \
    fail "Installory.xcodeproj must remain gitignored; project.yml is the source of truth"

echo "✓ Installory product invariants verified"
