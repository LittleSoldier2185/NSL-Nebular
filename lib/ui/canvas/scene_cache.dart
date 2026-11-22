import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/l10n/l10n.dart';
import '../theme.dart';

/// ภาพเนื้อหาแผนภาพทั้งชุด (พิกัดแผนภาพ) ที่บันทึกไว้ต่อ [owner] (ปกติคือวัตถุเนื้อหาของเอกสาร)
///
/// แพน/ซูมเปลี่ยนแค่ Matrix ก่อนวาด จึงเล่นภาพเดิมซ้ำได้ ไม่ต้องจัดวางข้อความ/คำนวณเส้นทางใหม่ทุกเฟรม
/// บันทึกใหม่เมื่อ [key] เปลี่ยน — key ต้องรวมทุกอย่างที่ [draw] อ่าน (เนื้อหา, สิ่งที่เลือก ฯลฯ) ; ธีมและภาษาเติมให้เอง
final Expando<(String, ui.Picture)> _scenes = Expando('scene');

void drawCachedScene(Canvas canvas, Object owner, String key, void Function(Canvas c) draw) {
  final full = '${identityHashCode(C.palette)}|${currentLang.name}|$key';
  final hit = _scenes[owner];
  if (hit != null && hit.$1 == full) {
    canvas.drawPicture(hit.$2);
    return;
  }
  final rec = ui.PictureRecorder();
  draw(Canvas(rec));
  final pic = rec.endRecording();
  // ภาพเก่าปล่อยให้ระบบเก็บกวาดเอง (อาจยังถูกอ้างในเฟรมที่กำลังวาด — เหมือน WfPictureCache)
  _scenes[owner] = (full, pic);
  canvas.drawPicture(pic);
}

/// ส่วนของ key สำหรับเซตที่ลำดับไม่สำคัญ
String setKey(Iterable<String> ids) => (ids.toList()..sort()).join(',');
