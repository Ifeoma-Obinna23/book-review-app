#!/bin/bash
# PreToolUse hook: blocks terraform apply/destroy if the latest drift
# report shows Overall Status: FAIL.

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')

if ! echo "$command" | grep -qE '\bterraform[[:space:]]+(apply|destroy)\b'; then
  exit 0
fi

report="$CLAUDE_PROJECT_DIR/reports/tf-drift-report.txt"

if [ ! -f "$report" ]; then
  echo "BLOCKED: No drift report found at reports/tf-drift-report.txt. Run tf-drift-check.sh and review the result before running terraform apply/destroy." >&2
  exit 2
fi

status=$(grep "^Overall Status:" "$report" | awk -F': ' '{print $2}')

if [ "$status" = "FAIL" ]; then
  echo "BLOCKED: Latest drift report shows Overall Status: FAIL. Review reports/tf-drift-report.txt and resolve the findings before running terraform apply/destroy." >&2
  exit 2
fi

exit 0
