# scripts/jenkins/jenkins-on-azure/ — Jenkins Landing Page

โฟลเดอร์นี้เก็บ static web page ที่แสดงแทนหน้า Jenkins เมื่อผู้ใช้เปิด public IP โดยตรง เพื่อแจ้งเตือนว่าต้องใช้ SSH tunnel แทน

---

## index.html

**หน้าที่:** หน้าเว็บที่แสดงคำแนะนำให้ผู้ใช้ใช้ SSH port forwarding

### เนื้อหาที่แสดง

- แจ้งเตือนว่า HTTPS ยังไม่ได้เปิดใช้งาน → **ห้าม login ผ่าน public IP**
- แสดงคำสั่ง SSH tunnel พร้อมปุ่ม copy:
  ```sh
  ssh -L 127.0.0.1:8080:localhost:8080 azureuser@<jenkins-fqdn>
  ```
- แสดงลิงก์ไปยัง `http://localhost:8080` หลังเชื่อมต่อแล้ว

### เหตุผล

Jenkins ไม่มี HTTPS certificate — ถ้า login ผ่าน HTTP บน public IP รหัสผ่านจะถูกส่งแบบ plain text ซึ่งไม่ปลอดภัย การใช้ SSH tunnel ทำให้ traffic เข้ารหัสตลอดเส้นทาง

---

## site.css

**หน้าที่:** Stylesheet สำหรับ landing page

| ส่วน | รายละเอียด |
|---|---|
| Header | พื้นหลังสีดำ สูง 40px |
| Logo | ตำแหน่ง absolute ภายใน header |
| Breadcrumb | Typography สำหรับ navigation text |
| Sticker | ตำแหน่งของ element แสดงข้อมูล |

---

## site.js

**หน้าที่:** JavaScript (jQuery) สำหรับฟีเจอร์ copy-to-clipboard

### การทำงาน

- เมื่อ hover บน code snippet จะแสดง clipboard icon
- คลิก icon → คัดลอก command SSH ไปยัง clipboard
- รองรับหลาย browser (`document.selection`, `window.getSelection`, `execCommand`)

---

## install-web-page.sh

**หน้าที่:** Script ติดตั้ง landing page นี้บน nginx ของ Jenkins VM

### Arguments

| Flag | ความหมาย |
|---|---|
| `-l` | Web root location (เช่น `/var/www/html`) |
| `-d` | Domain URL ของ Jenkins (FQDN) |
| `-a` | Artifacts location URL |
| `-t` | Artifacts SAS token |

### ขั้นตอนที่ทำงาน

1. ดาวน์โหลด `index.html`, `site.css`, `site.js` จาก artifacts_location
2. แทนที่ placeholder URL ด้วย Jenkins FQDN จริง
3. คัดลอกไฟล์ไปยัง web root ของ nginx
4. nginx จะ serve หน้านี้แทน Jenkins เมื่อเปิด public IP
