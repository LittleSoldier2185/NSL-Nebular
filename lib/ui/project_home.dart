import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/l10n.dart';
import '../core/models/dfd_model.dart';
import '../core/models/flowchart_model.dart';
import '../core/models/workspace.dart';
import '../core/validate/issue.dart';
import '../core/validate/workspace_validator.dart';
import '../state/workspace_controller.dart';
import 'activity_rail.dart';
import 'app_actions.dart';
import 'document_actions.dart' show DocTypeDot;
import 'shortcuts.dart';
import 'start_page.dart' show relativeTimeLabel;
import 'theme.dart';
import 'workspace_issues_dialog.dart';

typedef _DocIssues = ({int errors, int warnings});

/// ชื่อชนิดเอกสารบนการ์ดของหน้า Home (ตามดีไซน์ — เป็นชื่อเฉพาะ ไม่แปล)
String homeTypeLabel(DocType t) => switch (t) {
      DocType.er => 'ER Diagram',
      DocType.dfd => 'Data Flow',
      DocType.flowchart => 'Flowchart',
      DocType.wireframe => 'Wireframe',
      DocType.screenflow => 'Screen Flow',
      DocType.api => 'API',
    };

String _menuLabel(DocType t) => switch (t) {
      DocType.er => tr('ER Diagram (ตารางฐานข้อมูล)'),
      DocType.dfd => tr('DFD (Data Flow Diagram)'),
      DocType.flowchart => tr('Flowchart (ผังงาน)'),
      DocType.wireframe => tr('Wireframe (หน้าจอ)'),
      DocType.screenflow => tr('Screen Flow (ลำดับหน้าจอ)'),
      DocType.api => tr('API (Endpoint)'),
    };

/// บรรทัดสรุปของการ์ดชนิดเอกสาร (รวมทุกเอกสารชนิดนั้น)
@visibleForTesting
String homeTypeDetail(DocType t, List<ProjectDocument> docs) {
  if (docs.isEmpty) return tr('ยังไม่มีเอกสารชนิดนี้');
  int sum(int Function(ProjectDocument d) f) => docs.fold(0, (a, d) => a + f(d));
  return switch (t) {
    DocType.er => tr('{0} ตาราง · {1} ความสัมพันธ์', [sum((d) => d.er!.tables.length), sum((d) => d.er!.relations.length)]),
    DocType.dfd => tr('{0} กระบวนการ · {1} คลังข้อมูล', [
        sum((d) => d.dfd!.nodes.where((n) => n.kind == DfdKind.process).length),
        sum((d) => d.dfd!.nodes.where((n) => n.kind == DfdKind.store).length),
      ]),
    DocType.flowchart => tr('{0} สัญลักษณ์ · {1} จุดตัดสินใจ', [
        sum((d) => d.flowchart!.nodes.length),
        sum((d) => d.flowchart!.nodes.where((n) => n.shape == FcShape.decision).length),
      ]),
    DocType.wireframe => tr('{0} ชิ้นส่วน · ผูกกับ ER {1} จุด', [
        sum((d) => d.wireframe!.components.length),
        sum((d) => d.wireframe!.components.where((c) => c.ref != null).length),
      ]),
    DocType.screenflow => tr('{0} หน้าจอ · {1} เส้นทาง', [sum((d) => d.screenflow!.nodes.length), sum((d) => d.screenflow!.edges.length)]),
    DocType.api => tr('{0} endpoint · ผูกกับตาราง {1}', [
        sum((d) => d.api!.endpoints.length),
        sum((d) => d.api!.endpoints.where((e) => e.table != null).length),
      ]),
  };
}

/// หน้า Project Home (Artboard `Home` ใน design/): ภาพรวมทั้งโปรเจกต์ — แสดงแทนแคนวาสขณะ [WorkspaceController.homeView]
/// หัว (ชื่อ · จำนวนเอกสาร · บันทึกล่าสุด · ไฟล์ + ส่งออก/เอกสารใหม่) → การ์ดรายชนิด → เอกสารล่าสุด + ปัญหาข้ามเอกสาร
class ProjectHomeView extends StatelessWidget {
  const ProjectHomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    final all = w.workspaceIssues;
    final perDoc = <String, _DocIssues>{};
    for (final i in all) {
      final cur = perDoc[i.docId] ?? (errors: 0, warnings: 0);
      if (i.issue.severity == Severity.error) {
        perDoc[i.docId] = (errors: cur.errors + 1, warnings: cur.warnings);
      } else if (i.issue.severity == Severity.warning) {
        perDoc[i.docId] = (errors: cur.errors, warnings: cur.warnings + 1);
      }
    }
    final cross = crossDocIssues(all);
    final n = countIssues(all.map((x) => x.issue));

