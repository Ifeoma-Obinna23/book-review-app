# Terraform Drift Review Summary

**Full Name:** Ifeoma Jane Akabueze

**Date:** 18/10/2026

## 1. Change Introduced

I introduced a controlled, intentional configuration change by adding a new `Owner = "Ifeoma Jane Akabueze"` tag to the `aws_vpc.main` resource in `terraform/modules/network/main.tf`, alongside the existing `Name` tag.

This was a Terraform configuration change, not true infrastructure drift. True drift happens when the real AWS resources change outside of Terraform (e.g. a manual console edit), so the live state no longer matches the `.tf` files. Here, I edited the `.tf` file itself, so Terraform's desired state temporarily differed from the deployed state — the opposite direction from real drift, but it produces the same kind of detectable mismatch when `terraform plan` is run, which made it a safe way to test the detection and review workflow.

## 2. Evidence Collected

Running `terraform plan -detailed-exitcode` showed `module.network.aws_vpc.main will be updated in-place`, with the `tags` map gaining `+ "Owner" = "Ifeoma Jane Akabueze"`, and a summary of `Plan: 0 to add, 1 to change, 0 to destroy`. The detailed exit code returned `2`, confirming a pending, non-destructive change. Running `tf-drift-check.sh` against this plan produced a report showing `[WARN]` on the pending plan, `[PASS]` on no delete/replace actions, and (after fixing a false positive described below) `[PASS]` on open ingress — giving an overall `WARN` status rather than a `FAIL`.

## 3. Risk Assessment

The only real pending change was the VPC tag — a metadata-only update with no effect on networking, security, or availability, so risk was low. Separately, the first drift report showed a `FAIL`, but on inspection this was a false positive in `check_open_ingress`: the check scanned every resource in the plan's JSON regardless of whether it was actually changing, so it flagged the public ALB's pre-existing, intentionally public listener ports (HTTP/HTTPS from `0.0.0.0/0`) even though nothing about that resource was in this plan's diff. I fixed the script to skip resources with `change.actions == ["no-op"]` before checking for open ingress, so it now only flags genuinely new or changed exposure, not long-standing allowed rules. Both `/tf-drift-review` and the fixed script agreed the actual change (the tag) carried no security or destructive risk.

## 4. Human-Approved Action

After reviewing the Terraform plan and Claude's analysis, I ran `terraform apply "tfplan.out"` manually in my own terminal — applying the exact plan that had already been reviewed, rather than re-planning at apply time. This was a deliberate human decision and action; at no point did Claude or any script run `apply` or `destroy` automatically. `Apply complete! Resources: 0 added, 1 changed, 0 destroyed` confirmed only the intended change was made.

## 5. Verification

After applying, I ran `/tf-drift-review` again. It reported `Overall status: HEALTHY` with `3 PASS, 0 WARN, 0 FAIL`, and confirmed `terraform plan`'s detailed exit code was `0` — no pending changes, meaning the real AWS infrastructure now matches the Terraform configuration exactly. I saved this as `reports/resolved-report.txt` and confirmed both it and the earlier `drift-detected-report.txt` exist side by side in `reports/`.

## 6. Safety Decision

Claude was allowed to gather evidence (reading plan output, running `tf-drift-check.sh`, inspecting the JSON) and analyze it (classifying risk, explaining findings) because that work benefits from being thorough and fast, and getting it wrong only costs a re-run. It was never allowed to execute `terraform apply` or `destroy` because those actions are difficult or impossible to reverse and have real cost and availability consequences — a mistaken or persuaded automated action there is far more expensive than a mistaken analysis. This is enforced two ways in this project: as an explicit rule in `CLAUDE.md` that Claude follows through judgment, and as a structural, deterministic `PreToolUse` hook in `.claude/settings.json` that blocks any `apply`/`destroy` attempt whenever the latest drift report shows `FAIL` — regardless of how the request is phrased or justified in conversation. I confirmed this hook actually works by testing it directly and by watching Claude Code itself decline to run `apply` even when asked to "just demonstrate" the block.

## 7. Agentic Loop Mapping

- **Gather:** `tf-drift-check.sh` ran `terraform plan -detailed-exitcode` and `terraform show -json` to collect raw evidence about the pending change.
- **Analyze:** The script classified that evidence into PASS/WARN/FAIL checks, and `/tf-drift-review` added a plain-language risk assessment on top, explaining what was safe and identifying the open-ingress check's false positive.
- **Human Act:** I reviewed the plan and the analysis myself, decided the tag change was safe and intentional, and ran `terraform apply "tfplan.out"` manually — the one step no AI component was permitted to perform.
- **Verify:** I re-ran `/tf-drift-review` after applying to confirm the environment returned to `HEALTHY`, with Terraform's own plan output as the independent proof that reality now matches configuration.
