import 'dart:convert';

/// เขียนค่าแบบ JSON (`Map` / `List` / ข้อความ / ตัวเลข / จริงเท็จ / null) เป็น YAML แบบบล็อก — คงลำดับคีย์ตามที่ให้มา
///
/// หลักการ: ข้อความที่ไม่ใส่เครื่องหมายคำพูดได้ ต้อง "ไม่มีทางถูกอ่านเป็นอย่างอื่น" เท่านั้น ที่เหลือครอบ `"…"`
/// (รูปแบบ escape ของ JSON ใช้ใน YAML แบบ double-quoted ได้) ; ข้อความหลายบรรทัดใช้บล็อก `|` เมื่ออ่านกลับได้ตรงเดิม
String writeYaml(Object? value) {
  final out = StringBuffer();
  if (value is Map && value.isNotEmpty) {
    _map(out, value, '');
  } else if (value is List && value.isNotEmpty) {
    _list(out, value, '');
  } else {
    out.writeln(_inline(value));
  }
  return out.toString();
}

/// ขึ้นต้นด้วยตัวอักษรละติน/`_`/`/` และมีเฉพาะอักขระที่ไม่มีความหมายพิเศษใน YAML ; ห้ามจบด้วยช่องว่าง
final _plain = RegExp(r'^[A-Za-z_/]([A-Za-z0-9_ ./{}()-]*[A-Za-z0-9_./{}()-])?$');

/// คำที่ตัวอ่าน YAML (ทั้ง 1.1 และ 1.2) อาจอ่านเป็นจริงเท็จหรือ null
const _reserved = {'true', 'false', 'null', 'yes', 'no', 'on', 'off', 'y', 'n'};

bool _isPlain(String s) => _plain.hasMatch(s) && !_reserved.contains(s.toLowerCase());

/// อักขระที่ `jsonEncode` ปล่อยไว้ตรง ๆ แต่ YAML ไม่ยอมรับ หรือถือเป็นการขึ้นบรรทัด
final _unsafe = RegExp('[\u007F-\u009F  ﻿￾￿]');

String _quoted(String s) => jsonEncode(s).replaceAllMapped(_unsafe, (m) => '\\u${m[0]!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}');

String _scalarString(String s) => _isPlain(s) ? s : _quoted(s);

/// อักขระควบคุมอื่นนอกจากขึ้นบรรทัด `\n`
final _control = RegExp('[\u0000-\u0009\u000B-\u001F]');

/// ใช้บล็อก `|` ได้ไหม: หลายบรรทัด จบด้วยขึ้นบรรทัดไม่เกินหนึ่ง และไม่มีสิ่งที่บล็อกอ่านกลับเพี้ยน
bool _canBlock(String s) {
  if (!s.contains('\n') || _control.hasMatch(s) || _unsafe.hasMatch(s) || s.endsWith('\n\n')) return false;
  final lines = (s.endsWith('\n') ? s.substring(0, s.length - 1) : s).split('\n');
  // บรรทัดแรกกำหนดระดับย่อหน้าของบล็อก จึงห้ามว่างหรือขึ้นต้นด้วยช่องว่าง ; ช่องว่างท้ายบรรทัดมักถูกตัวแก้ไขตัดทิ้ง
  return lines.first.isNotEmpty && !lines.first.startsWith(' ') && lines.every((l) => !l.endsWith(' '));
}

String _inline(Object? v) => switch (v) {
      null => 'null',
      String s => _scalarString(s),
      bool b => '$b',
      int i => '$i',
      double d when d.isNaN => '.nan',
      double d when d.isInfinite => d > 0 ? '.inf' : '-.inf',
      double d => '$d',
      Map m when m.isEmpty => '{}',
      List l when l.isEmpty => '[]',
      _ => _quoted('$v'),
    };

/// ค่าที่อยู่หลัง `คีย์:` หรือ `-` ; [indent] = ย่อหน้าของบรรทัดลูก
void _value(StringBuffer out, Object? v, String indent) {
  if (v is Map && v.isNotEmpty) {
    out.writeln();
    _map(out, v, indent);
  } else if (v is List && v.isNotEmpty) {
    out.writeln();
    _list(out, v, indent);
  } else if (v is String && _canBlock(v)) {
    final keep = v.endsWith('\n');
    out.writeln(keep ? ' |' : ' |-');
    for (final line in (keep ? v.substring(0, v.length - 1) : v).split('\n')) {
      out.writeln(line.isEmpty ? '' : '$indent$line');
    }
  } else {
    out.writeln(' ${_inline(v)}');
  }
}

void _map(StringBuffer out, Map<Object?, Object?> m, String indent, {bool firstInline = false}) {
  var first = true;
  for (final e in m.entries) {
    out.write('${first && firstInline ? '' : indent}${_scalarString('${e.key}')}:');
    first = false;
    _value(out, e.value, '$indent  ');
  }
}

void _list(StringBuffer out, List<Object?> l, String indent) {
  for (final v in l) {
    if (v is Map && v.isNotEmpty) {
      out.write('$indent- ');
      _map(out, v, '$indent  ', firstInline: true);
    } else {
      out.write('$indent-');
      _value(out, v, '$indent  ');
    }
  }
}
