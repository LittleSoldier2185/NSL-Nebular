import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/models/dfd_model.dart';
import '../../core/models/doc_ref.dart';
import '../../core/models/workspace.dart';
import '../../core/validate/dfd_validator.dart';
import '../../core/validate/issue.dart';
import '../../state/app_settings.dart';
import '../../state/dfd_controller.dart';
import '../../state/project_controller.dart';
import '../../state/workspace_controller.dart';
import '../document_actions.dart' show DocTypeDot;
import '../issue_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'dfd_actions.dart';
import 'dfd_painter.dart';
import '../api/api_ref_picker.dart';

IconData dfdKindIcon(DfdKind k) => switch (k) {
  DfdKind.entity => Icons.crop_square_rounded,
  DfdKind.process => Icons.rounded_corner_rounded,
  DfdKind.store => Icons.storage_rounded,
};

String dfdKindName(DfdKind k) => switch (k) {
  DfdKind.entity => tr('ผู้ใช้ภายนอก'),
  DfdKind.process => tr('กระบวนการ'),
  DfdKind.store => tr('ที่เก็บข้อมูล'),
};

const _kMono = kMono;
const _kMonoFallback = ['Consolas'];

/// หัวหมวดตัวเล็ก (ตามดีไซน์ Phase 15)
Widget _sec(String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.muted, letterSpacing: 0.4)),
        ),
        ?trailing,
      ]),
    );

/// เส้นเข้า (true) / ออก (false) ของวัตถุ [node]
(List<DfdFlow>, List<DfdFlow>) _io(DfdDiagram dg, DfdNode node) => (
      [for (final f in dg.flows) if (f.toId == node.id || (f.bidirectional && f.fromId == node.id)) f],
      [for (final f in dg.flows) if (f.fromId == node.id || (f.bidirectional && f.toId == node.id)) f],
    );

// =====================================================================================================
// แผงซ้าย

/// แผงซ้ายของแท็บ DFD (ตามดีไซน์ Phase 15): ค้นหา · ปุ่มวางวัตถุ (E / P / D / ขอบเขตระบบ) · รายการแยกตามชนิด (พับได้)
class DfdLeftPanel extends StatefulWidget {
  const DfdLeftPanel({super.key});

  @override
  State<DfdLeftPanel> createState() => _DfdLeftPanelState();
}

class _DfdLeftPanelState extends State<DfdLeftPanel> {
  String _q = '';

  /// หมวดที่พับอยู่ ('flows' = เส้นข้อมูล) — เส้นข้อมูลพับไว้ก่อนตามดีไซน์
  final _collapsed = <String>{'flows'};

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DfdController>();
    final w = context.watch<WorkspaceController>();
    final dg = d.diagram;
    final dc = C.doc(DocType.dfd);
    final q = _q.trim().toLowerCase();
    bool match(String s) => q.isEmpty || s.toLowerCase().contains(q);
    String nodeName(String id) => dg.nodeById(id)?.title ?? '?';

    final nodes = [for (final n in dg.nodes) if (match('${n.number} ${n.name}')) n];
    final flows = [for (final f in dg.flows) if (match('${f.label} ${nodeName(f.fromId)} ${nodeName(f.toId)}')) f];

