import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/export/trace_export.dart';
import '../core/l10n/l10n.dart';
import '../core/models/requirement.dart';
import '../core/models/traceability.dart';
import '../core/models/workspace.dart';
import '../state/workspace_controller.dart';
import 'document_actions.dart' show DocTypeDot;
import 'file_actions.dart';
import 'notes_panel.dart' show gotoNoteTarget;
import 'project_home.dart' show homeTypeLabel;
import 'theme.dart';
import 'widgets.dart';

String reqPriorityLabel(ReqPriority p) => switch (p) {
      ReqPriority.high => tr('สูง@@priority'),
      ReqPriority.medium => tr('กลาง@@priority'),
      ReqPriority.low => tr('ต่ำ'),
    };

/// ชื่อคอลัมน์ของเมทริกซ์ (สั้น ตามดีไซน์)
String traceColumnLabel(DocType t) => switch (t) {
      DocType.er => 'ER',
      DocType.dfd => 'DFD',
      DocType.flowchart => 'Flowchart',
      DocType.wireframe => 'Wireframe',
      DocType.screenflow => 'Screen',
      DocType.api => 'API',
    };

/// หน้าความต้องการและการไล่ตาม (Artboard `Trace`): สรุป · เมทริกซ์ ความต้องการ × ชนิดเอกสาร
/// แสดงแทนแคนวาสขณะ [WorkspaceController.page] == [WorkspacePage.trace]
class TraceView extends StatelessWidget {
  const TraceView({super.key});

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    final s = traceSummary(w.workspace);
    return Container(
      key: const ValueKey('trace-view'),
      color: C.bg,
      child: ListView(padding: const EdgeInsets.all(24), children: [
        Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('ความต้องการและการไล่ตาม'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: C.text)),
              const SizedBox(height: 4),
              Text(tr('ผูกความต้องการแต่ละข้อกับเอกสารที่ทำมันจริง ดูทันทีว่าข้อไหนยังขาดอะไร'), style: TextStyle(color: C.muted)),
            ]),
          ),
          OutlinedButton(
            key: const ValueKey('trace-export'),
            onPressed: w.requirements.isEmpty
                ? null
                : () => FileActions.saveText(context, exportTraceMarkdown(w.workspace),
                    '${FileActions.safeName(w.workspace.name)}-requirements.md', tr('ส่งออกเป็นเอกสารสเปก')),
            child: Text(tr('ส่งออกเป็นเอกสารสเปก')),
          ),
          FilledButton(
            key: const ValueKey('trace-add'),
            onPressed: () => w.addRequirement(),
            child: Text(tr('+ ความต้องการ')),
          ),
        ]),
        const SizedBox(height: 20),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _Stat(key: const ValueKey('trace-stat-covered'), label: tr('ครอบคลุมครบ'), value: '${s.covered} / ${s.total}', unit: tr('ข้อ'), good: s.total > 0 && s.covered == s.total),
          _Stat(key: const ValueKey('trace-stat-screens'), label: tr('ยังไม่มีหน้าจอ'), value: '${s.missingScreens}', warn: s.missingScreens > 0),
          _Stat(key: const ValueKey('trace-stat-api'), label: tr('ยังไม่มี API'), value: '${s.missingApi}', warn: s.missingApi > 0),
          _Stat(
            key: const ValueKey('trace-stat-unlinked'),
            label: tr('เอกสารที่ไม่ได้ผูกกับความต้องการใด'),
            value: '${s.unlinkedDocs.length}',
            tooltip: s.unlinkedDocs.map((d) => d.name).join('\n'),
          ),
        ]),
        const SizedBox(height: 20),
        if (w.requirements.isEmpty)
          Container(
            key: const ValueKey('trace-empty'),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
            child: Text(tr('ยังไม่มีความต้องการ — กด "+ ความต้องการ" เพื่อเริ่ม'), textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
          )
        else
          _Matrix(reqs: w.requirements),
        const SizedBox(height: 10),
        Text(tr('ช่องเหลืองคือที่ยังขาด กดเพื่อผูกกับเอกสารที่มีอยู่ หรือสร้างเอกสารใหม่ที่ผูกกับความต้องการนั้นทันที'),
            style: TextStyle(fontSize: 12, color: C.muted)),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.label, required this.value, this.unit, this.warn = false, this.good = false, this.tooltip});
  final String label, value;
  final String? unit;
  final bool warn, good;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final color = warn ? C.warnText : (good ? C.primaryDark : C.text);
    final box = Container(
      width: 210,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warn ? C.warnBg : C.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, maxLines: 2, style: TextStyle(fontSize: 12, color: C.muted)),
        const SizedBox(height: 4),
        Text.rich(TextSpan(children: [
          TextSpan(text: value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color)),
          if (unit != null) TextSpan(text: ' $unit', style: TextStyle(fontSize: 13, color: C.muted)),
        ])),
      ]),
    );
    return tooltip == null || tooltip!.isEmpty ? box : Tooltip(message: tooltip!, child: box);
  }
}

class _Matrix extends StatelessWidget {
  const _Matrix({required this.reqs});
  final List<Requirement> reqs;

