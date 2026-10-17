---
name: tf-drift-review
description: Run the read-only Terraform drift-and-policy check, analyze the evidence for destructive changes and unsafe ingress rules, and recommend whether terraform apply appears safe. Never runs terraform apply or destroy.
allowed-tools: Bash, Read, Grep
disable-model-invocation: true
---

# Terraform Drift Review Skill

When `/tf-drift-review` is invoked:

1. Read `CLAUDE.md` before doing anything else.

2. Run:

   `bash "AI Assignment/tf-drift-check.sh" || true`

   from the project root.

3. Read:

   `reports/tf-drift-report.txt`

4. If:

   `reports/tfplan.json`

   exists, inspect it for additional evidence about flagged resource changes.

5. Report:

   - Overall status: HEALTHY, WARN, or FAIL
   - Terraform plan detailed exit code and its meaning
   - Every WARN or FAIL result
   - Any resource deletion or replacement
   - Any ingress/security change that exposes `0.0.0.0/0` or `*`
   - A plain-language risk assessment
   - Whether `terraform apply` appears safe based on the evidence
   - One recommended next step for the human operator

6. If Terraform reports no changes, state clearly that no infrastructure action is required.

7. Do not edit any `.tf` file.

8. Never run:
   - `terraform apply`
   - `terraform destroy`
   - Any command using `-auto-approve`

9. Do not generate a separate Terraform plan outside `tf-drift-check.sh`. The generated report and JSON are the evidence source for this review.

10. The human operator must review and execute any approved infrastructure-changing command manually.
