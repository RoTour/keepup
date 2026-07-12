#!/usr/bin/env bash
#
# check-raw-html.test.sh - fixture tests that PIN the guarantees of
# check-raw-html.sh so CI catches any regression that weakens the gate.
#
# Cases:
#   1. clean tree                 -> exit 0
#   2. literal sink               -> exit 1
#   3. [innerHTML] template bind  -> exit 1
#   4. NUL-prefixed .ts + sink    -> exit 1   (must NOT be skipped as binary)
#   5. whitespace-evaded NONE     -> exit 1   (SecurityContext . NONE)
#   6. unreadable file in target  -> exit 2   (fails CLOSED, not "clean")
#   7. obfuscated el['in'+'HTML'] -> exit 0   (DOCUMENTED known limit: a grep
#                                              cannot catch runtime-built names)
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/check-raw-html.sh"

WORK="$(mktemp -d)"
# chmod back before delete so an intentionally-unreadable fixture file can be
# cleaned up regardless of its mode.
trap 'chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

fails=0
run_case() {
  # run_case <name> <expected-exit> <target-dir>
  local name="$1" expected="$2" target="$3" rc=0
  bash "$GATE" "$target" >/dev/null 2>&1 || rc=$?
  if [ "$rc" = "$expected" ]; then
    echo "PASS  $name (exit $rc)"
  else
    echo "FAIL  $name (expected exit $expected, got $rc)"
    fails=$((fails + 1))
  fi
}

# 1. clean tree
d="$WORK/clean/frontend/src"; mkdir -p "$d"
printf 'export const greeting = "hello";\n' > "$d/app.ts"
run_case "clean-tree" 0 "$d"

# 2. literal sink
d="$WORK/literal/frontend/src"; mkdir -p "$d"
printf 'element.innerHTML = untrusted;\n' > "$d/app.ts"
run_case "literal-sink" 1 "$d"

# 3. [innerHTML] template binding
d="$WORK/binding/frontend/src"; mkdir -p "$d"
printf '<div [innerHTML]="evidence"></div>\n' > "$d/view.html"
run_case "template-binding" 1 "$d"

# 4. NUL-prefixed .ts still scanned as text
d="$WORK/nul/frontend/src"; mkdir -p "$d"
{ printf '\0'; printf 'const y = node.insertAdjacentHTML("beforeend", x);\n'; } > "$d/app.ts"
run_case "nul-prefixed-sink" 1 "$d"

# 5. whitespace-evaded SecurityContext . NONE
d="$WORK/ws/frontend/src"; mkdir -p "$d"
printf 'this.sanitizer.sanitize(SecurityContext . NONE, dirty);\n' > "$d/app.ts"
run_case "whitespace-none" 1 "$d"

# 6. unreadable file -> fail closed (exit 2). Root bypasses file perms, so skip
#    the assertion when running as root (CI runners are non-root).
d="$WORK/unreadable/frontend/src"; mkdir -p "$d"
printf 'const y = el.innerHTML;\n' > "$d/secret.ts"
chmod 000 "$d/secret.ts"
if [ "$(id -u)" = "0" ]; then
  echo "SKIP  unreadable-fails-closed (running as root; perms not enforced)"
else
  run_case "unreadable-fails-closed" 2 "$d"
fi

# 7. obfuscated runtime-built name -> NOT caught. This is the documented limit;
#    asserting exit 0 makes the boundary explicit and load-bearing in CI.
d="$WORK/obfuscated/frontend/src"; mkdir -p "$d"
printf "const y = el['inner' + 'HTML'];\n" > "$d/app.ts"
run_case "obfuscated-known-limit" 0 "$d"

echo
if [ "$fails" -eq 0 ]; then
  echo "check-raw-html.test: all cases passed"
  exit 0
fi
echo "check-raw-html.test: $fails case(s) failed"
exit 1
