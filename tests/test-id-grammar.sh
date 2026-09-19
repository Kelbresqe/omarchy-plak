#!/usr/bin/env bash
# The id grammar lives in two languages; this keeps them identical.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0; n=0
while IFS='|' read -r want id; do
  [ -z "$want" ] && continue
  n=$((n+1))
  js=$(node -e 'const Y=require("./Ytm.js"); process.exit(Y.isValidId(process.argv[1]) ? 0 : 1)' -- "$id" && echo ok || echo bad)
  py=$(python3 bin/ytm-bridge --check-id="$id" && echo ok || echo bad)
  if [ "$js" != "$want" ] || [ "$py" != "$want" ]; then
    echo "FAIL: '$id' want=$want js=$js py=$py"; fail=1
  fi
done < tests/fixtures/ids.txt
echo "test-id-grammar: $n ids checked"
exit $fail