    Widget group(String id, String title, int count, List<Widget> rows) {
      final open = q.isNotEmpty || !_collapsed.contains(id);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          key: ValueKey('dfd-group-$id'),
          onTap: () => setState(() => _collapsed.contains(id) ? _collapsed.remove(id) : _collapsed.add(id)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(children: [
              Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 15, color: C.muted),
              const SizedBox(width: 2),
              Expanded(
                child: Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.muted, letterSpacing: 0.4)),
              ),
              Text('$count', style: TextStyle(fontSize: 11, color: C.muted)),
            ]),
          ),
        ),
        if (open) ...rows,
      ]);
    }

    Widget row({required Key key, required bool selected, required VoidCallback onTap, String? number, required String title, Widget? trailing}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Material(
            color: selected ? dc.tint : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(6),
              onTap: onTap,
              child: SizedBox(
                height: 28,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(children: [
                    if (number != null && number.isNotEmpty) ...[
                      Text(number, style: TextStyle(fontSize: 11, fontFamily: _kMono, fontFamilyFallback: _kMonoFallback, color: selected ? dc.ink : C.muted)),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        title.isEmpty ? tr('(ไม่มีชื่อ)') : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? dc.ink : C.text),
                      ),
                    ),
                    ?trailing,
                  ]),
                ),
              ),
            ),
          ),
        );

    Widget? trailingOf(DfdNode n) {
      if (n.kind == DfdKind.store && n.tableId != null) {
        final t = w.erDocumentWithTable(n.tableDocId, n.tableId!)?.er?.tableById(n.tableId!);
        if (t != null) {
          return Flexible(
            child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: C.primaryDark, fontFamily: _kMono, fontFamilyFallback: _kMonoFallback)),
          );
        }
      }
      if (n.kind == DfdKind.process && n.api != null) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: C.borderSoft)),
          child: Text('API', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: dc.ink)),
        );
      }
      return null;
    }

    // ListTile/InkWell วาดพื้นบน Material ที่ใกล้สุด: ต้องมี Material ของตัวเองคั่นกลาง
    return Container(
      decoration: BoxDecoration(border: Border(right: BorderSide(color: C.border))),
      child: Material(
        color: C.surface,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
              child: Text(
                w.activeDocument.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: SizedBox(
                height: kFieldHeight,
                child: TextField(
                  key: const ValueKey('dfd-search'),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: tr('ค้นหาวัตถุ / เส้นข้อมูล'),
                    prefixIcon: const Icon(Icons.search_rounded, size: 16),
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
            ),
            const Padding(padding: EdgeInsets.fromLTRB(12, 2, 12, 0), child: _Palette()),
            Padding(padding: const EdgeInsets.only(top: 12), child: Divider(height: 1, color: C.borderSoft)),
            for (final k in const [DfdKind.process, DfdKind.entity, DfdKind.store])
              group(k.name, dfdKindName(k), nodes.where((n) => n.kind == k).length, [
                for (final n in nodes.where((n) => n.kind == k))
                  row(
                    key: ValueKey('dfd-item-${n.id}'),
                    selected: d.selectedNodeIds.contains(n.id),
                    number: k == DfdKind.entity ? null : n.number,
                    title: n.name,
                    trailing: trailingOf(n),
                    onTap: () {
                      d.selectNode(n.id);
                      d.reveal(n.id, d.viewport);
                    },
                  ),
              ]),
            group('flows', tr('เส้นข้อมูล'), flows.length, [
              for (final f in flows)
                row(
                  key: ValueKey('dfd-flow-${f.id}'),
                  selected: d.selectedFlowId == f.id,
                  title: f.label,
                  trailing: Flexible(
                    child: Text(
                      '${nodeName(f.fromId)} ${f.bidirectional ? '↔' : '→'} ${nodeName(f.toId)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: C.muted),
                    ),
                  ),
                  onTap: () => d.selectFlow(f.id),
                ),
            ]),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// ปุ่มวางวัตถุ 2×2 : เลือกเครื่องมือแล้วคลิกบนแคนวาส (ขอบเขตระบบ = วางกลางจอทันที)
class _Palette extends StatelessWidget {
  const _Palette();

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DfdController>();
    final dc = C.doc(DocType.dfd);
    Widget tile(String key, String label, String? shortcut, Widget shape, bool on, VoidCallback onTap) => Tooltip(
          message: shortcut == null ? label : '$label ($shortcut)',
          child: Material(
            color: on ? dc.tint : C.surface,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              key: ValueKey(key),
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: on ? dc.main : C.borderSoft, width: on ? 1.5 : 1),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  shape,
                  const SizedBox(height: 5),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: label),
                        if (shortcut != null) TextSpan(text: '  $shortcut', style: TextStyle(fontFamily: _kMono, fontFamilyFallback: _kMonoFallback, color: C.muted, fontSize: 10.5)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: on ? dc.ink : C.text, fontWeight: on ? FontWeight.w600 : FontWeight.w400),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
    final ink = dc.main;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sec(tr('วางวัตถุ')),
      // ความสูงปุ่มคงที่ 56 (ไม่ใช้ childAspectRatio: ความสูงจะผันตามความกว้างแผง แผงแคบแล้วเนื้อหาล้น)
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          mainAxisExtent: 56,
        ),
        children: [
          tile('dfd-tool-entity', tr('ผู้ใช้ภายนอก'), 'E',
              Container(width: 32, height: 16, decoration: BoxDecoration(border: Border.all(color: ink, width: 1.5))),
              d.tool == DfdTool.entity, () => d.setTool(DfdTool.entity)),
          tile('dfd-tool-process', tr('กระบวนการ'), 'P',
              Container(width: 32, height: 18, decoration: BoxDecoration(border: Border.all(color: ink, width: 1.5), borderRadius: BorderRadius.circular(5))),
              d.tool == DfdTool.process, () => d.setTool(DfdTool.process)),
          tile('dfd-tool-store', tr('ที่เก็บข้อมูล'), 'D',
              Container(
                width: 32,
                height: 13,
                decoration: BoxDecoration(border: Border(top: BorderSide(color: ink, width: 1.5), bottom: BorderSide(color: ink, width: 1.5), left: BorderSide(color: ink, width: 1.5))),
              ),
              d.tool == DfdTool.store, () => d.setTool(DfdTool.store)),
          tile('dfd-tool-boundary', tr('ขอบเขตระบบ'), null,
              Container(width: 32, height: 18, decoration: BoxDecoration(border: Border.all(color: C.muted), borderRadius: BorderRadius.circular(4))),
              false, () {
            final c = d.toWorld(d.viewport.center(Offset.zero));
            final b = d.addBoundaryAt(c.dx, c.dy, snap: context.read<AppSettings>().snapToGrid);
            if (b != null) DfdActions(context).renameBoundary(b);
          }),
        ],
      ),
    ]);
  }
}

