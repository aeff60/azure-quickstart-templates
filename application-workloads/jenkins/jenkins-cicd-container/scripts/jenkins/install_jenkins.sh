#!/usr/bin/env bash
# =============================================================================
# install_jenkins.sh
# Jenkins LTS Installation Script for Ubuntu 22.04 / 24.04
# Last updated: 2025
#
# Changes from legacy script:
#   - Java 21 (ใช้ OpenJDK 21 แทน OpenJDK 8 ที่ EOL แล้ว)
#   - GPG keyring ใหม่ (/etc/apt/keyrings/) แทน apt-key ที่ deprecated
#   - Jenkins key URL อัพเดตเป็น jenkins.io-2026.key
#   - ลบ azure-cli / aks ออกจาก core script (ย้ายเป็น optional)
#   - set -euo pipefail เพื่อ fail-fast
#   - ไม่ curl | sudo bash โดยตรง (security risk)
#   - nginx ใช้ modern config + TLS-ready structure
#   - ไม่ expose initialAdminPassword ผ่าน anonymous read
#   - FIX: รอ apt lock ก่อน (แก้ปัญหา cloud-init ล็อค apt ตอน VM boot)
#   - FIX: retry apt-get update (แก้ปัญหา Unable to locate package)
# =============================================================================

set -euo pipefail

# ─── Colour helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

# ─── Usage ───────────────────────────────────────────────────────────────────
print_usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Installs Jenkins LTS on Ubuntu 22.04/24.04 with nginx reverse proxy.

Required:
  --fqdn,     -f  <hostname>   Public FQDN for Jenkins (e.g. jenkins.example.com)

Optional:
  --private-ip, -p <ip>        Private IP for Jenkins URL (uses FQDN if omitted)
  --release,    -r <type>      Jenkins release type: lts (default) | weekly
  --with-nginx                 Install and configure nginx reverse proxy (default: true)
  --skip-nginx                 Skip nginx installation
  --admin-user  <name>         Initial admin username (default: admin)
  --java-version <ver>         Java version to install: 21 (default) | 17
  --help,       -h             Show this help
EOF
}

# ─── Defaults ────────────────────────────────────────────────────────────────
JENKINS_FQDN=""
JENKINS_PRIVATE_IP=""
RELEASE_TYPE="lts"
INSTALL_NGINX=true
ADMIN_USER="admin"
JAVA_VERSION="21"

# ─── Argument parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fqdn|-f)         JENKINS_FQDN="$2";       shift 2 ;;
    --private-ip|-p)   JENKINS_PRIVATE_IP="$2"; shift 2 ;;
    --release|-r)      RELEASE_TYPE="$2";       shift 2 ;;
    --with-nginx)      INSTALL_NGINX=true;       shift   ;;
    --skip-nginx)      INSTALL_NGINX=false;      shift   ;;
    --admin-user)      ADMIN_USER="$2";          shift 2 ;;
    --java-version)    JAVA_VERSION="$2";        shift 2 ;;
    --help|-h)         print_usage; exit 0       ;;
    *) die "Unknown argument: $1. Use --help for usage." ;;
  esac
done

# ─── Validation ──────────────────────────────────────────────────────────────
[[ -z "$JENKINS_FQDN" ]] && die "--fqdn is required."

if [[ "$RELEASE_TYPE" != "lts" && "$RELEASE_TYPE" != "weekly" ]]; then
  die "--release must be 'lts' or 'weekly'. Got: '$RELEASE_TYPE'"
fi

if [[ "$JAVA_VERSION" != "17" && "$JAVA_VERSION" != "21" ]]; then
  die "--java-version must be '17' or '21'. Got: '$JAVA_VERSION'"
fi

# Determine Jenkins URL
if [[ -n "$JENKINS_PRIVATE_IP" ]]; then
  JENKINS_URL="http://${JENKINS_PRIVATE_IP}:8080/"
else
  JENKINS_URL="http://${JENKINS_FQDN}/"
fi

# ─── Helpers ─────────────────────────────────────────────────────────────────
require_root() {
  [[ $EUID -eq 0 ]] || die "This script must be run as root (sudo)."
}

