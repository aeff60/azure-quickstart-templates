# scripts/grafana/ — Grafana Setup Scripts

โฟลเดอร์นี้เก็บ scripts และ dashboard definitions สำหรับติดตั้งและ configure Grafana บน VM ที่สร้างโดย `nested/grafana.json`

---

## install-grafana.sh

**หน้าที่:** ติดตั้ง Grafana Enterprise บน Ubuntu 22.04 ผ่าน official apt repository

### Arguments

| Flag | ความหมาย |
|---|---|
| `-A` | Admin password สำหรับ Grafana |
| `-V` | Version ของ Grafana ที่ต้องการ (optional) |
| `-p` | Port ที่จะให้ Grafana ฟัง (default: 3000) |

### ขั้นตอนที่ทำงาน

1. เพิ่ม Grafana GPG key และ apt repository (`packages.grafana.com`)
2. `apt-get install grafana-enterprise`
3. เปิดใช้งาน Grafana service ผ่าน systemd (`systemctl enable --now grafana-server`)

> **หมายเหตุ:** ใช้ apt repository แทนการดาวน์โหลด .deb โดยตรง เพื่อให้ apt จัดการ dependency `libfontconfig1` ได้อัตโนมัติ

---

## configure-grafana.sh

**หน้าที่:** เชื่อม Grafana กับ Azure Monitor, CosmosDB, AKS และ import dashboard

### Arguments

| Flag | ความหมาย |
|---|---|
| `-A` | Grafana admin password |
| `-S` | Azure Subscription ID |
| `-T` | Azure Tenant ID |
| `-i` | Service Principal Client ID |
| `-s` | Service Principal Client Secret |
| `-r` | Resource Group name |
| `-c` | CosmosDB account name |
| `-k` | AKS cluster name |
| `-l` | Artifacts location URL |
| `-t` | Artifacts location SAS token |

### ขั้นตอนที่ทำงาน

1. ติดตั้ง Azure CLI (ผ่าน `https://aka.ms/InstallAzureCLIDeb`)
2. Login ด้วย Service Principal
3. ดึง subscription/resource info จาก Azure
4. เพิ่ม Azure Monitor datasource ใน Grafana ผ่าน Grafana API
5. Import dashboard จาก `dashboard.json`, `dashboard-db.json`, `dashboard-aks.json`

---

## dashboard.json

**หน้าที่:** โครงสร้างหลักของ Grafana dashboard ชื่อ **"Hello World Overview"**

- Theme: dark
- Time window: 30 นาที
- เป็น wrapper สำหรับ panels จาก `dashboard-db.json` และ `dashboard-aks.json`

---

## dashboard-db.json

**หน้าที่:** Panel สำหรับแสดง CosmosDB metrics

| ค่า | รายละเอียด |
|---|---|
| Datasource | Azure Monitor |
| Metric | `TotalRequests` |
| Dimensions | DatabaseAccount, DatabaseName, CollectionName, Region, StatusCode |
| Visualization | Line graph |

---

## dashboard-aks.json

**หน้าที่:** Panel สำหรับแสดง AKS CPU usage

| ค่า | รายละเอียด |
|---|---|
| Datasource | Azure Monitor |
| Metric | `Percentage CPU` |
| Visualization | Timeseries พร้อม threshold (เขียว / แดงที่ 80%) |

---

## dashboard-aks-target.json

**หน้าที่:** Azure Monitor query configuration สำหรับดึง CPU metrics จาก VM resource โดยมี placeholder สำหรับ resource group, VM name, subscription ID — ถูก inject ค่าจริงโดย `configure-grafana.sh`
