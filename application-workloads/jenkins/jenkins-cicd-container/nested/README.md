# nested/ — ARM Nested Templates

โฟลเดอร์นี้เก็บ ARM template ย่อยที่ถูกเรียกจาก `azuredeploy.json` หลัก แต่ละไฟล์สร้าง VM พร้อม network resources และ custom script สำหรับ component หนึ่งของระบบ

---

## jenkins.json

**หน้าที่:** สร้าง Jenkins VM พร้อม network และรัน setup script อัตโนมัติ

### Resource ที่สร้าง

| Resource | รายละเอียด |
|---|---|
| `Microsoft.Network/publicIPAddresses` | Public IP แบบ Static/Standard สำหรับ Jenkins (DNS FQDN) |
| `Microsoft.Network/networkSecurityGroups` | NSG เปิด port 22 (SSH) และ 80 (HTTP) |
| `Microsoft.Network/networkInterfaces` | NIC เชื่อมต่อ VM กับ VNet และ Public IP |
| `Microsoft.Compute/virtualMachines` | Ubuntu 22.04 LTS (22_04-lts-gen2) |
| `CustomScript Extension` | รัน `jenkins-acr-aks.sh` หลัง VM สร้างเสร็จ |

### ขั้นตอนที่ทำงาน

1. ARM สร้าง VM บน Ubuntu 22.04
2. Custom Script Extension ดาวน์โหลด scripts ทั้งหมดจาก `fileUris`
3. รัน `jenkins-acr-aks.sh` พร้อมส่ง credentials (ACR, AKS, CosmosDB) เป็น arguments

### Parameters ที่รับมาจาก azuredeploy.json

```
jenkinsVmName, adminUsername, adminPassword, sshPublicKey,
jenkinsVmSize, subnetRef, artifacts_location,
servicePrincipalClientId, servicePrincipalClientSecret,
cosmosDbName, azureContainerRegistry, aksClusterName,
resourceGroupName, gitRepository
```

---

## grafana.json

**หน้าที่:** สร้าง Grafana VM พร้อม network และรัน install + configure script

### Resource ที่สร้าง

| Resource | รายละเอียด |
|---|---|
| `Microsoft.Network/publicIPAddresses` | Public IP สำหรับ Grafana (DNS FQDN) |
| `Microsoft.Network/networkSecurityGroups` | NSG เปิด port 22 (SSH) และ 3000 (Grafana) |
| `Microsoft.Network/networkInterfaces` | NIC เชื่อมต่อ VM กับ VNet |
| `Microsoft.Compute/virtualMachines` | Ubuntu 22.04 LTS (22_04-lts-gen2) |
| `CustomScript Extension` | รัน `install-grafana.sh` และ `configure-grafana.sh` |

### ขั้นตอนที่ทำงาน

1. สร้าง VM บน Ubuntu 22.04
2. รัน `install-grafana.sh` — ติดตั้ง Grafana Enterprise จาก apt repository
3. รัน `configure-grafana.sh` — เชื่อม Grafana กับ Azure Monitor, CosmosDB, AKS

### Parameters ที่รับมาจาก azuredeploy.json

```
grafanaVmName, adminUsername, adminPassword, sshPublicKey,
grafanaVmSize, subnetRef, artifacts_location,
servicePrincipalClientId, servicePrincipalClientSecret,
subscriptionId, tenantId, cosmosDbName, aksClusterName,
resourceGroupName
```