retry() {
  local -r max=10
  local count=0
  until "$@"; do
    ((count++))
    [[ $count -ge $max ]] && die "Command failed after $max attempts: $*"
    warn "Attempt $count/$max failed, retrying in 5 s…"
    sleep 5
  done
}

wait_for_jenkins() {
  info "Waiting for Jenkins to become reachable…"
  local url="http://localhost:8080/login"
  retry curl --silent --fail --output /dev/null "$url"
  info "Jenkins is up."
}

# ─── FIX: รอ apt lock ──────────────────────────────────────────────────────
# cloud-init ล็อค apt ระหว่าง VM boot ทำให้ apt-get update ล้มเหลว
# และทำให้ package อย่าง fontconfig หา repository ไม่เจอ
wait_for_apt_lock() {
  info "Waiting for apt locks to be released…"
  local locks=(
    /var/lib/dpkg/lock-frontend
    /var/lib/dpkg/lock
    /var/cache/apt/archives/lock
    /var/lib/apt/lists/lock
  )
  local waited=0
  local max_wait=300  # รอสูงสุด 5 นาที

  while true; do
    local locked=false
    for lock in "${locks[@]}"; do
      if fuser "$lock" >/dev/null 2>&1; then
        locked=true
        break
      fi
    done

    if ! $locked; then
      info "apt locks released."
      break
    fi

    if [[ $waited -ge $max_wait ]]; then
      warn "Timed out waiting for apt lock after ${max_wait}s. Proceeding anyway…"
      break
    fi

    warn "apt is locked (cloud-init still running), waiting 10 s… (${waited}s/${max_wait}s)"
    sleep 10
    ((waited += 10))
  done
}

# ─── Main installation ───────────────────────────────────────────────────────
require_root

# ── 0. รอ cloud-init ปล่อย apt lock ก่อน ─────────────────────────────────────
wait_for_apt_lock

# ── 1. System update ─────────────────────────────────────────────────────────
info "Updating system packages…"
# FIX: retry apt-get update เผื่อ mirror ตอบช้า
retry apt-get update
# FIX: แยก fontconfig ออก เพราะเป็น universe package ที่ index บางครั้งยัง sync
# ไม่เสร็จทันทีหลัง apt-get update → ต้องใช้ retry ป้องกัน "Unable to locate package"
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg lsb-release apt-transport-https
retry apt-get install -y --no-install-recommends fontconfig

# ── 2. Java ──────────────────────────────────────────────────────────────────
info "Installing OpenJDK ${JAVA_VERSION}…"
apt-get install -y --no-install-recommends "openjdk-${JAVA_VERSION}-jre"
java -version

# ── 3. Jenkins repository (modern GPG keyring) ───────────────────────────────
info "Adding Jenkins ${RELEASE_TYPE} repository…"
mkdir -p /etc/apt/keyrings

if [[ "$RELEASE_TYPE" == "lts" ]]; then
  JENKINS_REPO_URL="https://pkg.jenkins.io/debian-stable"
  JENKINS_KEY_URL="https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key"
else
  JENKINS_REPO_URL="https://pkg.jenkins.io/debian"
  JENKINS_KEY_URL="https://pkg.jenkins.io/debian/jenkins.io-2026.key"
fi

retry curl -fsSL "${JENKINS_KEY_URL}" \
  | tee /etc/apt/keyrings/jenkins-keyring.asc > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] ${JENKINS_REPO_URL} binary/" \
  | tee /etc/apt/sources.list.d/jenkins.list > /dev/null

retry apt-get update

# ── 4. Install Jenkins ───────────────────────────────────────────────────────
info "Installing Jenkins…"
apt-get install -y jenkins

# ── 5. Harden Jenkins config ─────────────────────────────────────────────────
info "Configuring Jenkins location…"
JENKINS_CONFIG_DIR="/var/lib/jenkins"

