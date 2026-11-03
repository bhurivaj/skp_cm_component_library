# Changelog

## [0.2.0] - 2026-11-03

### Added
- เวอร์ชันรายตัว: `index.json` schema 2 — แต่ละ component มี `version` ของตัวเอง ไฟล์อยู่ใต้ `library/<version>/`
- Publish ตัวที่เลือก (เมนู + คลิกขวา): เลือก component ใน CM Structure Set แล้วส่งขึ้นเฉพาะตัวนั้น ตัวอื่นคงเวอร์ชันเดิม
- Upload ขึ้น Azure จากใน SketchUp ด้วย SAS ของ container (ถามครั้งแรก จำไว้ในเครื่อง) — Publish ทั้งหมด / ตัวที่เลือก upload ให้เอง
- แถบ "ไฟล์นี้มี component เวอร์ชันเก่า N ตัว" + ปุ่ม อัปเดตในงาน (ดาวน์โหลดครบก่อน แล้วแทนในขั้นเดียว undo ได้) — นับตัวที่ copy จาก Structure Set เองด้วยถ้าชื่อตรง Code
- คลิกวางตัวที่ในไฟล์เป็นเวอร์ชันเก่า → ถาม อัปเดตทั้งหมดแล้ววางตัวใหม่ / วางตัวเดิม
- แจ้งเตือนของใหม่ในหน้าต่าง: ป้าย ใหม่/อัปเดต บน tile, หมวด "ใหม่/อัปเดต", ปุ่ม รับทราบ

### Changed
- Publish ใช้ได้เฉพาะในไฟล์ `CM Structure Set.skp`; จำ path CSV ไว้ใช้ครั้งต่อไป
- plugin 0.1.0 อ่านรายการ schema 2 ไม่ได้ — ต้องอัปเดตผ่าน Hub

### Removed
- `tools/upload_library.sh` (plugin upload เองแล้ว)

## [0.1.0] - 2026-11-03

### Added
- หน้าต่าง Component Library: หมวดด้านซ้าย (พร้อมจำนวน), ตาราง thumbnail, ค้นหาจาก code / ชื่อ — คลิกแล้ว component ติดเมาส์ให้วาง (ใช้ definition เดิมถ้ามีในงานแล้ว)
- โหลดรายการจาก Azure Blob (`sketchup` / `component-library`) และเก็บ cache ในเครื่อง — offline ใช้รายการและไฟล์ที่เคยโหลดไว้
- เมนู Publish Library…: อ่าน sheet Code List (CSV UTF-8) แล้วแตก component ที่ชื่อตรง Code ใน CM Structure Set เป็นไฟล์ `.skp` + รูป + `index.json` ลงโฟลเดอร์ staging พร้อมสรุป Code ที่ไม่มี component
- `tools/upload_library.sh`: upload ไฟล์ Publish ขึ้น Azure (index.json เป็นไฟล์สุดท้าย)
- ต้อง login SKP CM Extensions Hub (0.4.0 ขึ้นไป)