// =====================================================================================================
// แผงขวา

/// แผงขวาของแท็บ DFD: คุณสมบัติของวัตถุ/เส้นที่เลือก หรือสรุปปัญหาของแผนภาพเมื่อไม่ได้เลือกอะไร
class DfdRightPanel extends StatelessWidget {
  const DfdRightPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DfdController>();
    context.watch<ProjectController>();
    final node = d.selectedNode;
    final flow = d.selectedFlow;
    final boundary = d.selectedBoundary;
    final Widget body;
    if (boundary != null) {
      body = _BoundaryProps(boundary: boundary);
    } else if (node != null) {
      body = _NodeProps(node: node);
    } else if (flow != null) {
      body = _FlowProps(flow: flow);
    } else if (d.selectedNodeIds.length > 1) {
      body = _MultiProps(ids: d.selectedNodeIds);
    } else {
      body = _Issues(diagram: d.diagram);
    }
    // Material คั่นกลาง: CheckboxListTile/ListTile วาดพื้นบน Material ใกล้สุด
    return Container(
      decoration: BoxDecoration(border: Border(left: BorderSide(color: C.border))),
      child: Material(color: C.surface, child: body),
    );
  }
}

/// โครงแผงขวา: หัว (ไอคอน ชื่อ คำอธิบาย ปุ่มลบ) + เนื้อหาเลื่อนได้ + แถบล่าง (ไม่บังคับ)
class _Panel extends StatelessWidget {
  const _Panel({required this.icon, required this.title, this.subtitle, this.onDelete, this.deleteTip, required this.children, this.footer});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onDelete;
  final String? deleteTip;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final dc = C.doc(DocType.dfd);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.borderSoft))),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: dc.tint, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 18, color: dc.main),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              if (subtitle != null)
                Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted)),
            ]),
          ),
          if (onDelete != null)
            IconButton(
              key: const ValueKey('dfd-delete'),
              tooltip: deleteTip,
              icon: Icon(Icons.delete_outline, color: C.danger, size: 20),
              onPressed: onDelete,
            ),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
      ?footer,
    ]);
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.current, required this.defaultColor, required this.onPick, required this.onCustom});
  final int? current;
  final int defaultColor;
  final ValueChanged<int?> onPick;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    Widget sw(Key k, String tip, bool on, VoidCallback tap, Widget child) => Tooltip(
          message: tip,
          child: InkResponse(
            key: k,
            onTap: tap,
            radius: 18,
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? C.text : C.border, width: on ? 2 : 1)),
              child: child,
            ),
          ),
        );
    Widget dot(int c, {double a = 1}) =>
        Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: Color(c).withValues(alpha: a)));
    final custom = current != null && !kDfdPalette.contains(current);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      sw(const ValueKey('dfd-color-default'), tr('ใช้สีตามชนิด'), current == null, () => onPick(null), dot(defaultColor, a: 0.35)),
      for (var i = 0; i < kDfdPalette.length; i++)
        sw(ValueKey('dfd-color-$i'), '#${(kDfdPalette[i] & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}',
            current == kDfdPalette[i], () => onPick(kDfdPalette[i]), dot(kDfdPalette[i])),
      sw(const ValueKey('dfd-color-custom'), tr('กำหนดสีเอง…'), custom, onCustom,
          custom ? dot(current!) : Icon(Icons.colorize_rounded, size: 15, color: C.muted)),
    ]);
  }
}

/// แถวเส้นข้อมูลเข้า/ออก (คลิก = เลือกเส้นนั้น)
class _FlowRow extends StatelessWidget {
  const _FlowRow({required this.flow, required this.incoming, required this.other});
  final DfdFlow flow;
  final bool incoming;
  final String other;

