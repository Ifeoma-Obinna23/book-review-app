#!/bin/bash
# App-tier (Node.js/Express) bootstrap script.
#
# Rendered by Terraform's templatefile() -- only ${app_repo_url},
# ${db_secret_name}, ${app_allowed_origins} and ${aws_region} below are
# substituted at plan/apply time. Everything else is a literal bash script
# that runs once, on first boot, as root (via cloud-init user data).
#
# All stdout/stderr from this entire script is redirected to
# /var/log/user-data.log so a failed bootstrap can be diagnosed via SSM
# Session Manager -- there is no SSH path into this tier at all.

exec > >(tee -a /var/log/user-data.log > /dev/console) 2>&1
set -xeuo pipefail

dnf update -y
dnf install -y git jq

# Node.js 20.x -- see the web-tier script for why NodeSource is used instead
# of an AL2023 dnf module.
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
dnf install -y nodejs

if [ -d /opt/book-review-app/.git ]; then
  git -C /opt/book-review-app pull
else
  git clone "${app_repo_url}" /opt/book-review-app
fi
cd /opt/book-review-app/backend

# Fetch the app tier's DB credentials and JWT secret from Secrets Manager at
# boot time. No cloud credential or DB password is ever written into this
# template per CLAUDE.md section 4 -- the real values live only in Secrets
# Manager and are read at runtime by the IAM role already attached to this
# instance (scoped secretsmanager:GetSecretValue, see
# var.secrets_manager_arn_pattern).
#
# The secret named "${db_secret_name}" does NOT exist yet -- the database
# module is still a scaffold (CLAUDE.md Build Status table) -- so this call
# is expected to fail today. It is guarded with `if ! ...; then` so a failure
# does not trip `set -e` and abort the rest of boot; a warning is logged and
# DB_SECRET_JSON falls back to an empty JSON object, which makes every jq
# lookup below fall back independently to its own REPLACE_ME_* placeholder.
if ! DB_SECRET_JSON=$(aws secretsmanager get-secret-value --region "${aws_region}" --secret-id "${db_secret_name}" --query SecretString --output text 2>>/var/log/user-data.log); then
  echo "WARNING: failed to fetch secret ${db_secret_name} from Secrets Manager -- falling back to placeholder DB/JWT values" >>/var/log/user-data.log
  DB_SECRET_JSON='{}'
fi

DB_HOST=$(jq -r '.DB_HOST // "REPLACE_ME_DB_HOST"' <<<"$DB_SECRET_JSON")
DB_NAME=$(jq -r '.DB_NAME // "REPLACE_ME_DB_NAME"' <<<"$DB_SECRET_JSON")
DB_USER=$(jq -r '.DB_USER // "REPLACE_ME_DB_USER"' <<<"$DB_SECRET_JSON")
DB_PASS=$(jq -r '.DB_PASS // "REPLACE_ME_DB_PASS"' <<<"$DB_SECRET_JSON")
JWT_SECRET=$(jq -r '.JWT_SECRET // "REPLACE_ME_JWT_SECRET"' <<<"$DB_SECRET_JSON")

# Environment file. Deliberately an UNQUOTED heredoc (<<EOF, not <<'EOF') so
# the shell variables populated above are interpolated into the file; PORT
# and DB_DIALECT stay as literals since they aren't secrets and aren't part
# of the Secrets Manager JSON.
cat >.env <<EOF
PORT=3001
DB_HOST=$DB_HOST
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
DB_DIALECT=mysql
JWT_SECRET=$JWT_SECRET
ALLOWED_ORIGINS=${app_allowed_origins}
EOF

npm install

npm install -g pm2

pm2 describe book-review-app > /dev/null 2>&1 && pm2 restart book-review-app || pm2 start src/server.js --name book-review-app

# Running user data as root, so pm2 self-configures the systemd unit for the
# root user without needing an interactive sudo copy/paste step.
pm2 startup systemd -u root --hp /root
pm2 save
