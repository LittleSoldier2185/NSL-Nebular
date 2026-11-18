import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_ui/nsl_ui.dart' show contrastRatio;
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/ui/theme.dart';

/// สีประจำชนิดเอกสาร (Phase 0): มาจาก token `nebular.doc*` ของ nsl_ui ผ่าน `Palette.docColor` / `C.doc`
void main() {
  for (final p in [kLightPalette, kDarkPalette]) {
    group('สีชนิดเอกสาร (${p.brightness.name})', () {
      test('ทุกชนิดเอกสารมีสี และสีหลักไม่ซ้ำกัน', () {
        final mains = {for (final t in DocType.values) p.docColor(t).main};
        expect(mains.length, DocType.values.length);
        for (final t in DocType.values) {
          expect(kDocColorKeys.containsKey(t), true, reason: 'DocType.${t.name} ต้องมีคีย์สีใน kDocColorKeys');
        }
      });

      test('ตัวอักษร (ink) บนพื้นอ่อน (tint) ผ่าน 4.5:1', () {
        for (final t in DocType.values) {
          final c = p.docColor(t);
          expect(contrastRatio(c.ink, c.tint), greaterThanOrEqualTo(4.5), reason: t.name);
        }
      });
    });
  }

  test('โหมดสว่างตรงกับดีไซน์ NSL Nebular', () {
    final l = kLightPalette;
    expect(l.docColor(DocType.er).main, const Color(0xFF0F766E));
    expect(l.docColor(DocType.dfd).main, const Color(0xFF2F6FB5));
    expect(l.docColor(DocType.flowchart).main, const Color(0xFF6D4FC2));
    expect(l.docColor(DocType.wireframe).main, const Color(0xFFB7791F));
    expect(l.docColor(DocType.screenflow).main, const Color(0xFFB83B6B));
  });

  test('C.doc อ่านจากพาเลตต์ที่ใช้อยู่ (สลับธีมแล้วเปลี่ยนตาม)', () {
    C.use(kLightPalette);
    final light = C.doc(DocType.er).main;
    C.use(kDarkPalette);
    final dark = C.doc(DocType.er).main;
    C.use(kLightPalette);
    expect(light, isNot(dark));
  });
}