  @override
  Widget build(BuildContext context) {
    final d = context.read<DfdController>();
    final dc = C.doc(DocType.dfd);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: C.field,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          key: ValueKey('dfd-io-${flow.id}-${incoming ? 'in' : 'out'}'),
          borderRadius: BorderRadius.circular(6),
          onTap: () => d.selectFlow(flow.id),
          child: SizedBox(
            height: 28,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                Icon(incoming ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded, size: 14, color: dc.main),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(flow.label.isEmpty ? tr('(ไม่มีชื่อ)') : flow.label,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Text(other, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Connections extends StatelessWidget {
  const _Connections({required this.node});
  final DfdNode node;

  @override
  Widget build(BuildContext context) {
    final dg = context.read<DfdController>().diagram;
    final (ins, outs) = _io(dg, node);
    String otherOf(DfdFlow f) {
      final id = f.fromId == node.id ? f.toId : f.fromId;
      final n = dg.nodeById(id);
      if (n == null) return '?';
      return n.kind == DfdKind.entity || n.number.isEmpty ? n.title : n.number;
    }

    Widget count(int n) => Text('$n', style: TextStyle(fontSize: 11, color: C.muted));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sec(tr('ข้อมูลเข้า'), trailing: count(ins.length)),
      for (final f in ins) _FlowRow(flow: f, incoming: true, other: otherOf(f)),
      if (ins.isEmpty) Text(tr('— ไม่มี —'), style: TextStyle(fontSize: 12, color: C.muted)),
      const SizedBox(height: 10),
      _sec(tr('ข้อมูลออก'), trailing: count(outs.length)),
      for (final f in outs) _FlowRow(flow: f, incoming: false, other: otherOf(f)),
      if (outs.isEmpty) Text(tr('— ไม่มี —'), style: TextStyle(fontSize: 12, color: C.muted)),
    ]);
  }
}

/// แถบล่างของแผงวัตถุ: ผลตรวจกฎ DFD เฉพาะวัตถุนี้
class _NodeRules extends StatelessWidget {
  const _NodeRules({required this.node});
  final DfdNode node;

  @override
  Widget build(BuildContext context) {
    final d = context.read<DfdController>();
    final w = context.read<WorkspaceController>();
    final mine = [
      for (final i in validateDfd(d.diagram, workspace: w.workspace, diagramId: w.activeId))
        if (i.tableId == node.id && i.severity != Severity.info) i,
    ];
    if (mine.isEmpty) {
      return Container(
        key: const ValueKey('dfd-node-ok'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: C.primaryTint.withValues(alpha: 0.5), border: Border(top: BorderSide(color: C.borderSoft))),
        child: Row(children: [
          Icon(Icons.check_rounded, size: 15, color: C.primaryDark),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('ผ่านกฎ DFD'), style: TextStyle(fontSize: 12, color: C.primaryDark))),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: C.borderSoft))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final i in mine)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: IssueCard(key: ValueKey('dfd-node-issue-${i.code}'), issue: i),
          ),
      ]),
    );
  }
}

class _NodeProps extends StatelessWidget {
  const _NodeProps({required this.node});
  final DfdNode node;

  @override
  Widget build(BuildContext context) {
    final d = context.read<DfdController>();
    final a = DfdActions(context);
    final (ins, outs) = _io(d.diagram, node);
    final numbered = node.kind != DfdKind.entity;
    final title = numbered && node.number.isNotEmpty ? '${dfdKindName(node.kind)} ${node.number}' : dfdKindName(node.kind);
    final name = CommitField(
      key: ValueKey('dfd-name-${node.id}-${node.name}'),
      label: tr('ชื่อ'),
      value: node.name,
      onCommit: (v) => d.renameNode(node.id, v.trim()),
    );
    return _Panel(
      icon: dfdKindIcon(node.kind),
      title: title,
      subtitle: tr('ข้อมูลเข้า {0} · ออก {1}', [ins.length, outs.length]),
      onDelete: d.deleteSelection,
      deleteTip: tr('ลบวัตถุ'),
      footer: _NodeRules(node: node),
      children: [
        if (numbered)
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            SizedBox(
              width: 84,
              child: CommitField(
                key: ValueKey('dfd-number-${node.id}-${node.number}'),
                label: node.kind == DfdKind.process ? tr('เลขลำดับ') : tr('รหัส'),
                hint: node.kind == DfdKind.process ? '1.0' : 'D1',
                value: node.number,
                mono: true,
                onCommit: (v) => d.setNodeNumber(node.id, v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: name),
          ])
        else
          name,
        if (node.kind == DfdKind.process) ...[
          const SizedBox(height: 16),
          _ProcessChild(node: node),
          const SizedBox(height: 16),
          ApiRefPicker(value: node.api, onChanged: (r) => d.updateNode(node.id, (n) => n.api = r)),
        ],
        if (node.kind == DfdKind.store) ...[
          const SizedBox(height: 16),
          _StoreTable(node: node),
          _StoreUsages(node: node),
        ],
        const SizedBox(height: 16),
        _Connections(node: node),
        const SizedBox(height: 16),
        _sec(tr('สี')),
        _ColorRow(
          current: node.color,
          defaultColor: kDfdKindColors[node.kind]!,
          onPick: (c) => d.setNodesColor([node.id], c),
          onCustom: () => a.pickNodesColor([node.id], current: node.color ?? kDfdKindColors[node.kind]),
        ),
      ],
    );
  }
}

