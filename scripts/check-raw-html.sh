#!/usr/bin/env bash
#
# check-raw-html.sh - DOM-XSS sink tripwire for the frontend source tree.
#
# WHAT THIS CATCHES (and what it does NOT)
#   This is a grep tripwire, deliberately, not an ESLint rule. It reliably
#   catches the two cases that matter in practice:
#     - literal use of a raw-HTML / trust-bypass sink in source text, and
#     - `[innerHTML]="..."` style template bindings,
#   i.e. the accidental reintroduction and the plainly-deliberate one.
#
#   It does NOT and CANNOT catch dynamically-obfuscated access such as
#   `el['inner' + 'HTML'] = x` or an aliased DomSanitizer method - any grep is
#   evadable by constructing the sink name at runtime. That surface is covered
#   by code review and by the CSP / Trusted Types work landing with evidence
#   rendering (M3/M4), not by this script. An honest tripwire that names its
#   limits is worth more than one that claims coverage it does not have.
#
#   Why a grep and not a lint rule at all: this guard sits OUTSIDE the files it
#   scans, so it cannot be silenced from within a diff (no inline
#   `// eslint-disable`). That property is the whole point - keep it a grep.
#
# BEHAVIOUR (fails CLOSED)
#   exit 0  scanned cleanly, no sink found
#   exit 1  a forbidden sink was found
#   exit 2  the scan could not be trusted (bad target, or grep errored - e.g.
#           an unreadable file) => treated as failure, never as "clean"
#
# USAGE
#   scripts/check-raw-html.sh [target-dir]     # default target: frontend/src
#   Runs identically locally and in CI (raw-html-gate.yml).
#
set -euo pipefail

TARGET="${1:-frontend/src}"

# Broad sink set. `bypassSecurityTrust` is a PREFIX match on purpose so the
# whole DomSanitizer family is caught: bypassSecurityTrustHtml / ...Style /
# ...Script / ...Url / ...ResourceUrl. `SecurityContext . NONE` tolerates
# whitespace around the dot (valid TS that would otherwise slip a naive `\.`).
# Add sinks here; never remove them.
PATTERN='innerHTML|outerHTML|insertAdjacentHTML|bypassSecurityTrust|SecurityContext[[:space:]]*\.[[:space:]]*NONE|createContextualFragment|DOMParser|srcdoc'

if [ ! -d "$TARGET" ]; then
  echo "check-raw-html: target directory not found: $TARGET - failing closed" >&2
  exit 2
fi

# -r recursive, -E extended regex, -n line numbers, -a force TEXT (so a file
# whose bytes start with NUL is still scanned, not silently skipped as binary),
# --include allowlist so we scan source and never trip over real binary assets.
# We branch on grep's exit code EXPLICITLY: `set -e` does not catch a
# command-substitution failure in an `if` condition, so an if/else on grep would
# treat "no match" (1) and "error" (>=2) identically and fail OPEN. It must not.
rc=0
matches="$(grep -rEna \
  --include='*.ts' \
  --include='*.html' \
  --include='*.js' \
  "$PATTERN" "$TARGET")" || rc=$?

case "$rc" in
  0)
    echo "FAIL: raw-html gate found forbidden DOM/HTML sink(s) in $TARGET" >&2
    echo >&2
    echo "$matches" >&2
    echo >&2
    echo "These sinks can turn attacker-controlled text into executed markup." >&2
    echo "Render via Angular interpolation/binding; do not reach for raw HTML." >&2
    exit 1
    ;;
  1)
    echo "OK: raw-html gate found no forbidden sinks in $TARGET"
    exit 0
    ;;
  *)
    echo "check-raw-html: grep failed (rc=$rc) - failing closed" >&2
    exit 2
    ;;
esac