    return Container(
      key: const ValueKey('project-home'),
      color: C.bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _Header(w: w),
              const SizedBox(height: 28),
              _TypeCards(w: w),
              const SizedBox(height: 28),
              LayoutBuilder(builder: (context, c) {
                final recent = _RecentPanel(w: w, perDoc: perDoc);
                final issues = _CrossPanel(issues: cross, errors: n.errors, warnings: n.warnings);
                if (c.maxWidth < 760) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [recent, const SizedBox(height: 20), issues]);
                }
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 64, child: recent),
                  const SizedBox(width: 20),
                  Expanded(flex: 36, child: issues),
                ]);
              }),
            ]),
          ),
        ),
      ),
    );
  }
}

/// เวลาแก้ไขไฟล์บนดิสก์ (null = ยังไม่มีไฟล์ หรืออ่านไม่ได้)
DateTime? _fileTime(String? path) {
  if (path == null) return null;
  try {
    final f = File(path);
    return f.existsSync() ? f.lastModifiedSync() : null;
  } catch (_) {
    return null;
  }
}

String _baseName(String path) {
  final parts = path.split(RegExp(r'[\\/]'));
  return parts.isEmpty ? path : parts.last;
}

class _Header extends StatelessWidget {
  const _Header({required this.w});
  final WorkspaceController w;

  @override
  Widget build(BuildContext context) {
    final path = w.filePath;
    final name = w.workspace.name.trim().isEmpty ? tr('(ไม่มีชื่อ)') : w.workspace.name;
    final known = w.documents.where((d) => d.type != null).length;
    final saved = _fileTime(path);
    final meta = TextStyle(fontSize: 13.5, color: C.muted);
    final title = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('โปรเจกต์'), style: TextStyle(fontSize: 12, color: C.muted, letterSpacing: 0.5)),
      const SizedBox(height: 2),
      Text(name,
          key: const ValueKey('home-name'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 30, height: 1.2, fontWeight: FontWeight.w700, color: C.text)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(tr('{0} เอกสาร', [known]), key: const ValueKey('home-doc-count'), style: meta),
        if (saved != null) ...[
          Text('·', style: meta),
          Text(tr('บันทึกล่าสุด {0}', [relativeTimeLabel(saved, DateTime.now())]), style: meta),
        ],
        Text('·', style: meta),
        Tooltip(
          message: path ?? '',
          child: Text(path == null ? tr('ยังไม่ได้บันทึกเป็นไฟล์') : _baseName(path), key: const ValueKey('home-path'), style: meta),
        ),
        if (w.dirty) ...[
          Text('·', style: meta),
          Text(tr('● ยังไม่ได้บันทึก'),
              key: const ValueKey('home-dirty'), style: TextStyle(fontSize: 13.5, color: C.warnText, fontWeight: FontWeight.w600)),
        ],
      ]),
    ]);
    // ปุ่มหลัก 2 ปุ่ม (ส่งออก, เอกสารใหม่) ; เครื่องมือของโปรเจกต์เป็นแถวเล็กใต้ชื่อ (แบบ A ของ `design/project-home`)
    final primary = Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.end, children: [
      _HomeButton(
        key: const ValueKey('home-export'),
        icon: Icons.ios_share_rounded,
        label: tr('ส่งออกทั้งโปรเจกต์'),
        onPressed: () => AppActions(context).run(Cmd.exportText),
      ),
      _NewDocButton(w: w),
    ]);
    final tools = Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(tr('เครื่องมือของโปรเจกต์'), style: TextStyle(fontSize: 12, color: C.muted, letterSpacing: 0.4)),
      _HomeButton(key: const ValueKey('home-dictionary'), small: true, icon: Icons.menu_book_outlined, label: tr('พจนานุกรมข้อมูล'), onPressed: w.showDictionary),
      _HomeButton(key: const ValueKey('home-history'), small: true, icon: Icons.history_rounded, label: tr('ประวัติเวอร์ชัน'), onPressed: w.showHistory),
      _HomeButton(key: const ValueKey('home-trace'), small: true, icon: Icons.checklist_rounded, label: tr('ความต้องการ'), onPressed: w.showTrace),
      _HomeButton(key: const ValueKey('home-usecase'), small: true, icon: Icons.account_tree_outlined, label: 'Use Case', onPressed: w.showUseCases),
      _HomeButton(key: const ValueKey('home-codegen'), small: true, icon: Icons.code_rounded, label: tr('สร้างโค้ด'), onPressed: w.showCodegen),
      _HomeButton(key: const ValueKey('home-mock'), small: true, icon: Icons.dns_outlined, label: tr('Mock Server'), onPressed: w.showMock),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 700) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 12), primary]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: title),
          const SizedBox(width: 16),
          primary,
        ]);
      }),
      const SizedBox(height: 16),
      tools,
    ]);
  }
}

