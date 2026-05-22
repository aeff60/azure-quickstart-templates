# kubernetes/ — Kubernetes Manifests

โฟลเดอร์นี้เก็บ YAML manifest สำหรับ deploy แอป Hello World ขึ้น AKS Jenkins จะนำไฟล์เหล่านี้ไปใช้ใน pipeline เมื่อ deploy container ใหม่

---

## hello-world-deployment.yaml

**หน้าที่:** กำหนดว่าจะรัน container อย่างไรบน Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
```

### รายละเอียด

| ค่า | รายละเอียด |
|---|---|
| Replicas | 2 pods (high availability) |
| Image | ดึงจาก ACR — Jenkins จะแทนที่ tag ก่อน deploy |
| Port | 80 |
| CPU Request / Limit | 100m / 250m |
| Memory Request / Limit | 128Mi / 256Mi |
| Environment Variable | `MONGODB_URI` — connection string ไปยัง CosmosDB |

### การทำงาน

- Jenkins build Docker image → push ขึ้น ACR
- Jenkins แทนที่ image tag ใน manifest นี้ด้วย tag ใหม่
- `kubectl apply` นำ manifest ไป deploy บน AKS
- Kubernetes สร้าง/อัปเดต 2 pods พร้อมกัน

---

## hello-world-service.yaml

**หน้าที่:** สร้าง LoadBalancer เพื่อให้ภายนอกเข้าถึงแอปได้

```yaml
apiVersion: v1
kind: Service
spec:
  type: LoadBalancer
```

### รายละเอียด

| ค่า | รายละเอียด |
|---|---|
| Type | `LoadBalancer` — Azure จะสร้าง Public IP ให้อัตโนมัติ |
| Port | 80 (รับ traffic จากภายนอก) |
| Target Port | 80 (ส่งไปยัง container) |
| Selector | `app: hello-world` (match กับ pods จาก Deployment) |

### วิธีดู External IP

```sh
kubectl get service hello-world-service
```

เมื่อได้ `EXTERNAL-IP` แล้ว เปิดในเบราว์เซอร์จะเห็นหน้า Hello World
