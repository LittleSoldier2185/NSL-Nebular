import '../core/l10n/l10n.dart';
import '../state/project_templates.dart';

/// ชื่อ/คำอธิบายของจุดเริ่มต้นสำเร็จรูป (ใช้ทั้งหน้า Start และกล่องสร้างโปรเจกต์ใหม่)
String templateName(ProjectTemplate t) => switch (t) {
      ProjectTemplate.blank => tr('โปรเจกต์ว่าง'),
      ProjectTemplate.database => tr('ฐานข้อมูลอย่างเดียว'),
      ProjectTemplate.analysis => tr('วิเคราะห์ระบบ'),
      ProjectTemplate.appDesign => tr('ออกแบบแอป'),
      ProjectTemplate.flow => tr('ขั้นตอนงาน'),
      ProjectTemplate.full => tr('ครบทุกชนิด'),
    };

String templateDesc(ProjectTemplate t) => switch (t) {
      ProjectTemplate.blank => tr('เลือกเอกสารเอง'),
      ProjectTemplate.database => tr('ER + สร้าง SQL'),
      ProjectTemplate.analysis => tr('ER + DFD + Flowchart'),
      ProjectTemplate.appDesign => tr('ER + Wireframe + Screen Flow'),
      ProjectTemplate.flow => tr('Flowchart เป็นหลัก'),
      ProjectTemplate.full => tr('ER + DFD + Flowchart + Wireframe + Screen Flow'),
    };

