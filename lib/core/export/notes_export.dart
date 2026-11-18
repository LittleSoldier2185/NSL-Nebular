import '../l10n/l10n.dart';
import '../models/review_note.dart';
import '../models/review_note_refs.dart';
import '../models/workspace.dart';

/// โน้ตทั้งโปรเจกต์สำหรับส่งออก: เอกสารที่รู้จักชนิดและมีโน้ต ตามลำดับเอกสารในไฟล์ (โน้ตตามลำดับที่เพิ่ม)
List<ProjectDocument> docsWithNotes(Workspace w) => [
      for (final d in w.documents)
        if (d.type != null && d.reviewNotes.isNotEmpty) d,
    ];

String _typeName(DocType t) => switch (t) {
      DocType.er => 'ER',
      DocType.dfd => 'DFD',
      DocType.flowchart => 'Flowchart',
      DocType.wireframe => 'Wireframe',
      DocType.screenflow => 'Screen Flow',
    };

/// รายละเอียดท้ายโน้ต: (ชนิด · หมุด n · วัตถุ)
String _detail(ProjectDocument d, ReviewNote n) {
  var pin = 0, i = 0;
  for (final x in d.reviewNotes) {
    if (!x.pinned) continue;
    i++;
    if (x.id == n.id) pin = i;
  }
  final anchor = noteAnchorLabel(d, n.anchorId);
  return [
    noteKindLabel(n.kind),
    if (pin > 0) tr('หมุด {0}', [pin]),
    ?anchor,
  ].join(' · ');
}

String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// ส่วน "โน้ตและงานค้าง" แบบ Markdown (ขึ้นต้นด้วยบรรทัดว่าง) ; ไม่มีโน้ต = ''
String notesMarkdown(Workspace w) {
  final docs = docsWithNotes(w);
  if (docs.isEmpty) return '';
  final open = docs.fold<int>(0, (a, d) => a + d.reviewNotes.where((n) => n.open).length);
  final b = StringBuffer()
    ..writeln()
    ..writeln(tr('## โน้ตและงานค้าง'))
    ..writeln()
    ..writeln('- ${tr('ค้างอยู่ {0} รายการ', [open])}');
  for (final d in docs) {
    b
      ..writeln()
      ..writeln('### ${_typeName(d.type!)}: ${_oneLine(d.name)}')
      ..writeln();
    for (final n in d.reviewNotes) {
      final box = n.kind == NoteKind.memo ? '-' : (n.done ? '- [x]' : '- [ ]');
      b.writeln('$box ${_oneLine(n.text)} _(${_detail(d, n)})_');
    }
  }
  return b.toString();
}

/// ส่วน "โน้ตและงานค้าง" แบบ HTML ([esc] = ฟังก์ชัน escape ของผู้เรียก) ; ไม่มีโน้ต = ''
String notesHtml(Workspace w, String Function(String) esc) {
  final docs = docsWithNotes(w);
  if (docs.isEmpty) return '';
  final open = docs.fold<int>(0, (a, d) => a + d.reviewNotes.where((n) => n.open).length);
  final b = StringBuffer()
    ..writeln('<section class="group" id="review-notes">')
    ..writeln('<h2>${esc(tr('โน้ตและงานค้าง'))}</h2>')
    ..writeln('<p class="meta">${esc(tr('ค้างอยู่ {0} รายการ', [open]))}</p>');
  for (final d in docs) {
    b
      ..writeln('<h3>${esc('${_typeName(d.type!)}: ${d.name}')}</h3>')
      ..writeln('<ul>');
    for (final n in d.reviewNotes) {
      final mark = n.kind == NoteKind.memo ? '' : (n.done ? '☑ ' : '☐ ');
      final text = esc('$mark${_oneLine(n.text)}');
      b.writeln('<li>${n.done ? '<s>$text</s>' : text} <span class="muted">(${esc(_detail(d, n))})</span></li>');
    }
    b.writeln('</ul>');
  }
  b.writeln('</section>');
  return b.toString();
}
