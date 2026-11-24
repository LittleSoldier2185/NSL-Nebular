# design/ — ดีไซน์หน้าตา NSL Nebular

สำเนาของ Artifact "NSL Nebular - UI ใหม่" (บันทึกเมื่อ 2026-11-18) ใช้เป็นต้นแบบของ UI ตาม `plan.md`
เก็บไว้ในโปรเจกต์เพื่อไม่ต้องพึ่งลิงก์ Artifact (ซึ่งเป็นส่วนตัว) — **ลิงก์ต้นทาง:** https://claude.ai/artifact/AfFCTth52Bgg8qnkfbmrqU

## ไฟล์

`project/canvas.json` คือผังตำแหน่งของ artboard ทั้งหมด ; แต่ละหน้าอยู่ใน `project/<ชื่อ>.dc.html`

| ไฟล์ | หน้า | ใช้กับ phase |
|---|---|---|
| `Main.dc.html` | Workspace — ER Diagram (โครงหน้าต่างหลัก) | 1 |
| `Start.dc.html`, `NewProject.dc.html` | หน้าเปิดโปรแกรม, สร้างโปรเจกต์ใหม่ | 2 |
| `Home.dc.html` | Project Home | 3 |
| `Flowchart.dc.html` | Flowchart Editor (คลังรูปทรง 34 แบบ) | 4 |
| `Review.dc.html` | โน้ตและงานค้าง | 5 |
| `Dictionary.dc.html` | พจนานุกรมข้อมูล | 6 |
| `History.dc.html` | ประวัติเวอร์ชันและ Diff | 7 |
| `Api.dc.html` | API Designer | 8 |
| `Trace.dc.html` | Requirements และ Traceability | 9 |
| `Codegen.dc.html` | Code Generation | 10 |
| `Mock.dc.html` | Mock Server | 11 |
| `wireframe-panel/` | แผงขวาของ Wireframe 3 แนวทาง (ใช้แบบ C) — สำเนาของ Artifact "Wireframe แผงขวา" https://claude.ai/artifact/WE9mmEUw3g6y3arvpf3Y6t | (ระหว่าง 11–12) |
| `menus/` | เมนูมุมมอง/เครื่องมือ (ทำแล้ว) + เมนูไฟล์/แก้ไข/ช่วยเหลือ — สำเนาของ Artifact "NSL Nebular — เมนูมุมมองใหม่" https://claude.ai/artifact/FQZNui1HypLGJdgxHaeK4s | 12, 14 |
| `dfd/` | ตัวแก้ไข DFD (หน้าต่างเต็ม + แผงขวาเมื่อเลือกที่เก็บข้อมูล/เส้นข้อมูล) — สำเนาของ Artifact "NSL Nebular — ตัวแก้ไข DFD" https://claude.ai/artifact/Kj5SkA4i5TTxpaF1pwPvyE | 15 |
| `screenflow/` | ตัวแก้ไข Screen Flow (หน้าต่างเต็ม + แผงขวาเมื่อเลือกการเปลี่ยนหน้า / ภาพรวม) — สำเนาของ Artifact "NSL Nebular — ตัวแก้ไข Screen Flow" https://claude.ai/artifact/2RrVKvUKRQDVHhGadNRoQA | 16 |
| `er-cardinality/` | ตัวเลือก 3 แบบของแผงขวากำหนดสัญลักษณ์ความสัมพันธ์ ER (เล่นได้ ใช้แบบ B) — สำเนาของ Artifact "ER Cardinality Panel" https://claude.ai/artifact/LVdBMMprMtrjMgCWJng1u8 | 17b |
| `er-table-form/` | กล่องสร้าง/แก้ตาราง 4 แท็บ + แถบ SQL + ค่าที่อนุญาต/CHECK (เล่นได้ ใช้แบบ C) — สำเนาของ Artifact https://claude.ai/artifact/QPLeHKnAx5NZPaUrJ1ro5z | 19 |
| `wireframe-library/` | ตัวเลือกแถบเครื่องมือเต็มความกว้าง + คลังชิ้นส่วน 6 หมวด 3 แบบของ Wireframe (ใช้แบบ A + มุมมองรายการแบบ B) — สำเนาของ Artifact "Wireframe Library Panel" https://claude.ai/artifact/73Ygw8uCen2XzVcpCSSyGr | 18 |
| `use-case/` | Use Case 3 แนวทาง (รวม A+B+C : สเปก / แผนภาพ / เอกสาร ; รอบ 1 ทำสเปก+เอกสาร) — สำเนาของ Artifact "Use Case Designer" https://claude.ai/artifact/PUN4uJvV2h9fnKxyT9GrHQ | 27 |
| `project-home/` | หน้า Project Home 3 แบบ (ใช้แบบ A: ปรับของเดิม) — สำเนาของ Artifact "Project Home" https://claude.ai/artifact/5cPyrDfXRPZgsFsDpiuCeE | 26 |
| `flowchart-panel/` | แผงขวา Flowchart 3 แบบ (ใช้แบบ A: 3 แท็บ รูปทรง / เส้น / ตรวจ) — สำเนาของ Artifact "Flowchart Panel" https://claude.ai/artifact/Gy8NzyEygyNDMeJkp4HPne | 25 |
| `wireframe-components/` | ชิ้นส่วน Wireframe ใหม่ 15 ชนิด + แม่แบบ 8 ชุด + หมวดใหม่ในคลัง (สไตล์ร่าง/เรียบร้อย) — สำเนาของ Artifact "Wireframe Components" https://claude.ai/artifact/DrdFBbFPPesG9w3oBi3tat | 18b |

## วิธีดู

ไฟล์ `.dc.html` เป็นรูปแบบของเครื่องมือออกแบบ (ต้องมี `support.js` ของมัน) จึง **เปิดตรง ๆ ในเบราว์เซอร์ไม่ได้ครบ**
แต่เป็น HTML + inline style ธรรมดา อ่านค่า สี ขนาด และระยะจากไฟล์ได้เลย — ใช้เป็นข้อมูลอ้างอิงตอนทำ UI จริงใน Flutter

## หมายเหตุ

- ค่าสีทั้งหมดในดีไซน์ต้องมาจาก token ของ NSL-UI-Core (ส่วนขยาย `nebular`) — **ห้ามคัดลอกค่า hex จากไฟล์ดีไซน์ไปฝังในโค้ดแอป**
  สีประจำชนิดเอกสารใช้ `C.doc(DocType)` (`lib/ui/theme.dart`)
- ดีไซน์เป็นแบบออฟไลน์ ผู้ใช้คนเดียว (ไม่มีคอมเมนต์หลายคน/อนุมัติ)
- รายชื่อรูปทรง Flowchart ในดีไซน์เขียนจากความจำ ต้องเทียบกับ draw.io จริงก่อนลงมือ (Phase 4)
- ถ้าแก้ดีไซน์ใน Artifact ให้บันทึกสำเนาใหม่ทับที่นี่ และบอกเหตุผลใน `progress.md`
