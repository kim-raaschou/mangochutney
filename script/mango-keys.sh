#!/bin/sh
# Extract every config key, rule field and dispatcher name from a mango source tree.
#
#   script/mango-keys.sh <mango-dir> <out-dir>
#
# Writes one name per line, sorted, to <out-dir>/{options,keywords,window_rule,tag_rule,
# monitor_rule,layer_rule,device_rule,dispatchers}.txt and the mango version and commit to
# <out-dir>/VERSION. Tests/mango-keys holds the output for the mango version the port
# tracks; MangoCoverageTests requires each name to be implemented or ignored with a reason,
# and `make mango-diff` compares a newer mango against it.
#
# Source of truth is mango's code, not its docs:
#   src/config/option_defs.c   parse_option(): one top-level branch per key (one tab
#                              deep); rule fields are the keys inside the *_rule branches
#   src/config/binding_parse.c dispatcher names (strcmp(func_name, ...)) and the bind
#                              keyword family (bind + any of s l r p c)
set -eu

mango=${1:?usage: mango-keys.sh <mango-dir> <out-dir>}
out=${2:?usage: mango-keys.sh <mango-dir> <out-dir>}
defs="$mango/src/config/option_defs.c"
binds="$mango/src/config/binding_parse.c"
[ -f "$defs" ] && [ -f "$binds" ] || { echo "not a mango source tree: $mango" >&2; exit 1; }
mkdir -p "$out"

# Keys the config parser treats as keywords (structure, not settings).
keywords="key_mode var source source_optional env exec exec_once window_rule window_rule_once
tag_rule monitor_rule layer_rule device_rule mousebind axisbind gesturebind switchbind"

# Every top-level key of parse_option, tagged with the rule block it opens (if any).
# A top-level branch is "\t} else if (strcmp(key, ..." or "\t} else if (strncmp(key, ...";
# a condition continued with "||" on the next line belongs to the same branch.
LC_ALL=C awk '
    # Print every key of a strcmp(key, "...") / strncmp(key, "...") on the line, tagged.
    function emit(tag, line,    k) {
        while (match(line, /str(n)?cmp\(key, "[a-z_0-9]+"/)) {
            k = substr(line, RSTART, RLENGTH)
            sub(/^str(n)?cmp\(key, "/, "", k); sub(/"$/, "", k)
            print tag " " k
            line = substr(line, RSTART + RLENGTH)
        }
    }
    { sub(/\r$/, "") }                     # mango sources use CRLF line endings
    /^\t(\} else )?if \(/ {
        cont = ($0 ~ /\|\|[ \t]*$/)
        block = ""
        if (match($0, /"(window_rule|tag_rule|monitor_rule|layer_rule|device_rule)"/))
            block = substr($0, RSTART + 1, RLENGTH - 2)
        if (match($0, /is_title_message_bar_decorate_key\(key, "[a-z_]+"/)) {
            k = substr($0, RSTART, RLENGTH)
            sub(/^is_title_message_bar_decorate_key\(key, "/, "", k); sub(/"$/, "", k)
            print "top title_message_bar_decorate_" k
            next
        }
        emit("top", $0)
        next
    }
    cont { cont = ($0 ~ /\|\|[ \t]*$/); emit("top", $0); next }
    block != "" { emit(block, $0) }
' "$defs" > "$out/.all"

kw_re=$(printf '%s\n' $keywords | paste -sd'|' -)
awk '$1 == "top" {print $2}' "$out/.all" | grep -Ev "^($kw_re)\$" | sort -u > "$out/options.txt"
{ awk '$1 == "top" {print $2}' "$out/.all" | grep -Ex "$kw_re"
  # bind + flags (binding_parse.c: "bind" followed by any of s l r p c)
  grep -q 'strncmp(str, "bind", 4)' "$binds" && echo bind
} | sort -u > "$out/keywords.txt"
for b in window_rule tag_rule monitor_rule layer_rule device_rule; do
    # A rule block also tests the keyword itself (window_rule_once sets is_once): not a field.
    awk -v b="$b" '$1 == b {print $2}' "$out/.all" | grep -Ev "^($kw_re)\$" | sort -u > "$out/$b.txt"
done
rm "$out/.all"

grep -oE 'strcmp\(func_name, "[a-z_]+"\)' "$binds" | sed -E 's/.*"([^"]+)".*/\1/' | sort -u > "$out/dispatchers.txt"

version=$(sed -nE "s/^[[:space:]]*version[[:space:]]*:[[:space:]]*'([^']+)'.*/\1/p" "$mango/meson.build" | head -1)
commit=$(git -C "$mango" rev-parse HEAD 2>/dev/null || echo unknown)
printf 'mango %s\ncommit %s\n' "${version:-unknown}" "$commit" > "$out/VERSION"

for f in options keywords window_rule tag_rule monitor_rule layer_rule device_rule dispatchers; do
    printf '%-13s %4d\n' "$f" "$(wc -l < "$out/$f.txt")"
done