/// "ระดับถัดไป": แตกรายละเอียดกระบวนการเป็นแผนภาพย่อย — สร้างใหม่ (พร้อมเส้นข้อมูลเดียวกับแม่) หรือเลือกแท็บ DFD ที่มีอยู่
class _ProcessChild extends StatelessWidget {
  const _ProcessChild({required this.node});
  final DfdNode node;

  @override
  Widget build(BuildContext context) {
    final d = context.read<DfdController>();
    final w = context.watch<WorkspaceController>();
    final dc = C.doc(DocType.dfd);
    final cands = d.childCandidates(w.activeId);
    final cid = node.childId;
    final linked = cid == null ? null : w.documentById(cid);
    const none = '';
    final ids = [none, ...cands.map((t) => t.id)];
    final value = linked != null && ids.contains(linked.id) ? linked.id : none;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sec(tr('ระดับถัดไป')),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: linked != null ? dc.tint.withValues(alpha: 0.5) : null,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: linked != null ? dc.main.withValues(alpha: 0.35) : C.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (linked != null)
            Row(children: [
              DocTypeDot(DocType.dfd),
              const SizedBox(width: 8),
              Expanded(child: Text(linked.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: dc.ink))),
            ])
          else
            Text(
              cid != null ? tr('แผนภาพย่อยที่ชี้ไว้ไม่มีแล้ว') : tr('ยังไม่ได้แตกรายละเอียดเป็นแผนภาพย่อย'),
              style: TextStyle(fontSize: 12.5, color: cid != null ? C.danger : C.muted),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (linked != null)
              FilledButton.icon(
                key: const ValueKey('dfd-child-open'),
                style: FilledButton.styleFrom(backgroundColor: dc.main, visualDensity: VisualDensity.compact),
                onPressed: () => d.openChild(node.id),
                icon: const Icon(Icons.subdirectory_arrow_right_rounded, size: 16),
                label: Text(tr('เปิดแผนภาพย่อย')),
              ),
            if (cid == null)
              FilledButton.icon(
                key: const ValueKey('dfd-child-create'),
                style: FilledButton.styleFrom(backgroundColor: dc.main, visualDensity: VisualDensity.compact),
                onPressed: () => d.createChildFor(node.id),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(tr('สร้างแผนภาพย่อยใหม่')),
              ),
          ]),
          const SizedBox(height: 8),
          Text(tr('หรือเลือกแผนภาพที่มีอยู่'), style: TextStyle(fontSize: 11.5, color: C.muted)),
          const SizedBox(height: 4),
          KeyedSubtree(
            key: const ValueKey('dfd-child'),
            child: Dropdown<String>(
              value: value,
              items: ids,
              labelOf: (id) => id == none ? tr('— ไม่มี —') : w.documentById(id)!.name,
              onChanged: (id) => d.setProcessChild(node.id, id == none ? null : id),
            ),
          ),
        ]),
      ),
    ]);
  }
}

/// ผูกที่เก็บข้อมูลกับตารางใน ER: การ์ดตาราง (ดูคอลัมน์ · ไปที่ตาราง) + ตัวเลือกตาราง (ทุกตารางของทุก ER ในโปรเจกต์)
class _StoreTable extends StatelessWidget {
  const _StoreTable({required this.node});
  final DfdNode node;

