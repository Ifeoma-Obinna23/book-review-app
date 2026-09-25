#!/bin/bash
# Web-tier (Next.js) bootstrap script.
#
# Rendered by Terraform's templatefile() -- ${app_repo_url}, ${internal_alb_dns_name}
# and ${internal_alb_port} below are substituted at plan/apply time, not at
# instance boot time. Everything else is a literal bash script that runs once,
# on first boot, as root (via cloud-init user data).
#
# All stdout/stderr from this entire script is redirected to
# /var/log/user-data.log so a failed bootstrap can be diagnosed via SSM
# Session Manager without needing SSH.

exec > /var/log/user-data.log 2>&1
set -xeuo pipefail

dnf update -y
dnf install -y git

# Node.js 20.x -- AL2023's own package streams for Node are not guaranteed to
# track a specific major version over time, so the NodeSource setup script is
# used instead to pin Node 20 explicitly and reproducibly.
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
dnf install -y nodejs

if [ -d /opt/book-review-app/.git ]; then
  git -C /opt/book-review-app pull
else
  git clone "${app_repo_url}" /opt/book-review-app
fi
cd /opt/book-review-app/frontend

# Proxies browser/server-side calls to /api/* through to the internal ALB,
# which fronts the app tier on ${internal_alb_port}. The internal ALB's DNS
# name only resolves/routes inside the VPC, so this is unreachable from the
# public internet even though it is baked into the web tier's own config.
cat > next.config.js <<EOF
/** @type {import('next').NextConfig} */
const nextConfig = {
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: 'http://${internal_alb_dns_name}:${internal_alb_port}/api/:path*',
      },
    ]
  },
}

module.exports = nextConfig
EOF

npm install
npm run build

npm install -g pm2

pm2 describe book-review-web > /dev/null 2>&1 && pm2 restart book-review-web || pm2 start npm --name book-review-web -- start -- -p 3000

# Running user data as root, so pm2 self-configures the systemd unit for the
# root user without needing an interactive sudo copy/paste step.
pm2 startup systemd -u root --hp /root
pm2 save