/// ปุ่มขอบบางของหัวหน้า Home : [small] = ปุ่มเครื่องมือในแถวเล็ก, ไม่ใช่ = ปุ่มหลัก
class _HomeButton extends StatelessWidget {
  const _HomeButton({super.key, required this.icon, required this.label, required this.onPressed, this.small = false});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool small;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: small ? 15 : 17),
        label: Text(label, style: TextStyle(fontSize: small ? 12.5 : 13, fontWeight: small ? FontWeight.w500 : FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap, // ไม่ขยายพื้นที่กดเป็น 48 : แถวเครื่องมือเตี้ยกว่าปุ่มหลักจริง
          minimumSize: Size(0, small ? 32 : 38),
          padding: EdgeInsets.symmetric(horizontal: small ? 10 : 16),
          foregroundColor: C.text,
          backgroundColor: C.surface,
          side: BorderSide(color: C.inputBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(small ? 8 : 10)),
        ),
      );
}

class _NewDocButton extends StatelessWidget {
  const _NewDocButton({required this.w});
  final WorkspaceController w;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final t in DocType.values)
          MenuItemButton(
            key: ValueKey('home-add-${t.name}'),
            leadingIcon: DocTypeDot(t),
            onPressed: () => w.addDocument(t),
            child: Text(_menuLabel(t), style: const TextStyle(fontSize: 13)),
          ),
      ],
      builder: (context, ctl, _) => FilledButton(
        key: const ValueKey('home-new'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          backgroundColor: C.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: () => ctl.isOpen ? ctl.close() : ctl.open(),
        child: Text(tr('+ เอกสารใหม่'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _TypeCards extends StatelessWidget {
  const _TypeCards({required this.w});
  final WorkspaceController w;

  static const _gap = 14.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const types = DocType.values;
      // ขั้นต่ำ 160 (ดีไซน์ 190 สำหรับ 5 ชนิด — มี API เพิ่มเป็น 6 ชนิดแล้วยังอยู่แถวเดียวบนจอกว้าง)
      final cols = ((c.maxWidth + _gap) / (160 + _gap)).floor().clamp(1, types.length);
      final cardW = (c.maxWidth - _gap * (cols - 1)) / cols;
      return Wrap(spacing: _gap, runSpacing: _gap, children: [
        for (final t in types)
          SizedBox(width: cardW, child: _TypeCard(type: t, docs: [for (final d in w.documents) if (d.type == t) d], w: w)),
      ]);
    });
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({required this.type, required this.docs, required this.w});
  final DocType type;
  final List<ProjectDocument> docs;
  final WorkspaceController w;

  @override
  Widget build(BuildContext context) {
    final col = C.doc(type);
    final empty = docs.isEmpty;
    return Container(
      key: ValueKey('home-type-${type.name}'),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 4, color: col.main),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              DocTypeDot(type),
              const SizedBox(width: 8),
              Expanded(
                child: Text(homeTypeLabel(type),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: col.ink)),
              ),
            ]),
            const SizedBox(height: 10),
            Text('${docs.length}',
                key: ValueKey('home-type-count-${type.name}'),
                style: TextStyle(fontSize: 28, height: 1, fontWeight: FontWeight.w700, color: empty ? C.muted : C.text)),
            const SizedBox(height: 10),
            // สูงคงที่ 2 บรรทัด : การ์ดทุกใบสูงเท่ากันและปุ่มอยู่ระดับเดียวกัน ไม่ว่าสรุปจะยาวกี่บรรทัด
            SizedBox(
              height: 38,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(homeTypeDetail(type, docs),
                    key: ValueKey('home-type-detail-${type.name}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: C.muted)),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: ValueKey('home-type-open-${type.name}'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: col.ink,
                backgroundColor: C.surface,
                side: BorderSide(color: C.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => ActivityRail.go(w, type),
              child: Text(empty ? tr('สร้าง') : tr('เปิด'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// กรอบแผงของหน้า Home (หัว + รายการ)
class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.title, this.trailing, required this.children});
  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, thickness: 1, color: C.borderSoft));
      rows.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.border))),
          child: Row(children: [
            Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: C.text))),
            ?trailing,
          ]),
        ),
        ...rows,
      ]),
    );
  }
}

/// โปรเจกต์ที่มีเอกสารเกินนี้ : ที่ยังไม่เคยเปิดพับเก็บ (เล็กกว่านี้แสดงครบ)
const int kHomeCollapseUnopenedOver = 8;

class _RecentPanel extends StatefulWidget {
  const _RecentPanel({required this.w, required this.perDoc});
  final WorkspaceController w;
  final Map<String, _DocIssues> perDoc;

  @override
  State<_RecentPanel> createState() => _RecentPanelState();
}

