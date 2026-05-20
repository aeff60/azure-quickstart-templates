#!/bin/bash
echo $@
function print_usage() {
  cat <<USAGE
Installs Jenkins and exposes it to the public through port 80
USAGE
}

function throw_if_empty() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "Parameter '$name' cannot be empty." 1>&2
    print_usage
    exit -1
  fi
}

function run_util_script() {
  local script_path="$1"
  shift
  curl --silent "${artifacts_location}${script_path}${artifacts_location_sas_token}" | sudo bash -s -- "$@"
  local return_value=$?
  if [ $return_value -ne 0 ]; then
    >&2 echo "Failed while executing script '$script_path'."
    exit $return_value
  fi
}

function retry_until_successful {
  counter=0
  "${@}"
  while [ $? -ne 0 ]; do
    if [[ "$counter" -gt 20 ]]; then
        exit 1
    else
        let counter++
    fi
    sleep 5
    "${@}"
  done;
}

#defaults
jenkins_version_location="${artifacts_location}scripts/jenkins/jenkins-verified-ver${artifacts_location_sas_token}"
azure_web_page_location="/usr/share/nginx/azure"
jenkins_release_type="LTS"

while [[ $# > 0 ]]
do
  key="$1"
  shift
  case $key in
    --jenkins_fqdn|-jf) jenkins_fqdn="$1"; shift ;;
    --cluster_name|-cn) cluster_name="$1"; shift ;;
    --cluster_version|-cv) cluster_version="$1"; shift ;;
    --vm_private_ip|-pi) vm_private_ip="$1"; shift ;;
    --jenkins_release_type|-jrt) jenkins_release_type="$1"; shift ;;
    --jenkins_version_location|-jvl) jenkins_version_location="$1"; shift ;;
    --service_principal_type|-sp) service_principal_type="$1"; shift ;;
    --service_principal_id|-spid) service_principal_id="$1"; shift ;;
    --service_principal_secret|-ss) service_principal_secret="$1"; shift ;;
    --subscription_id|-subid) subscription_id="$1"; shift ;;
    --tenant_id|-tid) tenant_id="$1"; shift ;;
    --artifacts_location|-al) artifacts_location="$1"; shift ;;
    --sas_token|-st) artifacts_location_sas_token="$1"; shift ;;
    --cloud_agents|-ca) cloud_agents="$1"; shift ;;
    --resource_group|-rg) resource_group="$1"; shift ;;
    --location|-lo) location="$1"; shift ;;
    --help|-help|-h) print_usage; exit 13 ;;
    *) echo "ERROR: Unknown argument '$key'" 1>&2; exit -1 ;;
  esac
done

throw_if_empty --jenkins_fqdn $jenkins_fqdn

if [ -z "$vm_private_ip" ]; then
    jenkins_url="http://${jenkins_fqdn}/"
else
    jenkins_url="http://${vm_private_ip}:8080/"
fi

jenkins_auth_matrix_conf=$(cat <<XMLEOF
<authorizationStrategy class="hudson.security.ProjectMatrixAuthorizationStrategy">
    <permission>hudson.model.Hudson.Administer:authenticated</permission>
    <permission>hudson.model.Hudson.Read:authenticated</permission>
    <permission>hudson.model.Hudson.Read:anonymous</permission>
    <permission>hudson.model.Item.Discover:anonymous</permission>
    <permission>hudson.model.Item.Read:anonymous</permission>
</authorizationStrategy>
XMLEOF
)

jenkins_location_conf=$(cat <<XMLEOF
<?xml version='1.0' encoding='UTF-8'?>
<jenkins.model.JenkinsLocationConfiguration>
    <adminAddress>address not configured yet &lt;nobody@nowhere&gt;</adminAddress>
    <jenkinsUrl>${jenkins_url}</jenkinsUrl>
</jenkins.model.JenkinsLocationConfiguration>
XMLEOF
)

