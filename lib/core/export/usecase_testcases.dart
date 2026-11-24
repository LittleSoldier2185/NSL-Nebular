import '../l10n/l10n.dart';
import '../models/traceability.dart' show traceLinkLabel;
import '../models/use_case.dart';
import '../models/workspace.dart';
import 'usecase_export.dart';

/// ชนิดของกรณีทดสอบ : flow หลัก · ทางเลือก · ข้อผิดพลาด
enum TcKind { main, alternative, exception }

String tcKindLabel(TcKind k) => switch (k) {
      TcKind.main => tr('หลัก'),
      TcKind.alternative => tr('ทางเลือก'),
      TcKind.exception => tr('ข้อผิดพลาด'),
    };

/// ขั้นตอนหนึ่งของกรณีทดสอบ : [who] = ผู้ใช้ทำ (action) / ระบบ (ผลที่คาดหวัง) ; [isCondition] = บรรทัดเงื่อนไขของทางเลือก
class TcStep {
  const TcStep(this.who, this.text, {this.isCondition = false});
  final UcWho who;
  final String text;
  final bool isCondition;
}

/// สิ่งที่กรณีทดสอบแตะ (จากลิงก์ของขั้นตอน) : ชนิดเอกสาร + ชื่อ
typedef TcRef = ({DocType type, String label});

class TestCase {
  TestCase({
    required this.id,
    required this.ucId,
    required this.ucCode,
    required this.ucName,
    required this.kind,
    required this.title,
    required this.priority,
    required this.precondition,
    required this.steps,
    required this.expected,
    required this.reqCodes,
    required this.refs,
    this.branchLabel,
  });

  final String id;
  final String ucId, ucCode, ucName;
  final TcKind kind;
  final String title;
  final UcPriority priority;
  final String precondition;
  final List<TcStep> steps;

  /// ผลลัพธ์ที่คาดหวังโดยรวม (ผลลัพธ์เมื่อสำเร็จ / ผล + ปลายทางของทางเลือก)
  final String expected;
  final List<String> reqCodes;
  final List<TcRef> refs;

  /// ป้ายของทางเลือก/ข้อผิดพลาด เช่น 2a (null = กรณีหลัก)
  final String? branchLabel;

  List<TcRef> refsOf(DocType t) => [for (final r in refs) if (r.type == t) r];
}

