#!/usr/bin/env bash
#
# check-raw-html.sh - DOM-XSS sink gate for the frontend source tree.
#
# WHY A GREP AND NOT AN ESLINT RULE
#   This gate guards the ONE place attacker-controlled, LLM-extracted text can
#   reach a trainer's browser. A lint rule is the wrong tool here for two
#   reasons:
#     1. It is silenceable from INSIDE the file it guards, via an inline
#        `// eslint-disable-next-line` - i.e. the attacker's own diff can turn
#        the guard off.
#     2. It can be dodged by AST-level trickery (aliasing, computed property
#        access) that a rule keyed on syntax will not see.
#   A grep over the raw source text has neither weakness: it cannot be disabled
#   from within the scanned file, and it matches the text regardless of how the
#   sink is dressed up. Keep this a grep. Do NOT "upgrade" it to a lint rule.
#
# BEHAVIOUR
#   Exit 1 (fail CI) on ANY match of a raw-HTML / trust-bypass sink.
#   Exit 0 when the tree is clean.
#   Exit 2 on misuse (target directory missing).
#
# USAGE
#   scripts/check-raw-html.sh [target-dir]     # default target: frontend/src
#   Runnable locally and identically in CI (called by raw-html-gate.yml).
#
set -euo pipefail

TARGET="${1:-frontend/src}"

# Broad sink set. `bypassSecurityTrust` is a PREFIX match on purpose so the
# whole DomSanitizer family is caught: bypassSecurityTrustHtml / ...Style /
# ...Script / ...Url / ...ResourceUrl. Add sinks here; never remove them.
PATTERN='innerHTML|outerHTML|insertAdjacentHTML|bypassSecurityTrust|SecurityContext\.NONE|createContextualFragment|DOMParser|srcdoc'

if [ ! -d "$TARGET" ]; then
  echo "check-raw-html: target directory not found: $TARGET" >&2
  exit 2
fi

# -r recursive, -E extended regex, -n line numbers, -I skip binary files.
# grep exits 1 when there is no match; the `if` swallows that so `set -e`
# does not abort on the (desired) clean case.
if matches="$(grep -rEnI "$PATTERN" "$TARGET")"; then
  echo "FAIL: raw-html gate found forbidden DOM/HTML sink(s) in $TARGET" >&2
  echo >&2
  echo "$matches" >&2
  echo >&2
  echo "These sinks can turn attacker-controlled text into executed markup." >&2
  echo "Render via Angular interpolation/binding; do not reach for raw HTML." >&2
  echo "This gate is intentionally not disableable from inside the source." >&2
  exit 1
fi

echo "OK: raw-html gate found no forbidden sinks in $TARGET"
exit 0