jenkins_disable_reverse_proxy_warning=$(cat <<XMLEOF
<disabledAdministrativeMonitors>
    <string>hudson.diagnosis.ReverseProxySetupMonitor</string>
</disabledAdministrativeMonitors>
XMLEOF
)

jenkins_agent_port="<slaveAgentPort>5378</slaveAgentPort>"

nginx_reverse_proxy_conf=$(cat <<NGINXEOF
server {
    listen 80;
    server_name ${jenkins_fqdn};
    error_page 403 /jenkins-on-azure;
    location / {
        proxy_set_header        Host \$host:\$server_port;
        proxy_set_header        X-Real-IP \$remote_addr;
        proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto \$scheme;
        proxy_pass          http://localhost:8080;
        proxy_redirect      http://localhost:8080 http://${jenkins_fqdn};
        proxy_read_timeout  90;
    }
    location /cli { rewrite ^ /jenkins-on-azure permanent; }
    location ~ /login* { rewrite ^ /jenkins-on-azure permanent; }
    location /jenkins-on-azure { alias ${azure_web_page_location}; }
}
NGINXEOF
)

# ============================================================
# STEP 1: Update apt and install prerequisites FIRST
# ============================================================
sudo apt-get update --yes
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  curl wget gnupg apt-transport-https ca-certificates \
  lsb-release software-properties-common

# ============================================================
# STEP 2: Setup Jenkins repository with new GPG key (2023)
# ============================================================
sudo rm -f /etc/apt/sources.list.d/jenkins.list
sudo curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
  -o /usr/share/keyrings/jenkins-keyring.asc

if [ "$jenkins_release_type" == "weekly" ]; then
  echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian binary/" \
    | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
else
  echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
    | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
fi

# ============================================================
# STEP 3: Setup Azure CLI repository (new method, no apt-key)
# ============================================================
sudo mkdir -p /etc/apt/keyrings
curl -sL https://packages.microsoft.com/keys/microsoft.asc | \
  sudo gpg --dearmor --yes -o /etc/apt/keyrings/microsoft.gpg

AZ_DIST=$(lsb_release -cs)
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ ${AZ_DIST} main" \
  | sudo tee /etc/apt/sources.list.d/azure-cli.list > /dev/null

# ============================================================
# STEP 4: Update apt again with all new repos
# ============================================================
sudo apt-get update --yes

# ============================================================
# STEP 5: Install Java 17 (required by modern Jenkins LTS)
# Try Java 17 first, fall back to Java 11
# ============================================================
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-17-jdk-headless 2>/dev/null || \
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk-headless

# ============================================================
# STEP 6: Install Jenkins
# ============================================================
if [[ ${jenkins_release_type} == 'verified' ]]; then
  jenkins_version=$(curl --silent "${jenkins_version_location}")
  deb_file=jenkins_${jenkins_version}_all.deb
  wget -q "https://pkg.jenkins.io/debian-stable/binary/${deb_file}"
  if [[ -f ${deb_file} ]]; then
    sudo dpkg -i ${deb_file}
    sudo apt-get install -f --yes
  else
    echo "Failed to download ${deb_file}."
    exit -1
  fi
else
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y jenkins
fi

retry_until_successful sudo test -f /var/lib/jenkins/secrets/initialAdminPassword
retry_until_successful run_util_script "scripts/jenkins/run-cli-command.sh" -c "version"

# ============================================================
# STEP 7: Install plugins
# ============================================================
plugins=(azure-vm-agents windows-azure-storage matrix-auth workflow-aggregator azure-app-service azure-acs azure-container-agents)
for plugin in "${plugins[@]}"; do
  run_util_script "scripts/jenkins/run-cli-command.sh" -c "install-plugin $plugin -deploy"
done

