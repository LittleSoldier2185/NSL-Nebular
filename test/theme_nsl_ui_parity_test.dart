// ค่าสีเดิมของแอป (ก่อนย้ายไปคำนวณจากธีม nsl.nebular ของ nsl_ui) เก็บเป็นค่าตายตัวเพื่อกันถอยหลัง
// ถ้าต้องเปลี่ยนสีจริง ๆ ให้แก้ที่ธีมใน nsl_ui แล้วอัปเดตเทสต์นี้พร้อมกันโดยตั้งใจ
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/ui/theme.dart';

const _light = <String, Color>{
  'bg': Color(0xFFEEF1F5),
  'canvas': Color(0xFFF6F8FB),
  'dot': Color(0xFFC3CCD8),
  'surface': Colors.white,
  'surfaceHi': Colors.white,
  'border': Color(0xFFD8DEE6),
  'borderSoft': Color(0xFFE6EAF0),
  'inputBorder': Color(0xFFCBD3DE),
  'text': Color(0xFF1B2430),
  'muted': Color(0xFF5B6778),
  'primary': Color(0xFF0F766E),
  'primaryDark': Color(0xFF0B5A54),
  'primaryTint': Color(0xFFE2F3F1),
  'tableHead': Color(0xFF1F2A37),
  'warnBg': Color(0xFFFFF4D6),
  'warnText': Color(0xFF5C3D00),
  'infoBg': Color(0xFFE8EEF8),
  'infoText': Color(0xFF1E3A6B),
  'field': Color(0xFFF3F5F8),
  'pkBg': Color(0xFFFDEBD3),
  'pkText': Color(0xFF8A4B08),
  'uqBg': Color(0xFFEDE9FE),
  'uqText': Color(0xFF5B21B6),
  'nnBg': Color(0xFFE6EAF0),
  'nnText': Color(0xFF334155),
  'shadow': Color(0xFF0F172A),
};

const _dark = <String, Color>{
  'bg': Color(0xFF0E1319),
  'canvas': Color(0xFF121820),
  'dot': Color(0xFF2A3544),
  'surface': Color(0xFF19212B),
  'surfaceHi': Color(0xFF212B37),
  'border': Color(0xFF2E3946),
  'borderSoft': Color(0xFF242E3A),
  'inputBorder': Color(0xFF3B4859),
  'text': Color(0xFFE6EBF2),
  'muted': Color(0xFF9AA7B8),
  'primary': Color(0xFF14958B),
  'primaryDark': Color(0xFF5ED0C4),
  'primaryTint': Color(0xFF133533),
  'tableHead': Color(0xFF2A3848),
  'warnBg': Color(0xFF3A2E10),
  'warnText': Color(0xFFF4D58A),
  'infoBg': Color(0xFF1B2A44),
  'infoText': Color(0xFF9DBBEA),
  'field': Color(0xFF222C38),
  'pkBg': Color(0xFF4A3213),
  'pkText': Color(0xFFF5B66B),
  'uqBg': Color(0xFF2E2552),
  'uqText': Color(0xFFC4B0FA),
  'nnBg': Color(0xFF2A3441),
  'nnText': Color(0xFFB5C0CE),
  'shadow': Color(0xFF000000),
};

const _lightExtra = <String, Color>{
  'boardOutside': Color(0xFFE2E7EE),
  'boardEdge': Color(0xFFB4BFCD),
  'danger': Color(0xFFB42318),
  'dangerBg': Color(0xFFFDE8E8),
  'dangerText': Color(0xFF7A1F1F),
  'fkSource': Color(0xFFFFE9A8),
  'fkChip': Color(0xFFD9F0EC),
};

const _darkExtra = <String, Color>{
  'boardOutside': Color(0xFF0A0E13),
  'boardEdge': Color(0xFF3F4E62),
  'danger': Color(0xFFF97066),
  'dangerBg': Color(0xFF3F1B1B),
  'dangerText': Color(0xFFFCA5A5),
  'fkSource': Color(0xFF5A4A12),
  'fkChip': Color(0xFF16403D),
};

Map<String, Color> _actual(Palette p) => {
      'bg': p.bg,
      'canvas': p.canvas,
      'dot': p.dot,
      'surface': p.surface,
      'surfaceHi': p.surfaceHi,
      'border': p.border,
      'borderSoft': p.borderSoft,
      'inputBorder': p.inputBorder,
      'text': p.text,
      'muted': p.muted,
      'primary': p.primary,
      'primaryDark': p.primaryDark,
      'primaryTint': p.primaryTint,
      'tableHead': p.tableHead,
      'warnBg': p.warnBg,
      'warnText': p.warnText,
      'infoBg': p.infoBg,
      'infoText': p.infoText,
      'field': p.field,
      'pkBg': p.pkBg,
      'pkText': p.pkText,
      'uqBg': p.uqBg,
      'uqText': p.uqText,
      'nnBg': p.nnBg,
      'nnText': p.nnText,
      'shadow': p.shadow,
      'boardOutside': p.boardOutside,
      'boardEdge': p.boardEdge,
      'danger': p.danger,
      'dangerBg': p.dangerBg,
      'dangerText': p.dangerText,
      'fkSource': p.fkSource,
      'fkChip': p.fkChip,
    };

void main() {
  tearDown(() => C.use(kLightPalette));

  for (final (name, p, golden) in [
    ('light', kLightPalette, {..._light, ..._lightExtra}),
    ('dark', kDarkPalette, {..._dark, ..._darkExtra}),
  ]) {
    test('พาเลตต์$name (คำนวณจากธีม nsl.nebular) เท่าค่าเดิมของแอปทุกช่อง', () {
      final actual = _actual(p);
      expect(actual.keys.toSet(), golden.keys.toSet());
      for (final e in golden.entries) {
        expect(actual[e.key], e.value, reason: e.key);
      }
    });

    test('C.* อ่านจากพาเลตต์$name ตรงกับค่าเดิม', () {
      C.use(p);
      expect(C.danger, golden['danger']);
      expect(C.boardOutside, golden['boardOutside']);
      expect(C.fkChip, golden['fkChip']);
      expect(C.isDark, name == 'dark');
    });
  }

  test('สีพื้นผิวขาวของโหมดสว่างเป็นขาวล้วน (เดิมคือ Colors.white)', () {
    expect(kLightPalette.surface, Colors.white);
    expect(kLightPalette.surfaceHi, Colors.white);
  });

  test('buildTheme ใช้พาเลตต์ที่ให้มา', () {
    final t = buildTheme(kDarkPalette);
    expect(t.brightness, Brightness.dark);
    expect(t.scaffoldBackgroundColor, kDarkPalette.bg);
    expect(buildTheme().scaffoldBackgroundColor, kLightPalette.bg);
  });
}
