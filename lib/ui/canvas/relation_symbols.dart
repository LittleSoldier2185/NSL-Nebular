import 'package:flutter/material.dart';

import '../../core/layout/diagram_geometry.dart';

/// สัญลักษณ์ปลายเส้นความสัมพันธ์ ER (crow's foot) ที่ใช้ร่วมกันระหว่างเส้นบนแคนวาส ([RelationPainter])
/// และภาพตัวอย่าง/ปุ่มเลือกสัญลักษณ์ในแผงขวา (Phase 17b) — [dir] = ทิศที่เส้นยื่นออกจากขอบการ์ด (+1 ขวา, -1 ซ้าย)

/// ตีนกา "หลาย" ยาว 14
void drawCrow(Canvas canvas, Paint p, double x, double y, double dir) {
  final tip = x + dir * 14;
  canvas.drawLine(Offset(tip, y), Offset(x, y - 8), p);
  canvas.drawLine(Offset(tip, y), Offset(x, y), p);
  canvas.drawLine(Offset(tip, y), Offset(x, y + 8), p);
}

/// ขีดตั้ง "หนึ่ง" อยู่ห่างขอบการ์ด 8
void drawBar(Canvas canvas, Paint p, double x, double y, double dir, {double half = 8}) {
  final bx = x + dir * 8;
  canvas.drawLine(Offset(bx, y - half), Offset(bx, y + half), p);
}

/// วงกลม "ศูนย์" ทึบด้วยสีพื้น [knockout] เพื่อตัดเส้นที่ผ่านใต้ออก
void drawZero(Canvas canvas, Paint p, Offset c, Color knockout, {double r = 4.5}) {
  canvas.drawCircle(c, r, Paint()..color = knockout);
  canvas.drawCircle(c, r, p);
}

/// ปลายฝั่งลูก: [one] = ขีด (หนึ่ง) ไม่งั้นตีนกา (หลาย) ; ถัดออกไปเป็นวงกลม "ศูนย์" (ไม่บังคับ) หรือขีด (อย่างน้อย 1 = [required])
void drawChildEnd(Canvas canvas, Paint p, double x, double y, double dir,
    {required bool one, required bool required, required Color knockout}) {
  if (one) {
    drawBar(canvas, p, x, y, dir);
  } else {
    drawCrow(canvas, p, x, y, dir);
  }
  final off = childZeroOffset(one);
  if (required) {
    drawBar(canvas, p, x + dir * (off - 8), y, dir);
  } else {
    drawZero(canvas, p, Offset(x + dir * off, y), knockout);
  }
}

/// ปลายฝั่งแม่: "หนึ่งเดียว" = ขีดคู่ ; "ศูนย์หรือหนึ่ง" = ขีดเดียวแล้ววงกลมถัดออกไป
/// [crowded] = มีเส้นอื่นเข้าคอลัมน์เดียวกัน -> ย่อสัญลักษณ์ลงไม่ให้ซ้อนกับของเส้นข้างเคียง
void drawParentEnd(Canvas canvas, Paint p, double x, double y, double dir,
    {required bool required, required Color knockout, bool crowded = false}) {
  final s = crowded ? 0.6 : 1.0;
  drawBar(canvas, p, x, y, dir, half: 8 * s);
  if (required) {
    drawBar(canvas, p, x + dir * 5, y, dir, half: 8 * s);
  } else {
    drawZero(canvas, p, Offset(x + dir * (crowded ? 13 : 17), y), knockout, r: 4.5 * s);
  }
}
