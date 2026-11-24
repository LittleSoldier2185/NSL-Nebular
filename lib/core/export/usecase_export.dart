import '../l10n/l10n.dart';
import '../models/use_case.dart';
import '../models/traceability.dart' show traceLinkLabel;
import '../models/workspace.dart';

String ucStatusLabel(UcStatus s) => switch (s) {
      UcStatus.draft => tr('ร่าง'),
      UcStatus.review => tr('รอตรวจ'),
      UcStatus.approved => tr('อนุมัติ'),
    };

String ucPriorityLabel(UcPriority p) => switch (p) {
      UcPriority.high => tr('สูง@@priority'),
      UcPriority.medium => tr('กลาง@@priority'),
      UcPriority.low => tr('ต่ำ'),
    };

String ucWhoLabel(UcWho w) => w == UcWho.user ? tr('ผู้ใช้') : tr('ระบบ');

/// ข้อความขั้นตอน [id] ของ [u] แบบ "ขั้นที่ n" ; ไม่พบ = "?"
String ucStepRef(UseCase u, String? id) {
  final n = id == null ? 0 : u.stepNumber(id);
  return n == 0 ? '?' : tr('ขั้นที่ {0}', [n]);
}

/// ป้ายผลของทางเลือก: จบ / กลับไปขั้นที่ n / (ยังไม่ระบุ)
String ucBranchTarget(UseCase u, UcBranch b) {
  if (b.returnStepId != null) return tr('กลับไป{0}', [ucStepRef(u, b.returnStepId)]);
  return b.ends ? tr('จบ Use Case') : tr('(ยังไม่ระบุ)');
}

