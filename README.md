# SKP CM Component Library

เลือก component มาตรฐาน (จาก CM Structure Set) มาวางในงาน SketchUp โดยไม่ต้องเปิดไฟล์ Structure Set

- Target: SketchUp 2024+ — ติดตั้งผ่าน SKP CM Extensions Hub — ต้อง login Hub (0.4.0 ขึ้นไป)
- Spec: `../docs/specs/2026-11-01-component-library-design.md`

## ใช้งาน (ทุกคน)

Extensions › SKP CM Component Library › **Component Library** (หรือปุ่มบน toolbar)

- เลือกหมวดด้านซ้าย / พิมพ์ค้นหา code หรือชื่อ — หมวด **ใหม่/อัปเดต** โผล่เมื่อ library มีของเปลี่ยน (กด **รับทราบ** เพื่อซ่อนป้าย)
- คลิก component → ติดเมาส์ → คลิกวาง (Esc ยกเลิก)
- ไฟล์งานมี component เวอร์ชันเก่า → แถบด้านบนบอกจำนวน กด **อัปเดตในงาน** (undo ได้ขั้นเดียว — ตัวที่แก้เองในไฟล์จะถูกแทน)
- ครั้งแรกที่ใช้แต่ละตัวต้อง online (ดาวน์โหลดไฟล์) ครั้งต่อไปใช้ offline ได้

## Publish (เจ้าของ — Mac, เฉพาะในไฟล์ `CM Structure Set.skp`)

ตั้งครั้งเดียว: storage account `sketchup` เปิด "Allow Blob anonymous access", container `component-library` ระดับ access **Blob**,
และสร้าง **SAS ของ container** (Shared access tokens › สิทธิ์ Create + Write) — plugin ถามครั้งแรกที่ upload แล้วจำไว้ในเครื่อง (หมดอายุ/403 → ถามใหม่)

1. CSV: `Material Code.xlsx` › sheet `Code List` › Save As **CSV UTF-8** — plugin จำ path ไว้ อ่านใหม่ทุกครั้งที่ Publish (แก้ xlsx แล้ว save CSV ทับที่เดิม)
2. แก้ component ใน `CM Structure Set.skp` แล้วเลือก:
   - **Publish ตัวที่เลือก** (เมนู หรือคลิกขวา) — เลือก component ที่แก้ ส่งเฉพาะตัวนั้น *(ใช้ปกติ)*
   - **Publish ทั้งหมด…** — ส่งใหม่ทั้งชุด ทุกตัวจะขึ้นป้าย "อัปเดต" ในเครื่องของทีม *(ใช้เมื่อเพิ่ม/ลบหลายตัว)*
3. รอ upload (ดูความคืบหน้าที่ status bar ด้านล่าง) → อ่านสรุป โดยเฉพาะ "Code ใน CSV ที่ไม่มี component"
4. ลบโฟลเดอร์ `library/<version>` เก่าที่ไม่มีใครใช้ใน Azure Portal เป็นครั้งคราว (ดู `version` ที่ยังใช้ใน `library/index.json`)

## Dev

- Test: `for t in tests/tc_*.rb; do ruby "$t"; done`
- Build: `sh build.sh` → `skp_cm_component_library_<VERSION>.rbz` (loader + โฟลเดอร์ plugin เท่านั้น)
