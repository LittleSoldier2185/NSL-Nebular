import '../l10n/l10n.dart';
import '../models/requirement.dart';
import '../models/traceability.dart';
import '../models/workspace.dart';

String _priority(ReqPriority p) => switch (p) {
      ReqPriority.high => tr('สูง@@priority'),
      ReqPriority.medium => tr('กลาง@@priority'),
      ReqPriority.low => tr('ต่ำ'),
    };

String _col(DocType t) => switch (t) {
      DocType.er => 'ER',
      DocType.dfd => 'DFD',
      DocType.flowchart => 'Flowchart',
      DocType.wireframe => 'Wireframe',
      DocType.screenflow => 'Screen Flow',
      DocType.api => 'API',
    };

String _cellText(Workspace w, Requirement r, DocType t) => switch (traceStatus(w, r, t)) {
      TraceStatus.covered => [for (final l in validLinks(w, r, t)) traceLinkLabel(w, l) ?? '?'].join(', '),
      TraceStatus.notNeeded => tr('ไม่จำเป็น'),
      TraceStatus.missing => tr('ยังไม่มี'),
    };

String _md(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim().replaceAll('|', r'\|');

/// ตารางความต้องการ × เอกสาร แบบ Markdown (หัวข้อระดับ [level]) ; ไม่มีความต้องการ = ''
String traceMarkdownSection(Workspace w, {int level = 2}) {
  if (w.requirements.isEmpty) return '';
  final s = traceSummary(w);
  final h = '#' * level;
  final b = StringBuffer()
    ..writeln()
    ..writeln('$h ${tr('ความต้องการและการไล่ตาม')}')
    ..writeln()
    ..writeln('- ${tr('ครอบคลุมครบ {0} / {1} ข้อ', [s.covered, s.total])}')
    ..writeln('- ${tr('ยังไม่มีหน้าจอ {0} · ยังไม่มี API {1}', [s.missingScreens, s.missingApi])}')
    ..writeln()
    ..writeln('| ${tr('รหัส')} | ${tr('ความต้องการ')} | ${tr('ความสำคัญ')} | ${kTraceColumns.map(_col).join(' | ')} |')
    ..writeln('|${List.filled(3 + kTraceColumns.length, '---').join('|')}|');
  for (final r in w.requirements) {
    b.writeln('| ${_md(r.code)} | ${_md(r.text)} | ${_priority(r.priority)} | ${[for (final t in kTraceColumns) _md(_cellText(w, r, t))].join(' | ')} |');
  }
  return b.toString();
}

/// เอกสารสเปก (Markdown) ของความต้องการทั้งโปรเจกต์
String exportTraceMarkdown(Workspace w) =>
    '# ${w.name.trim().isEmpty ? 'project' : w.name.trim()} — ${tr('ความต้องการ')}\n${traceMarkdownSection(w)}';

/// ส่วนความต้องการแบบ HTML ([esc] = ฟังก์ชัน escape ของผู้เรียก) ; ไม่มีความต้องการ = ''
String traceHtmlSection(Workspace w, String Function(String) esc) {
  if (w.requirements.isEmpty) return '';
  final s = traceSummary(w);
  final b = StringBuffer()
    ..writeln('<section class="group" id="requirements">')
    ..writeln('<h2>${esc(tr('ความต้องการและการไล่ตาม'))}</h2>')
    ..writeln('<p class="meta">${esc(tr('ครอบคลุมครบ {0} / {1} ข้อ', [s.covered, s.total]))}</p>')
    ..write('<table><thead><tr><th>${esc(tr('รหัส'))}</th><th>${esc(tr('ความต้องการ'))}</th><th>${esc(tr('ความสำคัญ'))}</th>');
  for (final t in kTraceColumns) {
    b.write('<th>${esc(_col(t))}</th>');
  }
  b.writeln('</tr></thead><tbody>');
  for (final r in w.requirements) {
    b.write('<tr><td>${esc(r.code)}</td><td>${esc(r.text)}</td><td>${esc(_priority(r.priority))}</td>');
    for (final t in kTraceColumns) {
      final missing = traceStatus(w, r, t) == TraceStatus.missing;
      b.write(missing ? '<td class="muted"><em>${esc(_cellText(w, r, t))}</em></td>' : '<td>${esc(_cellText(w, r, t))}</td>');
    }
    b.writeln('</tr>');
  }
  b
    ..writeln('</tbody></table>')
    ..writeln('</section>');
  return b.toString();
}