  @override
  Widget build(BuildContext context) {
    final w = context.read<WorkspaceController>();
    final head = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.muted);
    return Container(
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1000),
          child: Table(
            columnWidths: {
              0: const FixedColumnWidth(90),
              1: const FixedColumnWidth(260),
              2: const FixedColumnWidth(90),
              for (var i = 0; i < kTraceColumns.length; i++) 3 + i: const FixedColumnWidth(130),
              3 + kTraceColumns.length: const FixedColumnWidth(40),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder(horizontalInside: BorderSide(color: C.borderSoft)),
            children: [
              TableRow(
                decoration: BoxDecoration(color: C.tableHead),
                children: [
                  for (final h in [tr('รหัส'), tr('ความต้องการ'), tr('ความสำคัญ')])
                    Padding(padding: const EdgeInsets.all(10), child: Text(h, style: head)),
                  for (final t in kTraceColumns)
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(children: [
                        DocTypeDot(t, size: 7),
                        const SizedBox(width: 5),
                        Flexible(child: Text(traceColumnLabel(t), maxLines: 1, overflow: TextOverflow.ellipsis, style: head)),
                      ]),
                    ),
                  const SizedBox.shrink(),
                ],
              ),
              for (final r in reqs)
                TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: CommitField(
                      key: ValueKey('trace-code-${r.id}'),
                      value: r.code,
                      mono: true,
                      onCommit: (v) => w.updateRequirement(r.id, (x) => x.code = v.trim()),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: CommitField(
                      key: ValueKey('trace-text-${r.id}'),
                      value: r.text,
                      hint: tr('อธิบายความต้องการ'),
                      onCommit: (v) => w.updateRequirement(r.id, (x) => x.text = v.trim()),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Dropdown<ReqPriority>(
                      key: ValueKey('trace-priority-${r.id}'),
                      value: r.priority,
                      items: ReqPriority.values,
                      labelOf: reqPriorityLabel,
                      onChanged: (p) => w.updateRequirement(r.id, (x) => x.priority = p),
                    ),
                  ),
                  for (final t in kTraceColumns) _Cell(req: r, type: t),
                  IconButton(
                    key: ValueKey('trace-delete-${r.id}'),
                    tooltip: tr('ลบความต้องการ'),
                    iconSize: 16,
                    onPressed: () => w.deleteRequirement(r.id),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// ช่องหนึ่ง: ลิงก์ที่ใช้ได้ (กด = เมนู) / "ไม่จำเป็น" / "+ ยังไม่มี" (พื้นเหลือง)
class _Cell extends StatelessWidget {
  const _Cell({required this.req, required this.type});
  final Requirement req;
  final DocType type;

  @override
  Widget build(BuildContext context) {
    final w = context.read<WorkspaceController>();
    final status = traceStatus(w.workspace, req, type);
    final links = validLinks(w.workspace, req, type);
    final Widget label = switch (status) {
      TraceStatus.covered => Text(
          links.map((l) => traceLinkLabel(w.workspace, l) ?? '?').join(', '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, color: C.doc(type).ink, fontWeight: FontWeight.w500),
        ),
      TraceStatus.notNeeded => Text(tr('ไม่จำเป็น'), style: TextStyle(fontSize: 12, color: C.muted)),
      TraceStatus.missing => Text(tr('+ ยังไม่มี'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.warnText)),
    };
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: status == TraceStatus.missing ? C.warnBg : (status == TraceStatus.covered ? C.doc(type).tint : Colors.transparent),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          key: ValueKey('trace-cell-${req.id}-${type.name}'),
          borderRadius: BorderRadius.circular(6),
          onTap: () => _menu(context, w),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: label),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, WorkspaceController w) async {
    final box = context.findRenderObject()! as RenderBox;
    final pos = box.localToGlobal(Offset(0, box.size.height));
    final cands = traceCandidates(w.workspace, type);
    final current = req.cells[type]?.links ?? const <TraceLink>[];
    final valid = validLinks(w.workspace, req, type);
    final choice = await showMenu<Object>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        for (final c in cands)
          CheckedPopupMenuItem<Object>(value: c.link, checked: current.contains(c.link), height: 34, child: Text(c.label, style: const TextStyle(fontSize: 13))),
        if (cands.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem<Object>(
          value: 'create',
          height: 34,
          child: Text(tr('สร้าง {0} ใหม่ที่ผูกกับข้อนี้', [homeTypeLabel(type)]), style: const TextStyle(fontSize: 13)),
        ),
        for (final l in valid)
          PopupMenuItem<Object>(
            value: ('open', l),
            height: 34,
            child: Text(tr('ไปที่ {0}', [traceLinkLabel(w.workspace, l) ?? '?']), style: const TextStyle(fontSize: 13)),
          ),
        CheckedPopupMenuItem<Object>(
          value: 'na',
          checked: req.cells[type]?.notNeeded ?? false,
          height: 34,
          child: Text(tr('ไม่จำเป็น'), style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
    if (choice == null) return;
    switch (choice) {
      case TraceLink l:
        w.toggleTraceLink(req.id, type, l);
      case 'create':
        w.createTracedDocument(req.id, type);
      case 'na':
        w.setTraceNotNeeded(req.id, type, !(req.cells[type]?.notNeeded ?? false));
      case ('open', TraceLink l):
        if (context.mounted) gotoNoteTarget(context, l.docId, elementId: l.elementId);
    }
  }
}
