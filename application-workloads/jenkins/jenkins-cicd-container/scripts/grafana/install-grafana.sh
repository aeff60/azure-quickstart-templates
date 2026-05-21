#!/bin/bash

# Command Line Opts
GRAFANA_VERSION=""
GRAFANA_PORT="3000"


# Utility Log Command
log()
{
    echo "`date -u +'%Y-%m-%d %H:%M:%S'`: ${1}"
}

help()
{
    echo "This script installs Grafana cluster on Ubuntu"
    echo "Parameters:"
    echo "-A admin password"
    echo "-V version of grafana to use. Default:${GRAFANA_VERSION}"
    echo "-p port to host grafana-server"
    echo "-h view this help content"
}

# Parameters
ADMIN_PWD="admin"

#Loop through options passed
while getopts :A:V::h optname; do
  log "Option $optname set"
  case $optname in
    A)
      ADMIN_PWD="${OPTARG}"
      ;;
    V) #input desired grafana version
        GRAFANA_VERSION="${OPTARG}"
        ;;
    p) #port number for local grafana server
        GRAFANA_PORT="${OPTARG}"
        ;;
    h) #show help
      help
      exit 2
      ;;
    \?) #unrecognized option - show help
      echo -e \\n"Option -${BOLD}$OPTARG${NORM} not allowed."
      help
      exit 2
      ;;
  esac
done

# Install Grafana
install_grafana()
{
    log "Installing Grafana Enterprise via apt repository"
    # FIX: Use official Grafana apt repository instead of direct deb download.
    # This lets apt resolve libfontconfig1 and all other dependencies automatically.
    # Ubuntu 16.04 (xenial) was EOL; VM image updated to Ubuntu 22.04 (jammy).
    apt-get update -y
    apt-get install -y --no-install-recommends apt-transport-https software-properties-common wget gpg

    mkdir -p /usr/share/keyrings
    wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
    echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" \
        | tee /etc/apt/sources.list.d/grafana.list

    apt-get update -y
    if [[ -n "${GRAFANA_VERSION}" ]]; then
        apt-get install -y "grafana-enterprise=${GRAFANA_VERSION}"
    else
        apt-get install -y grafana-enterprise
    fi
    systemctl daemon-reload
}

start_grafana()
{
    log "Staring the grafana-server"
    systemctl start grafana-server
    sudo systemctl enable grafana-server.service
}

# Install the Azure Monitor Datasource
install_azure_monitor_plugin()
{
    log "Install grafana-azure-monitor-datasource"
    grafana-cli plugins install grafana-azure-monitor-datasource
    systemctl restart grafana-server
}

# Update the grafana passord of the admin account
configure_admin_password()
{
    sed -i "s/;admin_password = admin/admin_password = ${ADMIN_PWD}/" /etc/grafana/grafana.ini
}

install_grafana
configure_admin_password
start_grafana