# ============================================================
# STEP 8: Configure Jenkins
# ============================================================
inter_jenkins_config=$(sed -zr -e"s|<authorizationStrategy.*</authorizationStrategy>|{auth-strategy-token}|" /var/lib/jenkins/config.xml)
final_jenkins_config=${inter_jenkins_config//'{auth-strategy-token}'/${jenkins_auth_matrix_conf}}
echo "${final_jenkins_config}" | sudo tee /var/lib/jenkins/config.xml > /dev/null

echo "${jenkins_location_conf}" | sudo tee /var/lib/jenkins/jenkins.model.JenkinsLocationConfiguration.xml > /dev/null

inter_jenkins_config=$(sed -zr -e"s|<disabledAdministrativeMonitors/>|{disable-reverse-proxy-token}|" /var/lib/jenkins/config.xml)
final_jenkins_config=${inter_jenkins_config//'{disable-reverse-proxy-token}'/${jenkins_disable_reverse_proxy_warning}}
echo "${final_jenkins_config}" | sudo tee /var/lib/jenkins/config.xml > /dev/null

inter_jenkins_config=$(sed -zr -e"s|<slaveAgentPort.*</slaveAgentPort>|{slave-agent-port}|" /var/lib/jenkins/config.xml)
final_jenkins_config=${inter_jenkins_config//'{slave-agent-port}'/${jenkins_agent_port}}
echo "${final_jenkins_config}" | sudo tee /var/lib/jenkins/config.xml > /dev/null

sudo service jenkins restart

# ============================================================
# STEP 9: Create Service Principal credential
# ============================================================
sp_cred=$(cat <<XMLEOF
<com.microsoft.azure.util.AzureCredentials>
  <scope>GLOBAL</scope>
  <id>azure_service_principal</id>
  <description>Manual Service Principal</description>
  <data>
    <subscriptionId>${subscription_id}</subscriptionId>
    <clientId>${service_principal_id}</clientId>
    <clientSecret>${service_principal_secret}</clientSecret>
    <oauth2TokenEndpoint>https://login.windows.net/${tenant_id}</oauth2TokenEndpoint>
    <serviceManagementURL>https://management.core.windows.net/</serviceManagementURL>
    <tenant>${tenant_id}</tenant>
    <authenticationEndpoint>https://login.microsoftonline.com/</authenticationEndpoint>
    <resourceManagerEndpoint>https://management.azure.com/</resourceManagerEndpoint>
    <graphEndpoint>https://graph.windows.net/</graphEndpoint>
  </data>
</com.microsoft.azure.util.AzureCredentials>
XMLEOF
)

retry_until_successful run_util_script "scripts/jenkins/run-cli-command.sh" -c "version"

echo "${sp_cred}" > sp_cred.xml
run_util_script "scripts/jenkins/run-cli-command.sh" -c "create-credentials-by-xml system::system::jenkins _" -cif sp_cred.xml
rm sp_cred.xml

# ============================================================
# STEP 10: Setup VM agents (FIX: removed typo 'conf=')
# ============================================================
vm_agent_conf=$(cat <<XMLEOF
<clouds>
  <com.microsoft.azure.vmagent.AzureVMCloud>
    <name>AzureVMAgents</name>
    <cloudName>AzureVMAgents</cloudName>
    <credentialsId>azure_service_principal</credentialsId>
    <maxVirtualMachinesLimit>10</maxVirtualMachinesLimit>
    <resourceGroupReferenceType>existing</resourceGroupReferenceType>
    <existingResourceGroupName>${resource_group}</existingResourceGroupName>
    <vmTemplates>
      <com.microsoft.azure.vmagent.AzureVMAgentTemplate>
        <templateName>linux-agent</templateName>
        <labels>linux</labels>
        <location>${location}</location>
        <virtualMachineSize>Standard_DS2_v2</virtualMachineSize>
        <storageAccountNameReferenceType>new</storageAccountNameReferenceType>
        <diskType>managed</diskType>
        <storageAccountType>Standard_LRS</storageAccountType>
        <noOfParallelJobs>1</noOfParallelJobs>
        <usageMode>NORMAL</usageMode>
        <shutdownOnIdle>false</shutdownOnIdle>
        <imageTopLevelType>basic</imageTopLevelType>
        <builtInImage>Ubuntu 20.04 LTS</builtInImage>
        <credentialsId>agent_admin_account</credentialsId>
        <retentionTimeInMin>60</retentionTimeInMin>
      </com.microsoft.azure.vmagent.AzureVMAgentTemplate>
    </vmTemplates>
    <deploymentTimeout>1200</deploymentTimeout>
    <approximateVirtualMachineCount>0</approximateVirtualMachineCount>
  </com.microsoft.azure.vmagent.AzureVMCloud>
</clouds>
XMLEOF
)

aci_agent_conf=$(cat <<XMLEOF
<clouds>
  <com.microsoft.jenkins.containeragents.aci.AciCloud>
    <name>AciAgents</name>
    <credentialsId>azure_service_principal</credentialsId>
    <resourceGroup>${resource_group}</resourceGroup>
    <templates>
      <com.microsoft.jenkins.containeragents.aci.AciContainerTemplate>
        <name>aciagents</name>
        <image>jenkinsci/jnlp-slave</image>
        <osType>Linux</osType>
        <command>jenkins-slave -url \${rootUrl} \${secret} \${nodeName}</command>
        <rootFs>/home/jenkins</rootFs>
        <timeout>10</timeout>
        <cpu>1</cpu>
        <memory>1.5</memory>
        <retentionStrategy class="com.microsoft.jenkins.containeragents.strategy.ContainerOnceRetentionStrategy" />
      </com.microsoft.jenkins.containeragents.aci.AciContainerTemplate>
    </templates>
  </com.microsoft.jenkins.containeragents.aci.AciCloud>
</clouds>
XMLEOF
)

agent_admin_password=$(head /dev/urandom | tr -dc A-Z | head -c 4)$(head /dev/urandom | tr -dc a-z | head -c 4)$(head /dev/urandom | tr -dc 0-9 | head -c 4)'!@'
agent_admin_cred=$(cat <<XMLEOF
<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>agent_admin_account</id>
  <description>the admin account for the vm agents</description>
  <username>agentadmin</username>
  <password>${agent_admin_password}</password>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
XMLEOF
)

if [ "${cloud_agents}" == 'vm' ]; then
  echo "${agent_admin_cred}" > agent_admin_cred.xml
  run_util_script "scripts/jenkins/run-cli-command.sh" -c "create-credentials-by-xml system::system::jenkins _" -cif agent_admin_cred.xml
  rm agent_admin_cred.xml
  inter_jenkins_config=$(sed -zr -e"s|<clouds/>|{clouds}|" /var/lib/jenkins/config.xml)
  final_jenkins_config=${inter_jenkins_config//'{clouds}'/${vm_agent_conf}}
  echo "${final_jenkins_config}" | sudo tee /var/lib/jenkins/config.xml > /dev/null
elif [ "${cloud_agents}" == 'aci' ]; then
  inter_jenkins_config=$(sed -zr -e"s|<clouds/>|{clouds}|" /var/lib/jenkins/config.xml)
  final_jenkins_config=${inter_jenkins_config//'{clouds}'/${aci_agent_conf}}
  echo "${final_jenkins_config}" | sudo tee /var/lib/jenkins/config.xml > /dev/null
fi

run_util_script "scripts/jenkins/run-cli-command.sh" -c "reload-configuration"

# ============================================================
# STEP 11: Install nginx
# ============================================================
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
echo "${nginx_reverse_proxy_conf}" | sudo tee /etc/nginx/sites-enabled/default > /dev/null
sudo sed -i "s|.*server_tokens.*|server_tokens off;|" /etc/nginx/nginx.conf

run_util_script "scripts/jenkins/jenkins-on-azure/install-web-page.sh" -u "${jenkins_fqdn}" -l "${azure_web_page_location}" -al "${artifacts_location}" -st "${artifacts_location_sas_token}"

sudo service nginx restart

# ============================================================
# STEP 12: Install common tools
# ============================================================
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git azure-cli xmlstarlet
sudo az aks install-cli --client-version ${cluster_version}
