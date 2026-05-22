---
description: ระบบ CI/CD ด้วย Jenkins บน Azure Container Service (AKS) สำหรับ build และ deploy Docker container อัตโนมัติ
page_type: sample
products:
- azure
- azure-resource-manager
urlFragment: jenkins-cicd-container
languages:
- json
---
# CI/CD ด้วย Jenkins บน Azure Container Service (AKS)

## ภาพรวมสถาปัตยกรรม

ระบบนี้ใช้ Jenkins เป็นตัว build และ deploy แอปพลิเคชันแบบ container โดยอัตโนมัติ ทำงานร่วมกับ Kubernetes (AKS) เพื่อจัดการ container และ Grafana สำหรับแสดงผล metrics

![](images/architecture.png)

1. แก้ไข source code ของแอปพลิเคชัน
2. Commit code ขึ้น GitHub
3. GitHub ส่ง trigger ไปยัง Jenkins
4. Jenkins สั่ง build โดยใช้ AKS เป็น build agent
5. Jenkins build Docker image แล้วอัปโหลดขึ้น Azure Container Registry (ACR)
6. Jenkins deploy container ใหม่ไปยัง Kubernetes (AKS) ที่ใช้ CosmosDB เป็น database
7. Grafana แสดงกราฟ metrics ผ่าน Azure Monitor
8. ตรวจสอบและปรับปรุงระบบ

---

## ขั้นตอนการ Deploy

### 1. สร้าง Azure Service Principal

Service Principal คือ account ที่ให้ template สร้าง resource ต่างๆ ใน Azure ได้

1. ติดตั้ง [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) หรือใช้ **Azure Cloud Shell** จาก Azure Portal ได้เลย

2. Login:

   ```sh
   az login
   ```

3. สร้าง Service Principal:

   ```sh
   az ad sp create-for-rbac --name <ชื่อที่ต้องการ> --role Contributor
   ```

4. จะได้ผลลัพธ์แบบนี้ — เก็บค่า **appId** และ **password** ไว้:

   ```json
   {
      "appId": "8e897eb4-069d-40c2-9563-000000003c14",
      "displayName": "<ชื่อที่ตั้ง>",
      "password": "xxxxxvJgeKZoRAfxxxx0SitnANH8Kxxxx",
      "tenant": "000088bf-0000-0000-0000-2d7cd0100000"
   }
   ```

### 2. สร้าง SSH Key สำหรับ VM