  @override
  Widget build(BuildContext context) {
    final d = context.read<DfdController>();
    final w = context.watch<WorkspaceController>();
    final ers = [for (final e in w.documents) if (e.er != null) e];
    final multi = ers.length > 1;
    // ค่าของตัวเลือก = "docId<NUL>tableId" (ตารางคนละ ER อาจมี id เดียวกัน เช่น ER ที่ทำสำเนามา)
    String key(String doc, String table) => '$doc\u0000$table';
    final labels = <String, String>{
      for (final e in ers)
        for (final t in e.er!.tables) key(e.id, t.id): multi ? '${e.name} › ${t.name}' : t.name,
    };
    final tid = node.tableId;
    final linkedDoc = tid == null ? null : w.erDocumentWithTable(node.tableDocId, tid);
    final linked = linkedDoc?.er?.tableById(tid!);
    const none = '';
    final ids = [none, ...labels.keys];
    final value = linkedDoc == null ? none : key(linkedDoc.id, tid!);
    final picker = KeyedSubtree(
      key: const ValueKey('dfd-store-table'),
      child: Dropdown<String>(
        value: value,
        items: ids,
        labelOf: (id) => id == none ? tr('— ไม่ผูก —') : labels[id]!,
        onChanged: (id) {
          if (id == none) {
            d.setStoreTable(node.id, null);
            return;
          }
          final parts = id.split('\u0000');
          d.setStoreTable(node.id, DocRef(docId: parts[0], elementId: parts[1], kind: DocRefKind.storeTable));
        },
      ),
    );
    final er = C.doc(DocType.er);
    final Widget card;
    if (linked == null) {
      card = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: C.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            tid != null ? tr('ตารางที่ผูกไว้ถูกลบไปแล้ว') : tr('ยังไม่ได้ผูกกับตาราง'),
            style: TextStyle(fontSize: 12.5, color: tid != null ? C.danger : C.muted),
          ),
          const SizedBox(height: 8),
          picker,
        ]),
      );
    } else {
      final pr = linkedDoc!.er!;
      final fkCols = {for (final r in pr.relations) if (r.fromTableId == linked.id) r.fromColumnId};
      final cols = linked.columns;
      Widget col(String flag, Color fc, String name) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(children: [
              SizedBox(width: 24, child: Text(flag, style: TextStyle(fontSize: 10.5, fontFamily: _kMono, fontFamilyFallback: _kMonoFallback, color: fc, fontWeight: FontWeight.w600))),
              Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontFamily: _kMono, fontFamilyFallback: _kMonoFallback))),
            ]),
          );
      card = Container(
        key: const ValueKey('dfd-store-card'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: er.main.withValues(alpha: 0.35))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            color: er.tint,
            child: Row(children: [
              Icon(Icons.table_chart_outlined, size: 15, color: er.ink),
              const SizedBox(width: 8),
              Expanded(child: Text(linked.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontFamily: _kMono, fontFamilyFallback: _kMonoFallback, color: er.ink))),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(linkedDoc.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: er.ink)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final c in cols.take(4))
                col(
                  c.isPrimaryKey ? 'PK' : (fkCols.contains(c.id) ? 'FK' : (c.unique ? 'UQ' : '')),
                  c.isPrimaryKey ? C.palette.pkText : (fkCols.contains(c.id) ? er.ink : C.palette.uqText),
                  c.name,
                ),
              if (cols.length > 4)
                Text(tr('+ อีก {0} คอลัมน์', [cols.length - 4]), style: TextStyle(fontSize: 11.5, color: C.muted)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: C.borderSoft))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              OutlinedButton.icon(
                key: const ValueKey('dfd-store-goto'),
                onPressed: () => d.gotoLinkedTable(node.id),
                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                label: Text(tr('ไปที่ตารางใน ER')),
              ),
              const SizedBox(height: 8),
              Text(tr('เปลี่ยนตาราง'), style: TextStyle(fontSize: 11.5, color: C.muted)),
              const SizedBox(height: 4),
              picker,
            ]),
          ),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sec(tr('ผูกกับตารางใน ER')),
      card,
    ]);
  }
}

