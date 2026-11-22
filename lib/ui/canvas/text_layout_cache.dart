import 'dart:collection';

import 'package:flutter/painting.dart';

/// ข้อความที่จัดวางแล้ว ใช้ซ้ำข้ามเฟรม/ข้ามการวาด — painter ของแผนภาพวาดข้อความเดิมหลายร้อยชิ้นทุกครั้งที่บันทึกภาพใหม่
/// (เลือก/ลากสิ่งหนึ่ง = วาดทั้งแผนภาพใหม่) การจัดวางข้อความเป็นงานที่แพงที่สุดในนั้น
///
/// key = ข้อความ+สไตล์ ([TextSpan] เทียบแบบลึก) + ตัวเลือกการจัดวาง ; ผลที่ได้ห้ามเรียก layout ซ้ำ/แก้ค่า (ใช้ร่วมกัน)
final LinkedHashMap<(InlineSpan, TextAlign, int?, String?, double, double, TextDirection), TextPainter> _cache = LinkedHashMap();
const _kMax = 6000;

TextPainter layoutText({
  required InlineSpan text,
  TextDirection textDirection = TextDirection.ltr,
  TextAlign textAlign = TextAlign.left,
  int? maxLines,
  String? ellipsis,
  double minWidth = 0,
  double maxWidth = double.infinity,
}) {
  final key = (text, textAlign, maxLines, ellipsis, minWidth, maxWidth, textDirection);
  final hit = _cache.remove(key);
  if (hit != null) {
    _cache[key] = hit; // ใช้ล่าสุด -> ย้ายไปท้าย
    return hit;
  }
  final tp = TextPainter(
    text: text,
    textDirection: textDirection,
    textAlign: textAlign,
    maxLines: maxLines,
    ellipsis: ellipsis,
  )..layout(minWidth: minWidth, maxWidth: maxWidth);
  _cache[key] = tp;
  if (_cache.length > _kMax) _cache.remove(_cache.keys.first);
  return tp;
}

/// ล้างแคช (เช่น เมื่อฟอนต์ในระบบเปลี่ยน) — ใช้ในเทสต์ได้
void clearTextLayoutCache() => _cache.clear();