class _RecentPanelState extends State<_RecentPanel> {
  bool _showUnopened = false;

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final docs = w.recentDocuments;
    final now = DateTime.now();
    final opened = [for (final d in docs) if (w.openedAt(d.id) != null) d];
    final unopened = [for (final d in docs) if (w.openedAt(d.id) == null) d];
    // พับเฉพาะโปรเจกต์ใหญ่ และต้องมีที่เคยเปิดอย่างน้อย 1 ชิ้น (ไม่งั้นรายการจะว่างเปล่า)
    final collapse = docs.length > kHomeCollapseUnopenedOver && opened.isNotEmpty && unopened.isNotEmpty;
    Widget row(ProjectDocument d) =>
        _RecentRow(doc: d, issues: widget.perDoc[d.id], opened: w.openedAt(d.id), now: now, onOpen: () => w.openDocument(d.id));
    return _Panel(
      key: const ValueKey('home-recent'),
      title: tr('เอกสารล่าสุด'),
      children: [
        for (final d in collapse ? opened : docs) row(d),
        if (collapse) ...[
          InkWell(
            key: const ValueKey('home-unopened-toggle'),
            onTap: () => setState(() => _showUnopened = !_showUnopened),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Row(children: [
                Expanded(
                  child: Text(
                    _showUnopened ? tr('ซ่อนเอกสารที่ยังไม่เคยเปิด') : tr('ยังไม่เคยเปิดอีก {0} เอกสาร', [unopened.length]),
                    style: TextStyle(fontSize: 12.5, color: C.muted),
                  ),
                ),
                Icon(_showUnopened ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: C.muted),
              ]),
            ),
          ),
          if (_showUnopened) for (final d in unopened) row(d),
        ],
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.doc, required this.issues, required this.opened, required this.now, required this.onOpen});
  final ProjectDocument doc;
  final _DocIssues? issues;
  final DateTime? opened;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final iss = issues;
    final total = iss == null ? 0 : iss.errors + iss.warnings;
    return InkWell(
      key: ValueKey('home-card-${doc.id}'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        child: Row(children: [
          DocTypeDot(doc.type),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${homeTypeLabel(doc.type!)} · ', style: TextStyle(color: C.muted)),
                TextSpan(text: doc.name),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: C.text),
            ),
          ),
          if (total > 0) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: tr('{0} ข้อผิดพลาด · {1} คำเตือน', [iss!.errors, iss.warnings]),
              child: Container(
                key: ValueKey('home-issues-${doc.id}'),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: iss.errors > 0 ? C.dangerBg : C.warnBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$total',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: iss.errors > 0 ? C.dangerText : C.warnText)),
              ),
            ),
          ],
          const SizedBox(width: 12),
          Text(opened == null ? tr('ยังไม่ได้เปิด') : relativeTimeLabel(opened!, now),
              style: TextStyle(fontSize: 12, color: C.muted)),
        ]),
      ),
    );
  }
}

class _CrossPanel extends StatelessWidget {
  const _CrossPanel({required this.issues, required this.errors, required this.warnings});
  final List<WorkspaceIssue> issues;
  final int errors, warnings;

  @override
  Widget build(BuildContext context) {
    final has = issues.isNotEmpty;
    return _Panel(
      key: const ValueKey('home-cross'),
      title: tr('ปัญหาข้ามเอกสาร'),
      trailing: Container(
        key: const ValueKey('home-cross-count'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: has ? C.dangerBg : C.surfaceHi, borderRadius: BorderRadius.circular(999)),
        child: Text('${issues.length}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: has ? C.dangerText : C.muted)),
      ),
      children: [
        if (!has)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Text(tr('ลิงก์ระหว่างเอกสารครบถ้วน ไม่มีอะไรชี้ไปของที่ถูกลบ'), style: TextStyle(fontSize: 13, color: C.muted)),
          ),
        for (final (i, x) in issues.indexed)
          InkWell(
            key: ValueKey('home-cross-$i'),
            onTap: () => gotoWorkspaceIssue(context, x),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(x.issue.title, style: TextStyle(fontWeight: FontWeight.w500, color: C.text)),
                const SizedBox(height: 2),
                Row(children: [
                  DocTypeDot(x.docType, size: 7),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('${homeTypeLabel(x.docType)} · ${x.docName}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted)),
                  ),
                ]),
              ]),
            ),
          ),
        InkWell(
          key: const ValueKey('home-issues'),
          onTap: () => showWorkspaceIssues(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(
              tr('ปัญหาทั้งโปรเจกต์: {0} ข้อผิดพลาด · {1} คำเตือน →', [errors, warnings]),
              key: const ValueKey('home-issue-totals'),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.primary),
            ),
          ),
        ),
      ],
    );
  }
}