/// "ใช้ในเอกสารอื่น": เอกสารอื่นที่อ้างถึงตารางเดียวกับที่เก็บข้อมูลนี้ (คลิก = เปิดเอกสารนั้น)
class _StoreUsages extends StatelessWidget {
  const _StoreUsages({required this.node});
  final DfdNode node;

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    final tid = node.tableId;
    final er = tid == null ? null : w.erDocumentWithTable(node.tableDocId, tid);
    if (er == null) return const SizedBox.shrink();
    final seen = <String>{};
    final usages = [
      for (final u in w.usagesOf(er.id, tid!))
        if (!(u.$1 == w.activeId && u.$2 == node.id) && seen.add(u.$1)) u,
    ];
    if (usages.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _sec(tr('ใช้ตารางเดียวกันใน')),
        for (final (fromDoc, fromElement, _) in usages)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: C.field,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                key: ValueKey('dfd-usage-$fromDoc-$fromElement'),
                borderRadius: BorderRadius.circular(6),
                onTap: () => w.openDocument(fromDoc),
                child: SizedBox(
                  height: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(children: [
                      DocTypeDot(w.documentById(fromDoc)?.type),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(w.documentById(fromDoc)?.name ?? '?', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 16, color: C.muted),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// ขอบเขตระบบที่เลือก : ชื่อ สี ลบ
class _BoundaryProps extends StatelessWidget {
  const _BoundaryProps({required this.boundary});
  final DfdBoundary boundary;

  @override
  Widget build(BuildContext context) {
    final d = context.read<DfdController>();
    final a = DfdActions(context);
    return _Panel(
      icon: Icons.crop_free_rounded,
      title: tr('ขอบเขตระบบ'),
      onDelete: d.deleteSelection,
      deleteTip: tr('ลบขอบเขต (ไม่ลบวัตถุข้างใน)'),
      children: [
        CommitField(
          key: ValueKey('dfd-boundary-name-${boundary.id}-${boundary.name}'),
          label: tr('ชื่อ'),
          value: boundary.name,
          onCommit: (v) => d.renameBoundary(boundary.id, v.trim()),
        ),
        const SizedBox(height: 16),
        _sec(tr('สี')),
        _ColorRow(
          current: boundary.color,
          defaultColor: C.muted.toARGB32(),
          onPick: (c) => d.setBoundaryColor(boundary.id, c),
          onCustom: () => a.pickBoundaryColor(boundary),
        ),
        const SizedBox(height: 12),
        Text(tr('ลากเส้นประเพื่อย้าย (วัตถุข้างในเลื่อนตาม) · ลากจุดจับเพื่อปรับขนาด'), style: TextStyle(fontSize: 12, color: C.muted)),
      ],
    );
  }
}

class _FlowProps extends StatelessWidget {
  const _FlowProps({required this.flow});
  final DfdFlow flow;

  @override
  Widget build(BuildContext context) {
    final d = context.read<DfdController>();
    final w = context.read<WorkspaceController>();
    final a = DfdActions(context);
    final dc = C.doc(DocType.dfd);
    final dg = d.diagram;
    final from = dg.nodeById(flow.fromId), to = dg.nodeById(flow.toId);
    Widget end(String label, DfdNode? n, CrossAxisAlignment al) => Expanded(
          child: Column(crossAxisAlignment: al, children: [
            Text(label, style: TextStyle(fontSize: 11, color: C.muted)),
            Text.rich(
              TextSpan(children: [
                if (n != null && n.kind != DfdKind.entity && n.number.isNotEmpty)
                  TextSpan(text: '${n.number} ', style: TextStyle(fontFamily: _kMono, fontFamilyFallback: _kMonoFallback, color: dc.ink)),
                TextSpan(text: n?.name ?? '?'),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: al == CrossAxisAlignment.end ? TextAlign.right : TextAlign.left,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
            ),
          ]),
        );
    final external = from?.kind == DfdKind.entity || to?.kind == DfdKind.entity;
    final parents = d.parentsOf(w.activeId);
    final internal = from?.kind != DfdKind.entity && to?.kind != DfdKind.entity;
    return _Panel(
      icon: Icons.arrow_right_alt_rounded,
      title: tr('เส้นข้อมูล'),
      subtitle: external ? tr('ต่อกับผู้ใช้ภายนอก') : (internal ? tr('ภายในระบบ') : null),
      onDelete: d.deleteSelection,
      deleteTip: tr('ลบเส้นข้อมูล'),
      children: [
        CommitField(
          key: ValueKey('dfd-label-${flow.id}-${flow.label}'),
          label: tr('ชื่อข้อมูลที่ไหล'),
          value: flow.label,
          onCommit: (v) => d.setFlowLabel(flow.id, v.trim()),
        ),
        const SizedBox(height: 16),
        _sec(tr('ทิศทาง')),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: C.borderSoft)),
          child: Row(children: [
            end(tr('จาก'), from, CrossAxisAlignment.start),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(flow.bidirectional ? Icons.sync_alt_rounded : Icons.arrow_forward_rounded, size: 18, color: dc.main),
            ),
            end(tr('ไป'), to, CrossAxisAlignment.end),
          ]),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('dfd-reverse'),
          onPressed: () => d.reverseFlow(flow.id),
          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
          label: Text(tr('สลับทิศทาง')),
        ),
        CheckboxListTile(
          key: const ValueKey('dfd-both'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: flow.bidirectional,
          onChanged: (v) => d.setFlowBidirectional(flow.id, v ?? false),
          title: Text(tr('ข้อมูลไหลสองทาง'), style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(height: 8),
        _sec(tr('เส้นและป้าย')),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              key: const ValueKey('dfd-reset-route'),
              onPressed: flow.hasManualRoute ? () => d.resetEdgeRoute(flow.id) : null,
              child: Text(tr('จัดเส้นอัตโนมัติ'), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: OutlinedButton(
              key: const ValueKey('dfd-reset-label'),
              onPressed: flow.labelDx != 0 || flow.labelDy != 0 ? () => d.resetEdgeLabelPosition(flow.id) : null,
              child: Text(tr('ป้ายกลับที่เดิม'), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(tr('ลากจุดกลางเส้นเพื่อดัด · ลากป้ายเพื่อย้าย'), style: TextStyle(fontSize: 11.5, color: C.muted)),
        const SizedBox(height: 16),
        _sec(tr('สีเส้น')),
        _ColorRow(
          current: flow.color,
          defaultColor: C.primary.toARGB32(),
          onPick: (c) => d.setFlowColor(flow.id, c),
          onCustom: () => a.pickFlowColor(flow),
        ),
        if (parents.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sec(tr('สมดุลกับระดับบน')),
          Container(
            key: const ValueKey('dfd-flow-balance-note'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(9)),
            child: Text(
              external
                  ? tr('เส้นนี้ต่อกับภายนอก — ต้องมีเส้นชื่อเดียวกันที่ {0} ใน {1}', [parents.first.$2.title, parents.first.$1.name])
                  : tr('เส้นนี้อยู่ภายในระบบ — ไม่ต้องมีคู่ในระดับบน'),
              style: TextStyle(fontSize: 12, color: C.muted),
            ),
          ),
        ],
      ],
    );
  }
}

class _MultiProps extends StatelessWidget {
  const _MultiProps({required this.ids});
  final Set<String> ids;

  @override
  Widget build(BuildContext context) {
    final d = context.read<DfdController>();
    final a = DfdActions(context);
    return _Panel(
      icon: Icons.select_all_rounded,
      title: tr('เลือก {0} วัตถุ', [ids.length]),
      onDelete: d.deleteSelection,
      deleteTip: tr('ลบวัตถุ'),
      children: [
        _sec(tr('สี')),
        _ColorRow(
          current: null,
          defaultColor: kDfdKindColors[DfdKind.process]!,
          onPick: (c) => d.setNodesColor(ids, c),
          onCustom: () => a.pickNodesColor(ids),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('dfd-duplicate'),
          onPressed: d.duplicateSelection,
          icon: const Icon(Icons.file_copy_outlined, size: 16),
          label: Text(tr('ทำสำเนา')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('dfd-multi-boundary'),
          onPressed: d.addBoundaryAround,
          icon: const Icon(Icons.crop_free_rounded, size: 16),
          label: Text(tr('ครอบด้วยขอบเขตระบบ')),
        ),
      ],
    );
  }
}

/// สรุปปัญหาของแผนภาพ (กฎของ DFD) — คลิกรายการเพื่อไปเลือกวัตถุ/เส้นที่เกี่ยวข้อง
class _Issues extends StatelessWidget {
  const _Issues({required this.diagram});
  final DfdDiagram diagram;

  @override
  Widget build(BuildContext context) {
    final d = context.read<DfdController>();
    final w = context.read<WorkspaceController>();
    final issues = validateDfd(diagram, workspace: w.workspace, diagramId: w.activeId);
    return _Panel(
      icon: Icons.account_tree_outlined,
      title: tr('แผนภาพ DFD'),
      subtitle: tr('{0} วัตถุ · {1} เส้นข้อมูล', [diagram.nodes.length, diagram.flows.length]),
      children: [
        _sec(tr('ตรวจสอบแผนภาพ'), trailing: Text('${issues.length}', style: TextStyle(fontSize: 11, color: C.muted))),
        if (diagram.nodes.isEmpty)
          Text(tr('วางวัตถุแล้วต่อเส้นข้อมูล ระบบจะตรวจกฎของ DFD ให้'), style: TextStyle(fontSize: 12.5, color: C.muted))
        else if (issues.isEmpty)
          Text(tr('✓ ไม่พบปัญหา'), key: const ValueKey('dfd-no-issues'), style: TextStyle(fontSize: 12.5, color: C.primaryDark))
        else
          for (final i in issues)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: IssueCard(
                key: ValueKey('dfd-issue-${i.code}-${i.tableId ?? i.relationId}'),
                issue: i,
                onTap: () {
                  if (i.tableId != null) {
                    d.selectNode(i.tableId!);
                    d.reveal(i.tableId!, d.viewport);
                  } else if (i.relationId != null) {
                    d.selectFlow(i.relationId);
                  }
                },
              ),
            ),
      ],
    );
  }
}
