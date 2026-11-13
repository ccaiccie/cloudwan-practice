#!/usr/bin/env bash
# Runs every case in tests/cases.txt through bin/cwsim.sh and compares the output with tests/expected/<name>.txt.
set -uo pipefail
cd "$(dirname "$0")/.."
pass=0; fail=0
while IFS='|' read -r name args; do
  name=$(echo "$name" | xargs); [ -z "$name" ] || [ "${name:0:1}" = "#" ] && continue
  got=$(bin/cwsim.sh $args 2>&1 | tr -d '\r'); want=$(tr -d '\r' < "tests/expected/$name.txt")
  if [ "$got" = "$want" ]; then pass=$((pass+1)); echo "PASS $name"
  else fail=$((fail+1)); echo "FAIL $name"; diff <(echo "$want") <(echo "$got") | sed 's/^/     /'; fi
done < tests/cases.txt
echo "bash: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