# Jenkins URL config
cat > "${JENKINS_CONFIG_DIR}/jenkins.model.JenkinsLocationConfiguration.xml" <<EOF
<?xml version='1.1' encoding='UTF-8'?>
<jenkins.model.JenkinsLocationConfiguration>
  <adminAddress>address not configured &lt;nobody@nowhere&gt;</adminAddress>
  <jenkinsUrl>${JENKINS_URL}</jenkinsUrl>
</jenkins.model.JenkinsLocationConfiguration>
EOF

# Disable the reverse-proxy setup monitor (we handle it via nginx)
JENKINS_MAIN_CONFIG="${JENKINS_CONFIG_DIR}/config.xml"
if [[ -f "$JENKINS_MAIN_CONFIG" ]]; then
  if $INSTALL_NGINX; then
    sed -i 's|<disabledAdministrativeMonitors/>|<disabledAdministrativeMonitors><string>hudson.diagnosis.ReverseProxySetupMonitor</string></disabledAdministrativeMonitors>|' \
      "$JENKINS_MAIN_CONFIG" 2>/dev/null || true
  fi

  sed -i 's|<slaveAgentPort>.*</slaveAgentPort>|<slaveAgentPort>50000</slaveAgentPort>|' \
    "$JENKINS_MAIN_CONFIG" 2>/dev/null || true
fi

# ── 6. Enable and start Jenkins ──────────────────────────────────────────────
info "Enabling and starting Jenkins service…"
systemctl enable jenkins
systemctl restart jenkins
wait_for_jenkins

# ── 7. nginx reverse proxy ───────────────────────────────────────────────────
if $INSTALL_NGINX; then
  info "Installing nginx…"
  apt-get install -y nginx

  info "Writing nginx config for ${JENKINS_FQDN}…"
  cat > /etc/nginx/sites-available/jenkins <<NGINX
# Jenkins reverse proxy – generated by install_jenkins.sh
# To add TLS: use certbot (sudo certbot --nginx -d ${JENKINS_FQDN})
upstream jenkins_backend {
  keepalive 32;
  server 127.0.0.1:8080;
}

server {
  listen 80;
  server_name ${JENKINS_FQDN};

  # Redirect /cli to home (prevent unauthenticated CLI access)
  location = /cli {
    return 301 /;
  }

  # Proxy to Jenkins
  location / {
    proxy_pass         http://jenkins_backend;
    proxy_redirect     http://jenkins_backend http://${JENKINS_FQDN};

    proxy_set_header   Host              \$host;
    proxy_set_header   X-Real-IP         \$remote_addr;
    proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
    proxy_set_header   X-Forwarded-Proto \$scheme;

    # WebSocket support (required for Blue Ocean, Pipeline logs)
    proxy_http_version 1.1;
    proxy_set_header   Upgrade           \$http_upgrade;
    proxy_set_header   Connection        "upgrade";

    proxy_read_timeout  90s;
    proxy_send_timeout  90s;
    proxy_connect_timeout 10s;
  }
}
NGINX

  sed -i 's|# server_tokens off;|server_tokens off;|' /etc/nginx/nginx.conf

  ln -sf /etc/nginx/sites-available/jenkins /etc/nginx/sites-enabled/jenkins
  rm -f /etc/nginx/sites-enabled/default

  nginx -t && systemctl restart nginx
  info "nginx configured and restarted."
fi

# ── 8. Summary ───────────────────────────────────────────────────────────────
ADMIN_PASSWORD_FILE="/var/lib/jenkins/secrets/initialAdminPassword"

echo
echo "============================================================"
echo "  Jenkins installation complete"
echo "============================================================"
echo "  URL           : ${JENKINS_URL}"
if [[ -f "$ADMIN_PASSWORD_FILE" ]]; then
  echo "  Admin password: $(cat $ADMIN_PASSWORD_FILE)"
fi
echo
echo "  Next steps:"
echo "  1. Open ${JENKINS_URL} in your browser"
echo "  2. Complete the setup wizard"
echo "  3. Add TLS (recommended):"
echo "     sudo apt install certbot python3-certbot-nginx"
echo "     sudo certbot --nginx -d ${JENKINS_FQDN}"
echo "============================================================"