1. เปิด [Azure Portal](https://portal.azure.com/) แล้วค้นหา **SSH keys**

2. กด **Create** แล้วกรอก:
   - เลือก/สร้าง Resource group
   - เลือก Region
   - ตั้งชื่อ Key pair
   - SSH public key source → **Generate public key pair**

3. กด **Review + create** → **Create**

4. เมื่อ popup ขึ้น กด **Download private key and create resource** เพื่อดาวน์โหลดไฟล์ `.pem`

   ![](images/portal-sshkey.png)
   ![](images/download-key.png)

5. เก็บไฟล์ `.pem` ไว้ในที่จำได้

### 3. Deploy ด้วย Azure Portal

1. กดปุ่มด้านล่างเพื่อเริ่ม deploy:

   [![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2Fazure-quickstart-templates%2Fmaster%2Fapplication-workloads%2Fjenkins%2Fjenkins-cicd-container%2Fazuredeploy.json)

2. กรอกข้อมูลในฟอร์ม:
   - เลือก Subscription และสร้าง Resource group ใหม่
   - กรอกค่าต่างๆ พร้อมเลือก SSH Key ที่สร้างในขั้นตอนที่ 2
   - ติ๊ก **I agree to the terms and conditions**

   > **หมายเหตุ:**
   > - ชื่อ CosmosDB ควรมี suffix เพื่อป้องกัน conflict เช่น `cosmos-20260522`
   > - ชื่อ ACR ใช้ได้เฉพาะตัวอักษรและตัวเลขเท่านั้น เช่น `acr20260522`

3. กด **Purchase** รอประมาณ 13 นาที

### 4. ดู Output หลัง Deploy เสร็จ

เปิด **Deployments** → **Microsoft.Template** → **Outputs** ใน Resource group

![](images/azure-deployment-output.png)
![](images/azure-resource-group-deployments.png)

---

## การเข้าใช้งานระบบ

### เข้า Jenkins

Jenkins ไม่รองรับ HTTPS บน public IP โดยตรง — ต้องใช้ SSH tunnel แทน

#### เชื่อมต่อผ่าน SSH Tunnel

1. เปิด terminal แล้วรัน (แทนที่ `<keyfile>` ด้วย path ของไฟล์ `.pem` และ `<jenkins-fqdn>` ด้วย FQDN จาก output):

   ```sh
   ssh -i <keyfile> -L 8080:localhost:8080 azureuser@<jenkins-fqdn>
   ```

2. เมื่อถาม fingerprint พิมพ์ `yes` แล้ว Enter

3. กรอก **Linux Admin Password** ที่ตั้งไว้ตอน deploy

4. **เปิดหน้าต่าง terminal นี้ทิ้งไว้ตลอด**

#### ดึง Jenkins Admin Password (ครั้งแรก)

รันใน terminal SSH:

```sh
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

จะได้รหัสผ่าน เช่น: `77a6d3183ad24f9ca7df6181c81400d0`

ทำตาม wizard **Getting Started** ของ Jenkins แล้วติดตั้ง recommended plugins

#### Login Jenkins

1. เปิด http://localhost:8080 ในเบราว์เซอร์
2. กด **log in** → User: `admin` / Password ที่ได้มา
3. จะเห็น pipeline job **Hello World Build & Deploy**

![](images/jenkins-pipline-job.png)

---

### เข้าใช้แอป Hello World

#### ดึง Credentials ของ AKS

```sh
az login
az aks get-credentials --resource-group <ResourceGroup> --name <KubernetesClusterName>
```

#### ดู External IP ของ service

ติดตั้ง kubectl ถ้ายังไม่มี: `az aks install-cli`

```sh
kubectl get service
```

ผลลัพธ์:

```
NAME                  TYPE           CLUSTER-IP   EXTERNAL-IP      PORT(S)
hello-world-service   LoadBalancer   10.0.98.99   52.168.126.156   80:32611/TCP
```

เปิด **EXTERNAL-IP** ในเบราว์เซอร์ จะเห็น:

```
Hello World!
There are 0 request records.
```

รีเฟรชหน้า จำนวน records จะเพิ่มขึ้น

---

### เข้าใช้ Grafana

1. คัดลอก **GRAFANAURL** จาก output ของ deployment
2. เปิดในเบราว์เซอร์ → login ด้วย User: `admin` / Password: Linux Admin Password
3. กด **Home** → **Hello World Overview**

![](images/grafana-01.png)
![](images/grafana-02.png)
![](images/grafana-03.png)

4. SSH เข้า Grafana ได้ด้วย:

   ```sh
   ssh -i <private_ssh_key> <username>@<GRAFANAURL>
   ```

---

## โครงสร้างไฟล์ในโปรเจค

```
jenkins-cicd-container/
├── azuredeploy.json              # ARM template หลัก — สร้าง infrastructure ทั้งหมด
├── azuredeploy.parameters.json   # ค่า parameters สำหรับ ARM template
├── metadata.json                 # metadata ของ Azure quickstart template
├── Dockerfile                    # สร้าง Docker image สำหรับแอป Hello World
├── server.js                     # แอป Node.js ที่จะ deploy ขึ้น AKS
├── package.json                  # dependencies ของ Node.js app
├── .gitignore                    # ไฟล์ที่ git ไม่ track (node_modules)
│
├── nested/                       # ARM nested templates (ดู nested/README.md)
│   ├── jenkins.json              # สร้าง Jenkins VM
│   └── grafana.json              # สร้าง Grafana VM
│
├── kubernetes/                   # Kubernetes manifests (ดู kubernetes/README.md)
│   ├── hello-world-deployment.yaml
│   └── hello-world-service.yaml
│
├── scripts/
│   ├── jenkins/                  # scripts สำหรับ Jenkins (ดู scripts/jenkins/README.md)
│   └── grafana/                  # scripts สำหรับ Grafana (ดู scripts/grafana/README.md)
│
└── images/                       # รูปภาพสำหรับ README
```

### ไฟล์ที่ root

| ไฟล์ | หน้าที่ |
|---|---|
| `azuredeploy.json` | ARM template หลัก — สั่ง deploy ทุก resource (ACR, CosmosDB, VNet, Jenkins VM, AKS, Grafana VM) ในครั้งเดียว |
| `azuredeploy.parameters.json` | ไฟล์กำหนดค่า input สำหรับ ARM template เช่น service principal, admin password, DNS name |
| `metadata.json` | ข้อมูล metadata ของ template สำหรับ Azure Quickstart Gallery |
| `Dockerfile` | สร้าง Docker image จาก Node 16 + ติดตั้ง dependencies + รัน server.js บน port 80 |
| `server.js` | แอป Node.js ที่รับ HTTP request, บันทึกลง MongoDB (CosmosDB), และตอบกลับด้วยจำนวน records |
| `package.json` | กำหนด dependencies ของ Node app — ใช้ `mongodb` driver v4.3.1 |

---

`Tags: Microsoft.ContainerRegistry/registries, Microsoft.DocumentDb/databaseAccounts, Microsoft.Network/virtualNetworks, Microsoft.Resources/deployments, Microsoft.ContainerService/managedClusters, Microsoft.Network/publicIPAddresses, Microsoft.Network/networkSecurityGroups, Microsoft.Network/networkInterfaces, Microsoft.Compute/virtualMachines, extensions, CustomScript`
