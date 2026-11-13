#!/usr/bin/env bash
# cwsim.sh - offline simulation of AWS Cloud WAN routing-policy evaluation with BGP communities.
# Teaching aid only: it reads JSON files and prints results. It never calls AWS. Needs jq 1.6+.
set -euo pipefail
usage() { cat <<'U'
Usage:
  cwsim.sh --policy FILE --routes FILE --names p1[,p2]                     [--via-dx | --via-dx-before]
  cwsim.sh --policy FILE --routes FILE --label L --edge REGION --direction inbound|outbound [--via-dx | --via-dx-before]
  cwsim.sh --policy FILE --lint
  --via-dx         apply the Direct Connect gateway community rules first (Nov 2026 behaviour)
  --via-dx-before  simulate the old behaviour: no communities reach Cloud WAN over Direct Connect
U
exit 2; }
policy= routes= names= label= edge= direction= dx= lint=false
while [ $# -gt 0 ]; do case "$1" in
  --policy) policy=$2; shift 2;; --routes) routes=$2; shift 2;; --names) names=$2; shift 2;;
  --label) label=$2; shift 2;; --edge) edge=$2; shift 2;; --direction) direction=$2; shift 2;;
  --via-dx) dx=now; shift;; --via-dx-before) dx=before; shift;; --lint) lint=true; shift;; -h|--help) usage;; *) echo "unknown option: $1" >&2; usage;; esac; done
command -v jq >/dev/null || { echo "cwsim.sh needs jq (https://jqlang.github.io/jq/)" >&2; exit 3; }
[ -n "$policy" ] || usage
here=$(cd "$(dirname "$0")" && pwd)
if $lint; then
  out=$(jq -nr --slurpfile P "$policy" --argjson args '{"lint":true}' '$P[0] as $P | {routes: []} as $R | '"$(cat "$here/cwsim.jq")")
  echo "$out"; grep -q '^ERROR' <<<"$out" && exit 1 || exit 0
fi
[ -n "$routes" ] || usage
[ -n "$names" ] || { [ -n "$label" ] && [ -n "$edge" ] && [ -n "$direction" ]; } || usage
args=$(jq -nc --arg n "$names" --arg l "$label" --arg e "$edge" --arg d "$direction" --arg x "$dx" \
  '{names: (if $n == "" then null else $n end), label: $l, edge: $e, direction: $d, dx: $x, lint: false}')
jq -nr --slurpfile P "$policy" --slurpfile R "$routes" --argjson args "$args" '$P[0] as $P | $R[0] as $R | '"$(cat "$here/cwsim.jq" | grep -v '^#')"
