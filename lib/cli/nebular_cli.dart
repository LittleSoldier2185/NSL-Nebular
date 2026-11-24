import 'dart:convert';
import 'dart:io';

import '../core/app_info.dart';
import 'nebular_api.dart';

const _usage = '''
nebular — เครื่องมือบรรทัดคำสั่งของ NSL Nebular (ออฟไลน์ ทำงานกับไฟล์โปรเจกต์ในเครื่อง)

การใช้งาน:
  nebular <คำสั่ง> <ไฟล์โปรเจกต์> [ตัวเลือก]

คำสั่ง:
  info      <ไฟล์>                 ภาพรวมโปรเจกต์ (จำนวนเอกสาร ตาราง endpoint ปัญหา)
  docs      <ไฟล์>                 รายการเอกสาร (id ชนิด ชื่อ)
  show      <ไฟล์> <เอกสาร>         เนื้อหาเอกสารเป็น JSON (อ้างด้วย id หรือชื่อ)
  validate  <ไฟล์>                 ตรวจปัญหาทั้งโปรเจกต์ — จบด้วยรหัส 1 ถ้าพบ error
  export    <ไฟล์> --format F      ส่งออกเป็นข้อความ F = markdown | html | sql | openapi
  targets   [ไฟล์]                 รายการเป้าหมายสร้างโค้ด (ใส่ไฟล์ = บอกว่าตัวไหนสร้างได้)
  codegen   <ไฟล์> --targets T --out โฟลเดอร์
                                   สร้างโค้ด T = ชื่อคั่นด้วย , หรือ all ; ไม่ทับไฟล์ที่แก้ด้วยมือ
  version | help

ตัวเลือก:
  --json                 ผลลัพธ์เป็น JSON (info docs validate targets codegen)
  --lang th|en           ภาษาของข้อความจากตัวตรวจ (ค่าเริ่มต้น th)
  --min-severity S       validate: แสดงเฉพาะ error | warning | info ขึ้นไป
  --out PATH             export: เขียนลงไฟล์นี้ (ไม่ระบุ = พิมพ์ออกหน้าจอ) ; codegen: โฟลเดอร์ปลายทาง
  --document D           export openapi: เอกสาร API ที่ใช้
  --overwrite-edited     codegen: เขียนทับไฟล์ที่ถูกแก้ด้วยมือด้วย (ค่าเริ่มต้นคือข้าม)
  --dry-run              codegen: แสดงไฟล์ที่จะสร้างโดยไม่เขียน

โปรแกรมนี้อ่านไฟล์โปรเจกต์อย่างเดียว ไม่แก้ไฟล์โปรเจกต์ (ปลอดภัยแม้เปิดไฟล์เดียวกันในโปรแกรมอยู่)
รหัสจบ: 0 สำเร็จ · 1 validate พบ error · 2 ใช้ผิดหรือเกิดข้อผิดพลาด
''';

class _Args {
  _Args(this.positional, this.options, this.flags);
  final List<String> positional;
  final Map<String, String> options;
  final Set<String> flags;
}

const _valueOptions = {'lang', 'min-severity', 'out', 'document', 'format', 'targets'};
const _flagOptions = {'json', 'overwrite-edited', 'dry-run', 'help'};

_Args _parse(List<String> args) {
  final pos = <String>[];
  final opts = <String, String>{};
  final flags = <String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) {
      pos.add(a);
      continue;
    }
    final eq = a.indexOf('=');
    final name = eq < 0 ? a.substring(2) : a.substring(2, eq);
    if (_flagOptions.contains(name)) {
      flags.add(name);
    } else if (_valueOptions.contains(name)) {
      if (eq >= 0) {
        opts[name] = a.substring(eq + 1);
      } else if (i + 1 < args.length) {
        opts[name] = args[++i];
      } else {
        throw NebularError('ตัวเลือก --$name ต้องมีค่า');
      }
    } else {
      throw NebularError('ไม่รู้จักตัวเลือก --$name (ดู: nebular help)');
    }
  }
  return _Args(pos, opts, flags);
}

String _json(Object? o) => const JsonEncoder.withIndent('  ').convert(o);

