#!/bin/bash

set -u

full_name="Ifeoma Jane Akabueze"
tf_dir="terraform"

plan_binary="tfplan.out"
plan_json="tfplan.json"

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
report_dir="$base_dir/reports"
report_file="$report_dir/tf-drift-report.txt"

checks=(
  check_plan_exit_code
  check_destructive_actions
  check_open_ingress
)

pass_count=0
warning_count=0
failure_count=0
plan_exit_code=0

mkdir -p "$report_dir"

: > "$report_file"

# Remove previous plan JSON so stale evidence is not reused.
rm -f "$report_dir/$plan_json"

write_line() {
  echo "$1" | tee -a "$report_file"
}

mark_pass() {
  write_line "[PASS] $1"
  pass_count=$((pass_count + 1))
}

mark_warning() {
  write_line "[WARN] $1"
  warning_count=$((warning_count + 1))
}

mark_failure() {
  write_line "[FAIL] $1"
  failure_count=$((failure_count + 1))
}

print_header() {
  write_line "========================================"
  write_line "Terraform Drift and Policy Review Report"
  write_line "========================================"
  write_line "Full Name: $full_name"
  write_line "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  write_line "Terraform Directory: $tf_dir"
  write_line ""
}

run_plan() {
  write_line "Running: terraform plan -detailed-exitcode -out=$plan_binary"
  write_line ""

  (cd "$tf_dir" && terraform plan -input=false -detailed-exitcode -out="$plan_binary")
  plan_exit_code=$?

  if [ "$plan_exit_code" -eq 2 ]
  then
    (cd "$tf_dir" && terraform show -json "$plan_binary") > "$report_dir/$plan_json" 2>/dev/null || true
  fi
}

check_plan_exit_code() {
  case "$plan_exit_code" in

    0)
      mark_pass "terraform plan exit code 0 — no pending changes"
      ;;

    1)
      mark_failure "terraform plan exit code 1 — Terraform plan failed"
      ;;

    2)
      mark_warning "terraform plan exit code 2 — changes are pending and require review"
      ;;

    *)
      mark_failure "terraform plan returned unexpected exit code: $plan_exit_code"
      ;;

  esac
}

check_destructive_actions() {
  local plan_path="$report_dir/$plan_json"
  local destructive_count

  if [ "$plan_exit_code" -ne 2 ] || [ ! -s "$plan_path" ]
  then
    mark_pass "No pending plan JSON to inspect for destructive actions"
    return
  fi

  # Terraform plan JSON represents replacement as a combination
  # containing both delete and create.
  # Therefore, checking for delete catches both deletion and replacement.

  destructive_count=$(jq \
    '[.resource_changes[]? |
      select(.change.actions | index("delete"))] |
      length' \
    "$plan_path" 2>/dev/null || echo 0)

  if [ -z "$destructive_count" ]
  then
    destructive_count=0
  fi

  if [ "$destructive_count" -gt 0 ]
  then
    mark_failure "$destructive_count resource(s) would be deleted or replaced"

    jq -r \
      '.resource_changes[]? |
       select(.change.actions | index("delete")) |
       "  - \(.address): \(.change.actions | join(","))"' \
      "$plan_path" 2>/dev/null | tee -a "$report_file"
  else
    mark_pass "No delete or replace actions found in the plan"
  fi
}

check_open_ingress() {
  local plan_path="$report_dir/$plan_json"
  local open_cidr_count

  if [ "$plan_exit_code" -ne 2 ] || [ ! -s "$plan_path" ]
  then
    mark_pass "No pending plan JSON to inspect for open ingress rules"
    return
  fi

  open_cidr_count=$(jq \
    '[.resource_changes[]? |
      select(.change.actions != ["no-op"]) |
      select(.change.after != null) |
      .change.after |
      (.ingress // [], .security_rule // []) |
      .[]? |
      select(
        (.cidr_blocks // [] | index("0.0.0.0/0"))
        or
        (.source_address_prefix // "") == "*"
      )] |
      length' \
    "$plan_path" 2>/dev/null || echo 0)

  if [ -z "$open_cidr_count" ]
  then
    open_cidr_count=0
  fi

  if [ "$open_cidr_count" -gt 0 ]
  then
    mark_failure "$open_cidr_count ingress rule(s) would open access to 0.0.0.0/0 or *"
  else
    mark_pass "No ingress rules found opening access to 0.0.0.0/0 or *"
  fi
}

print_summary() {
  local overall_status
  local script_exit_code

  if [ "$failure_count" -gt 0 ]
  then
    overall_status="FAIL"
    script_exit_code=2

  elif [ "$warning_count" -gt 0 ]
  then
    overall_status="WARN"
    script_exit_code=1

  else
    overall_status="HEALTHY"
    script_exit_code=0
  fi

  write_line ""
  write_line "Summary:"
  write_line "PASS: $pass_count"
  write_line "WARN: $warning_count"
  write_line "FAIL: $failure_count"
  write_line "Overall Status: $overall_status"
  write_line "Script Exit Code: $script_exit_code"
  write_line "Report File: $report_file"
  write_line ""
  write_line "This script only ran Terraform plan and show commands."
  write_line "It never ran terraform apply or terraform destroy."

  return "$script_exit_code"
}

print_header

run_plan

for check_function in "${checks[@]}"
do
  "$check_function"
done

print_summary

exit $?
