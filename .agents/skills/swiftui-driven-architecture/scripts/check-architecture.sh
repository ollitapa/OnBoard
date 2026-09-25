#!/bin/sh
# Greps a Swift source tree for architecture anti-patterns.
# Usage: ./check-architecture.sh [source-dir]   (default: current directory)
# Exits 1 if any violation is found.

set -u
DIR="${1:-.}"
STATUS=0

# check <rule> <pattern> [exclude-pattern]
check() {
    rule="$1"
    pattern="$2"
    exclude="${3:-}"
    hits=$(grep -rnE --include='*.swift' "$pattern" "$DIR" 2>/dev/null || true)
    if [ -n "$exclude" ]; then
        hits=$(printf '%s\n' "$hits" | grep -vE "$exclude" || true)
    fi
    if [ -n "$hits" ]; then
        printf '\n✗ %s\n%s\n' "$rule" "$hits"
        STATUS=1
    fi
}

check "Rule 1: no ObservableObject/@Published — use @Observable" \
    ': *ObservableObject|@Published'

check "Rule 3: never construct State manually — use an inline @State default" \
    'State\(initialValue:|_[a-zA-Z]+ = State\('

# Rule 5 needs lookahead: flag .onChange only when a Task is started inside it.
onchange_hits=$(grep -rnE --include='*.swift' -A3 '\.onChange\(of:' "$DIR" 2>/dev/null \
    | grep -E 'Task *\{' || true)
if [ -n "$onchange_hits" ]; then
    printf '\n✗ %s\n%s\n' \
        "Rule 5: no .onChange + unstructured Task — use .task(id:)" "$onchange_hits"
    STATUS=1
fi

check "Rule 6: no computed 'some View' properties — extract a View struct" \
    'var [a-zA-Z]+: some View' \
    'var body: some View'

check "Rule 7: no singletons — inject through the environment" \
    'static (let|var) shared'

check "Storage: never cache container.mainContext — pass it per call site" \
    'let [a-zA-Z]+ = .*\.mainContext'

if [ "$STATUS" -eq 0 ]; then
    printf '✓ No architecture anti-patterns found in %s\n' "$DIR"
else
    printf '\nReview each hit; a few are legitimate (e.g. a locally-scoped context).\n'
fi

exit "$STATUS"