/// รันคำสั่ง [args] — เขียนผลลง [out] / ข้อผิดพลาดลง [err] ; คืนรหัสจบ (0 สำเร็จ · 1 validate พบ error · 2 ผิดพลาด)
Future<int> runCli(List<String> args, {required StringSink out, required StringSink err}) async {
  try {
    if (args.isEmpty) {
      out.write(_usage);
      return 2;
    }
    final cmd = args.first;
    final a = _parse(args.sublist(1));
    if (cmd == 'help' || cmd == '--help' || a.flags.contains('help')) {
      out.write(_usage);
      return 0;
    }
    if (cmd == 'version' || cmd == '--version') {
      out.writeln('$kAppName $kAppVersion ($kAppCodename)');
      return 0;
    }
    setCliLanguage(a.options['lang']);
    final json = a.flags.contains('json');

    if (cmd == 'targets' && a.positional.isEmpty) {
      final list = listTargets();
      out.writeln(json ? _json(list) : [for (final t in list) '${t['name']}  (${t['source']} ← ${t['from']})'].join('\n'));
      return 0;
    }

    if (a.positional.isEmpty) throw NebularError('ต้องระบุไฟล์โปรเจกต์ (nebular $cmd <ไฟล์> …)');
    final path = a.positional.first;
    final w = await loadProject(path);

    switch (cmd) {
      case 'info':
        final i = projectInfo(w, path: path);
        out.writeln(json ? _json(i) : _infoText(i));
      case 'docs':
        final l = listDocuments(w);
        out.writeln(json ? _json(l) : [for (final d in l) '${d['id']}\t${d['type']}\t${d['name']}'].join('\n'));
      case 'show':
        if (a.positional.length < 2) throw NebularError('ต้องระบุเอกสาร (id หรือชื่อ) : nebular show <ไฟล์> <เอกสาร>');
        out.writeln(_json(readDocument(w, a.positional[1])));
      case 'validate':
        final r = validateReport(w, minSeverity: parseSeverity(a.options['min-severity']));
        out.writeln(json ? _json(r) : _validateText(r));
        return (r['errors'] as int) > 0 ? 1 : 0;
      case 'export':
        final format = a.options['format'];
        if (format == null) throw NebularError('ต้องระบุ --format (${kExportFormats.join(' | ')})');
        final text = exportProject(w, format, document: a.options['document']);
        final to = a.options['out'];
        if (to == null) {
          out.write(text);
          if (!text.endsWith('\n')) out.writeln();
        } else {
          final f = File(to);
          await f.parent.create(recursive: true);
          await f.writeAsString(text);
          out.writeln('เขียนแล้ว: ${f.absolute.path} (${utf8.encode(text).length} ไบต์)');
        }
      case 'targets':
        final list = listTargets(w);
        out.writeln(json ? _json(list) : [for (final t in list) '${t['available'] == true ? '✓' : '✗'} ${t['name']}  (${t['source']} ← ${t['from']})'].join('\n'));
      case 'codegen':
        final t = a.options['targets'];
        if (t == null) throw NebularError('ต้องระบุ --targets (ชื่อคั่นด้วย , หรือ all) ดูรายการด้วย: nebular targets');
        final targets = parseTargets(w, t.split(','));
        if (a.flags.contains('dry-run')) {
          final p = codegenPreview(w, targets);
          out.writeln(json ? _json(p) : _previewText(p));
          return 0;
        }
        final dir = a.options['out'];
        if (dir == null) throw NebularError('ต้องระบุ --out โฟลเดอร์ปลายทาง (หรือใช้ --dry-run เพื่อดูเฉย ๆ)');
        final r = await codegenWrite(w, targets, dir, overwriteEdited: a.flags.contains('overwrite-edited'));
        out.writeln(json ? _json(r) : _codegenText(r));
      default:
        throw NebularError('ไม่รู้จักคำสั่ง "$cmd" (ดู: nebular help)');
    }
    return 0;
  } on NebularError catch (e) {
    err.writeln('ผิดพลาด: ${e.message}');
    return 2;
  }
}

String _infoText(Map<String, dynamic> i) {
  final issues = i['issues'] as Map;
  final types = (i['documentsByType'] as Map).entries.map((e) => '${e.key} ${e.value}').join(' · ');
  return [
    '${i['name']}  (${i['path']})',
    'เอกสาร ${i['documents']}: $types',
    'ตาราง ${i['tables']} · ความสัมพันธ์ ${i['relations']} · endpoint ${i['endpoints']} · ชิ้นส่วน Wireframe ${i['wireframeComponents']} · ความต้องการ ${i['requirements']} · Use Case ${i['useCases']}',
    'ปัญหา: error ${issues['errors']} · warning ${issues['warnings']} · info ${issues['info']}',
  ].join('\n');
}

String _validateText(Map<String, dynamic> r) {
  final b = StringBuffer();
  for (final i in r['issues'] as List) {
    final m = i as Map;
    b.writeln('[${m['severity']}] ${m['document']} (${m['type']}) · ${m['code']}: ${m['title']} — ${m['message']}');
  }
  b.write('สรุป: error ${r['errors']} · warning ${r['warnings']} · info ${r['info']}');
  return b.toString();
}

String _previewText(Map<String, dynamic> p) {
  final b = StringBuffer();
  for (final f in p['files'] as List) {
    b.writeln('${(f as Map)['path']}  (${f['bytes']} ไบต์ · ${f['target']} ← ${f['origin']})');
  }
  for (final w in p['warnings'] as List) {
    b.writeln('คำเตือน: $w');
  }
  b.write('รวม ${(p['files'] as List).length} ไฟล์ (ยังไม่ได้เขียน)');
  return b.toString();
}

String _codegenText(Map<String, dynamic> r) {
  final b = StringBuffer('โฟลเดอร์: ${r['outDir']}\n')
    ..writeln('เขียนแล้ว ${r['written']} ไฟล์ · ไม่เปลี่ยน ${(r['unchanged'] as List).length} ไฟล์');
  for (final p in r['created'] as List) {
    b.writeln('  + $p');
  }
  for (final p in r['overwritten'] as List) {
    b.writeln('  ~ $p');
  }
  for (final p in r['skippedEditedByHand'] as List) {
    b.writeln('  ! ข้าม (ถูกแก้ด้วยมือ) $p');
  }
  for (final w in r['warnings'] as List) {
    b.writeln('คำเตือน: $w');
  }
  return b.toString().trimRight();
}
