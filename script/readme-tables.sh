#!/bin/sh
# Replace the text between two marker lines of a Markdown file with the contents of
# another file (the markers stay).
#
#   script/readme-tables.sh README.md <generated.md> [marker]
#
# Used by `make readme-tables` to put `mango --list-ignored` into docs/compatibility.md between
# <!-- mango-compat:start --> and <!-- mango-compat:end --> (the default marker), and
# `mango --list-glance` between README.md's mango-glance markers.
set -eu
readme=${1:?usage: readme-tables.sh <readme> <generated> [marker]}
generated=${2:?usage: readme-tables.sh <readme> <generated> [marker]}
marker=${3:-mango-compat}
start="<!-- $marker:start -->"
end="<!-- $marker:end -->"
grep -qxF "$start" "$readme" && grep -qxF "$end" "$readme" || { echo "markers missing in $readme" >&2; exit 1; }
tmp=$(mktemp)
awk -v s="$start" -v e="$end" -v g="$generated" '
    $0 == s { print; while ((getline line < g) > 0) print line; skip = 1; next }
    $0 == e { skip = 0 }
    !skip { print }
' "$readme" > "$tmp"
mv "$tmp" "$readme"
