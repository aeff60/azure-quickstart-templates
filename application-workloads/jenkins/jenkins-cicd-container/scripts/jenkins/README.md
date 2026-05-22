# scripts/jenkins/ — Jenkins Setup Scripts

โฟลเดอร์นี้เก็บ scripts ทั้งหมดที่ใช้ติดตั้งและ configure Jenkins บน VM รวมถึง templates สำหรับสร้าง pipeline job

> **การทำงานโดยรวม:** `nested/jenkins.json` ดาวน์โหลดไฟล์ทุกอย่างในโฟลเดอร์นี้ลงบน VM แล้วรัน `jenkins-acr-aks.sh` เป็น entry point หลัก

---

## jenkins-acr-aks.sh

**หน้าที่:** Entry point หลัก — orchestrate ทุกขั้นตอนการ setup Jenkins

### ขั้นตอนที่ทำงาน

1. รับ arguments (FQDN, credentials ต่างๆ)
2. เรียก `install_jenkins.sh` — ติดตั้ง Jenkins + Java + nginx
3. รอจนกว่า Jenkins จะ start สำเร็จ
4. เรียก `add-docker-build-job.sh` — สร้าง pipeline job ใน Jenkins
5. เรียก `configure-grafana.sh` บน Grafana VM (ผ่าน SSH)

### Arguments ที่รับ

```
$1 = jenkins_fqdn
$2 = artifacts_location
$3 = artifacts_location_sas_token
$4 = admin_user
$5 = admin_password
$6 = service_principal_id
$7 = service_principal_secret
$8 = subscription_id
$9 = tenant_id
$10 = resource_group
$11 = aks_name
$12 = acr_name
$13 = cosmos_db_name
$14 = git_repository
```

### `run_util_script` function

ฟังก์ชันภายในที่รันไฟล์ที่ดาวน์โหลดไว้ในเครื่องก่อน ถ้าไม่มีจึง curl จาก artifacts_location:

```bash
if [[ -f "$(basename $path)" ]]; then
  sudo bash "$(basename $path)" "$@"
else
  curl ... | sudo bash -s -- "$@"
fi
```

---

## install_jenkins.sh

**หน้าที่:** ติดตั้ง Jenkins LTS + Java 21 + nginx บน Ubuntu 22.04

### สิ่งที่ติดตั้ง

| Package | รายละเอียด |
|---|---|
| OpenJDK 21 | Java runtime สำหรับ Jenkins |
| Jenkins LTS | ติดตั้งจาก official Jenkins apt repository |
| fontconfig | จำเป็นสำหรับ Jenkins UI rendering |
| nginx | Reverse proxy ส่ง traffic port 80 → Jenkins port 8080 |

### retry() function

```bash
retry() {
  local count=0
  until "$@"; do
    (( ++count ))   # ใช้ pre-increment เพื่อป้องกัน set -e exit ตอน count=0
    [[ $count -ge 10 ]] && die "..."
    sleep 5
  done
}
```

> **หมายเหตุ:** ใช้ `((++count))` แทน `((count++))` เพราะภายใต้ `set -e` การ evaluate `((0))` จะ return exit code 1 ทำให้ script หยุดก่อนจะ retry ได้

---

## add-docker-build-job.sh

**หน้าที่:** สร้าง pipeline job ใน Jenkins ผ่าน Jenkins CLI

### Arguments

| Flag | ความหมาย |
|---|---|
| `-j` | Jenkins URL (ใช้ FQDN เพื่อ Origin header ตรงกัน) |
| `-g` | Git repository URL |
| `-r` | ACR registry URL |
| `-c` | AKS cluster name |
| `-n` | Resource group ของ AKS |
| `-m` | MongoDB connection string |

### ขั้นตอนที่ทำงาน

1. รอให้ Jenkins พร้อม (HTTP 200)
2. ดาวน์โหลด `jenkins-cli.jar` จาก Jenkins
3. ติดตั้ง plugins ที่จำเป็น (docker, kubernetes, git ฯลฯ)
4. อ่าน `basic-docker-build-job.xml` แล้วแทนที่ placeholder ด้วยค่าจริง
5. สร้าง job ด้วย `jenkins-cli.jar create-job`
6. เพิ่ม credentials ของ ACR ด้วย `basic-user-pwd-credentials.xml`

---

## run-cli-command.sh

**หน้าที่:** Wrapper สำหรับรัน Jenkins CLI command พร้อม retry

### การใช้งาน

```bash
run-cli-command.sh -j <jenkins_url> -u <user> -p <password> -c <command>
```

### จุดสำคัญ

ใช้ `-webSocket` flag เพื่อหลีกเลี่ยงปัญหา Origin header mismatch:

```bash
java -jar jenkins-cli.jar -s "${jenkins_url}" -webSocket -auth "${user}:${password}" $command
```

---

## basic-docker-build.groovy

**หน้าที่:** Jenkins Declarative Pipeline — ขั้นตอน build และ deploy จริง

```
Stage 1: Checkout    → git clone repository
Stage 2: Build       → docker build -t <image>:<tag>
Stage 3: Push        → docker push ขึ้น ACR
Stage 4: Deploy      → kubectl set image บน AKS
```

---

## basic-docker-build-job.xml

**หน้าที่:** Jenkins job configuration (XML format) ที่ใช้สร้าง job ผ่าน CLI

มี placeholders สำหรับ:
- Git repository URL
- ACR registry
- AKS cluster details
- MongoDB URI
- Groovy pipeline script (`{insert-groovy-script}` ถูกแทนที่ด้วย `basic-docker-build.groovy`)

---

## basic-user-pwd-credentials.xml

**หน้าที่:** Template XML สำหรับเพิ่ม credentials ของ ACR เข้า Jenkins Credentials Store

```xml
<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  <id>{credentials-id}</id>
  <username>{username}</username>
  <password>{password}</password>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
```

---

## jenkins-verified-ver

**หน้าที่:** ไฟล์ข้อความที่บันทึก Jenkins version ที่ทดสอบแล้วว่าใช้งานได้ (`2.73.3`) ใช้อ้างอิงเมื่อต้องการตรวจสอบ compatibility

---

## jenkins-on-azure/

ดูรายละเอียดได้ที่ [jenkins-on-azure/README.md](jenkins-on-azure/README.md)