String _line(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Use Case เดียวแบบ Markdown (หัวข้อระดับ [level])
String useCaseMarkdown(Workspace w, UseCase u, {int level = 2}) {
  final h = '#' * level;
  final reqs = [
    for (final id in u.reqIds)
      for (final r in w.requirements)
        if (r.id == id) r.code,
  ];
  final b = StringBuffer()
    ..writeln('$h ${u.code} ${u.name.trim().isEmpty ? tr('(ไม่มีชื่อ)') : u.name.trim()}')
    ..writeln()
    ..writeln('- **${tr('ผู้กระทำหลัก')}:** ${u.actor.trim().isEmpty ? '-' : u.actor.trim()}')
    ..writeln('- **${tr('ผู้กระทำรอง')}:** ${u.secondaryActors.isEmpty ? '-' : u.secondaryActors.join(', ')}')
    ..writeln('- **${tr('สถานะ')}:** ${ucStatusLabel(u.status)} · **${tr('ความสำคัญ')}:** ${ucPriorityLabel(u.priority)}')
    ..writeln('- **${tr('ความต้องการ')}:** ${reqs.isEmpty ? '-' : reqs.join(', ')}');
  void para(String label, String v) {
    if (v.trim().isEmpty) return;
    b
      ..writeln()
      ..writeln('**$label:** ${_line(v)}');
  }

  para(tr('เป้าหมาย'), u.goal);
  para(tr('ตัวเริ่มต้น'), u.trigger);
  para(tr('เงื่อนไขก่อนเริ่ม'), u.preconditions);
  if (u.steps.isNotEmpty) {
    b
      ..writeln()
      ..writeln('**${tr('ขั้นตอนหลัก')}**')
      ..writeln();
    for (final (i, s) in u.steps.indexed) {
      final links = [for (final l in s.links) traceLinkLabel(w, l) ?? tr('(ลิงก์ที่ขาด)')];
      b.writeln('${i + 1}. [${ucWhoLabel(s.who)}] ${_line(s.text)}${links.isEmpty ? '' : ' — ${links.join(', ')}'}');
    }
  }
  final alts = [for (final x in u.branches) if (!x.exception) x], exs = [for (final x in u.branches) if (x.exception) x];
  void branchList(String label, List<UcBranch> list) {
    if (list.isEmpty) return;
    b
      ..writeln()
      ..writeln('**$label**')
      ..writeln();
    for (final x in list) {
      b.writeln('- ${u.branchLabel(x)} ${_line(x.condition)} → ${_line(x.outcome).isEmpty ? '' : '${_line(x.outcome)} · '}${ucBranchTarget(u, x)}');
    }
  }

  branchList(tr('ทางเลือก'), alts);
  branchList(tr('ข้อผิดพลาด'), exs);
  para(tr('ผลลัพธ์เมื่อสำเร็จ'), u.postconditions);
  final inc = [
    for (final id in u.includes)
      for (final o in w.useCases)
        if (o.id == id) '${o.code} ${o.name.trim()}',
  ];
  if (inc.isNotEmpty) para(tr('เรียกใช้ Use Case'), inc.join(', '));
  return b.toString();
}

/// เอกสาร Use Case ทั้งโปรเจกต์ (Markdown) ; ไม่มี Use Case = หัวเรื่องกับบรรทัดบอกว่าว่าง
String exportUseCaseMarkdown(Workspace w) {
  final title = '# ${w.name.trim().isEmpty ? 'project' : w.name.trim()} — Use Case';
  if (w.useCases.isEmpty) return '$title\n\n${tr('ยังไม่มี Use Case')}\n';
  final steps = w.useCases.fold<int>(0, (a, u) => a + u.steps.length);
  final b = StringBuffer()
    ..writeln(title)
    ..writeln()
    ..writeln('- ${tr('{0} Use Case · {1} ขั้นตอน', [w.useCases.length, steps])}');
  for (final u in w.useCases) {
    b
      ..writeln()
      ..write(useCaseMarkdown(w, u));
  }
  return b.toString();
}

/// ส่วน Use Case สำหรับ "ส่งออกทั้งโปรเจกต์" (Markdown) — หัวข้อระดับ [level] ; ไม่มี Use Case = ''
String useCaseMarkdownSection(Workspace w, {int level = 2}) {
  if (w.useCases.isEmpty) return '';
  final steps = w.useCases.fold<int>(0, (a, u) => a + u.steps.length);
  final b = StringBuffer()
    ..writeln()
    ..writeln('${'#' * level} Use Case')
    ..writeln()
    ..writeln('- ${tr('{0} Use Case · {1} ขั้นตอน', [w.useCases.length, steps])}');
  for (final u in w.useCases) {
    b
      ..writeln()
      ..write(useCaseMarkdown(w, u, level: level + 1));
  }
  return b.toString();
}

/// ส่วน Use Case แบบ HTML ([esc] = ฟังก์ชัน escape ของผู้เรียก) ; ไม่มี Use Case = ''
String useCaseHtmlSection(Workspace w, String Function(String) esc) {
  if (w.useCases.isEmpty) return '';
  final b = StringBuffer()
    ..writeln('<section class="group" id="usecases">')
    ..writeln('<h2>Use Case</h2>');
  for (final u in w.useCases) {
    final reqs = [
      for (final id in u.reqIds)
        for (final r in w.requirements)
          if (r.id == id) r.code,
    ];
    b
      ..writeln('<h3>${esc(u.code)} ${esc(u.name.trim().isEmpty ? tr('(ไม่มีชื่อ)') : u.name.trim())}</h3>')
      ..writeln('<p class="meta">${esc(tr('ผู้กระทำหลัก'))}: ${esc(u.actor.trim().isEmpty ? '-' : u.actor.trim())}'
          '${u.secondaryActors.isEmpty ? '' : ' + ${esc(u.secondaryActors.join(', '))}'}'
          ' · ${esc(ucStatusLabel(u.status))} · ${esc(tr('ความสำคัญ'))}: ${esc(ucPriorityLabel(u.priority))}'
          '${reqs.isEmpty ? '' : ' · ${esc(reqs.join(', '))}'}</p>');
    void para(String label, String v) {
      if (v.trim().isNotEmpty) b.writeln('<p><strong>${esc(label)}:</strong> ${esc(_line(v))}</p>');
    }

    para(tr('เป้าหมาย'), u.goal);
    para(tr('ตัวเริ่มต้น'), u.trigger);
    para(tr('เงื่อนไขก่อนเริ่ม'), u.preconditions);
    if (u.steps.isNotEmpty) {
      b.writeln('<ol>');
      for (final s in u.steps) {
        final links = [for (final l in s.links) traceLinkLabel(w, l) ?? tr('(ลิงก์ที่ขาด)')];
        b.writeln('<li>[${esc(ucWhoLabel(s.who))}] ${esc(_line(s.text))}${links.isEmpty ? '' : ' — ${esc(links.join(', '))}'}</li>');
      }
      b.writeln('</ol>');
    }
    if (u.branches.isNotEmpty) {
      b.writeln('<ul>');
      for (final x in u.branches) {
        b.writeln('<li><strong>${esc(u.branchLabel(x))}</strong> ${esc(_line(x.condition))} → '
            '${_line(x.outcome).isEmpty ? '' : '${esc(_line(x.outcome))} · '}${esc(ucBranchTarget(u, x))}</li>');
      }
      b.writeln('</ul>');
    }
    para(tr('ผลลัพธ์เมื่อสำเร็จ'), u.postconditions);
  }
  b.writeln('</section>');
  return b.toString();
}