String _line(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
String _stepText(UcStep s) => _line(s.text).isEmpty ? tr('(ยังไม่ได้เขียน)') : _line(s.text);

/// สร้างกรณีทดสอบจาก Use Case ทุกข้อ : 1 กรณีหลัก + 1 กรณีต่อทางเลือก/ข้อผิดพลาดแต่ละข้อ (ที่อ้างขั้นตอนที่ยังมีอยู่)
///
/// กรณีของทางเลือก = ขั้นที่ 1..n-1 ของ flow หลัก + เงื่อนไขที่ขั้น n + ผลที่ระบุ ; ถ้าทางเลือกกลับไปขั้น k ไม่ขยายวงวน
/// เขียนเป็นข้อความ "กลับไปขั้นที่ k แล้วทำต่อจนจบ" ; รหัสไม่ซ้ำกันเสมอ (`TC-<รหัส UC>-<nn>`)
List<TestCase> generateTestCases(Workspace w) {
  final out = <TestCase>[];
  final used = <String>{};
  String uniqueId(String base) {
    var id = base, n = 2;
    while (!used.add(id)) {
      id = '${base}_${n++}';
    }
    return id;
  }

  for (final (ui, u) in w.useCases.indexed) {
    final code = u.code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final prefix = 'TC-${code.isEmpty ? 'UC${ui + 1}' : code}';
    final reqCodes = [
      for (final id in u.reqIds)
        for (final r in w.requirements)
          if (r.id == id) r.code,
    ];
    final name = u.name.trim().isEmpty ? u.code : u.name.trim();
    var seq = 0;

    List<TcRef> refsFor(Iterable<UcStep> steps) {
      final seen = <String>{};
      final refs = <TcRef>[];
      for (final s in steps) {
        for (final l in s.links) {
          final label = traceLinkLabel(w, l);
          final type = w.documentById(l.docId)?.type;
          if (label == null || type == null) continue;
          if (seen.add('${type.name}|$label')) refs.add((type: type, label: label));
        }
      }
      return refs;
    }

    TestCase make(TcKind kind, String title, List<TcStep> steps, String expected, Iterable<UcStep> touched, {String? branchLabel}) {
      seq++;
      return TestCase(
        id: uniqueId('$prefix-${seq.toString().padLeft(2, '0')}'),
        ucId: u.id,
        ucCode: u.code,
        ucName: name,
        kind: kind,
        title: title,
        priority: u.priority,
        precondition: _line(u.preconditions),
        steps: steps,
        expected: expected,
        reqCodes: reqCodes,
        refs: refsFor(touched),
        branchLabel: branchLabel,
      );
    }

    // ---- กรณีหลัก ----
    final mainExpected = _line(u.postconditions).isNotEmpty
        ? _line(u.postconditions)
        : (u.steps.where((s) => s.who == UcWho.system).lastOrNull != null ? _stepText(u.steps.where((s) => s.who == UcWho.system).last) : '');
    out.add(make(
      TcKind.main,
      '$name — ${tr('ขั้นตอนหลัก')}',
      [for (final s in u.steps) TcStep(s.who, _stepText(s))],
      mainExpected,
      u.steps,
    ));

    // ---- ทางเลือก / ข้อผิดพลาด ----
    for (final b in u.branches) {
      final at = b.atStepId == null ? 0 : u.stepNumber(b.atStepId!);
      if (at == 0) continue; // อ้างขั้นตอนที่ไม่มีแล้ว (ตัวตรวจเตือนอยู่)
      final label = u.branchLabel(b);
      final before = u.steps.take(at - 1).toList();
      final outcome = _line(b.outcome);
      final target = ucBranchTarget(u, b);
      final cond = _line(b.condition).isEmpty ? tr('(ยังไม่ระบุเงื่อนไข)') : _line(b.condition);
      final steps = <TcStep>[
        for (final s in before) TcStep(s.who, _stepText(s)),
        TcStep(UcWho.user, tr('ที่ขั้นที่ {0} : เมื่อ {1}', [at, cond]), isCondition: true),
        if (outcome.isNotEmpty) TcStep(UcWho.system, outcome),
        TcStep(UcWho.system, target),
      ];
      final expected = outcome.isEmpty ? target : '$outcome · $target';
      out.add(make(
        b.exception ? TcKind.exception : TcKind.alternative,
        '$name — $label $cond',
        steps,
        expected,
        u.steps.take(at),
        branchLabel: label,
      ));
    }
  }
  return out;
}

/// สรุปกรณีทดสอบ : จำนวนทั้งหมด/ต่อชนิด และความครอบคลุมของความต้องการ (REQ ที่มีกรณีทดสอบอย่างน้อยหนึ่งข้อ)
({int total, int main, int alternative, int exception, int reqCovered, int reqTotal}) testCaseSummary(Workspace w, [List<TestCase>? cases]) {
  final all = cases ?? generateTestCases(w);
  final covered = {for (final c in all) ...c.reqCodes};
  return (
    total: all.length,
    main: all.where((c) => c.kind == TcKind.main).length,
    alternative: all.where((c) => c.kind == TcKind.alternative).length,
    exception: all.where((c) => c.kind == TcKind.exception).length,
    reqCovered: w.requirements.where((r) => covered.contains(r.code)).length,
    reqTotal: w.requirements.length,
  );
}

String _md(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim().replaceAll('|', r'\|');

String _refsText(TestCase c) => [for (final r in c.refs) '${_typeShort(r.type)}: ${r.label}'].join(', ');

String _typeShort(DocType t) => switch (t) {
      DocType.er => 'ER',
      DocType.dfd => 'DFD',
      DocType.flowchart => 'Flowchart',
      DocType.wireframe => 'Wireframe',
      DocType.screenflow => 'Screen Flow',
      DocType.api => 'API',
    };

/// รูปแบบการเขียนกรณีทดสอบเป็น Markdown
enum TcMarkdownStyle { table, givenWhenThen }

/// กรณีทดสอบทั้งโปรเจกต์เป็น Markdown ; [style] = ตาราง (ขั้นตอน/ผลที่คาดหวัง) หรือ Given/When/Then
String exportTestCasesMarkdown(Workspace w, {TcMarkdownStyle style = TcMarkdownStyle.table, List<TestCase>? cases}) {
  final all = cases ?? generateTestCases(w);
  final title = '# ${w.name.trim().isEmpty ? 'project' : w.name.trim()} — ${tr('กรณีทดสอบ')}';
  if (all.isEmpty) return '$title\n\n${tr('ยังไม่มี Use Case จึงยังไม่มีกรณีทดสอบ')}\n';
  final s = testCaseSummary(w, all);
  final b = StringBuffer()
    ..writeln(title)
    ..writeln()
    ..writeln('- ${tr('{0} กรณี : หลัก {1} · ทางเลือก {2} · ข้อผิดพลาด {3}', [s.total, s.main, s.alternative, s.exception])}');
  if (s.reqTotal > 0) b.writeln('- ${tr('ความต้องการที่มีกรณีทดสอบ {0} / {1} ข้อ', [s.reqCovered, s.reqTotal])}');

  final byUc = <String, List<TestCase>>{};
  for (final c in all) {
    byUc.putIfAbsent(c.ucId, () => []).add(c);
  }
  for (final list in byUc.values) {
    final first = list.first;
    b
      ..writeln()
      ..writeln('## ${first.ucCode} ${first.ucName}');
    if (style == TcMarkdownStyle.table) {
      b
        ..writeln()
        ..writeln('| ${tr('รหัส')} | ${tr('ประเภท')} | ${tr('เงื่อนไขก่อนเริ่ม')} | ${tr('ขั้นตอน')} | ${tr('ผลที่คาดหวัง')} | ${tr('อ้างอิง')} |')
        ..writeln('|---|---|---|---|---|---|');
      for (final c in list) {
        final steps = [
          for (final (i, st) in c.steps.indexed) '${i + 1}. [${ucWhoLabel(st.who)}] ${_md(st.text)}',
        ].join('<br>');
        final refs = [if (c.reqCodes.isNotEmpty) c.reqCodes.join(', '), if (c.refs.isNotEmpty) _refsText(c)].join(' · ');
        b.writeln('| ${c.id} | ${tcKindLabel(c.kind)}${c.branchLabel == null ? '' : ' ${c.branchLabel}'} | ${_md(c.precondition)} | $steps | ${_md(c.expected)} | ${_md(refs)} |');
      }
    } else {
      for (final c in list) {
        b
          ..writeln()
          ..writeln('### ${c.id} ${c.title}')
          ..writeln()
          ..writeln('- **${tr('ประเภท')}:** ${tcKindLabel(c.kind)} · **${tr('ความสำคัญ')}:** ${ucPriorityLabel(c.priority)}${c.reqCodes.isEmpty ? '' : ' · ${c.reqCodes.join(', ')}'}');
        if (c.refs.isNotEmpty) b.writeln('- **${tr('อ้างอิง')}:** ${_refsText(c)}');
        b.writeln();
        b.writeln('**Given** ${c.precondition.isEmpty ? tr('(ไม่มีเงื่อนไขก่อนเริ่ม)') : c.precondition}');
        for (final st in c.steps) {
          final kw = st.isCondition ? 'When' : (st.who == UcWho.user ? 'When' : 'Then');
          b.writeln('- **$kw** ${st.text}');
        }
        b.writeln('- **Then** ${c.expected.isEmpty ? tr('(ยังไม่ระบุผลลัพธ์)') : c.expected}');
      }
    }
  }
  return b.toString();
}

/// ตัวคั่นฟิลด์ CSV : ครอบด้วย " เมื่อมี , " หรือขึ้นบรรทัดใหม่ และเติม " ซ้ำ
String _csv(String s) => RegExp(r'[",\r\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;

/// กรณีทดสอบเป็น CSV (UTF-8 พร้อม BOM ให้ Excel อ่านภาษาไทยถูก ; บรรทัดจบด้วย CRLF) — ขั้นตอนคั่นด้วยการขึ้นบรรทัดใหม่ในเซลล์
String exportTestCasesCsv(Workspace w, {List<TestCase>? cases}) {
  final all = cases ?? generateTestCases(w);
  final header = [
    tr('รหัส'),
    'Use Case',
    tr('ประเภท'),
    tr('ชื่อกรณีทดสอบ'),
    tr('ความสำคัญ'),
    tr('เงื่อนไขก่อนเริ่ม'),
    tr('ขั้นตอน'),
    tr('ผลที่คาดหวัง'),
    tr('ความต้องการ'),
    tr('อ้างอิง'),
  ];
  final b = StringBuffer('﻿')..write('${header.map(_csv).join(',')}\r\n');
  for (final c in all) {
    final row = [
      c.id,
      '${c.ucCode} ${c.ucName}',
      '${tcKindLabel(c.kind)}${c.branchLabel == null ? '' : ' ${c.branchLabel}'}',
      c.title,
      ucPriorityLabel(c.priority),
      c.precondition,
      [for (final (i, st) in c.steps.indexed) '${i + 1}. [${ucWhoLabel(st.who)}] ${st.text}'].join('\n'),
      c.expected,
      c.reqCodes.join(', '),
      _refsText(c),
    ];
    b.write('${row.map(_csv).join(',')}\r\n');
  }
  return b.toString();
}
