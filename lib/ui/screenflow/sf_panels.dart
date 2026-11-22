import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/layout/box_ops.dart';
import '../../core/layout/screenflow_geometry.dart' show sfNodeColor;
import '../../core/models/api_ref.dart';
import '../../core/models/screenflow_model.dart';
import '../../core/models/wireframe_model.dart';
import '../../core/models/workspace.dart';
import '../../core/validate/issue.dart';
import '../../core/validate/screenflow_validator.dart';
import '../../state/app_settings.dart';
import '../../state/screenflow_controller.dart';
import '../../state/workspace_controller.dart';
import '../canvas/canvas_chrome.dart';
import '../color_picker_dialog.dart';
import '../issue_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import '../wireframe/wf_painter.dart' show kWfPalette;
import '../wireframe/wf_panels.dart' show WireframeThumbnail;
import 'sf_actions.dart';
import 'sf_view.dart';
import '../api/api_ref_picker.dart';
import '../../state/doc_controller.dart';

const _kMonoFallback = ['Consolas'];

/// หัวหมวดตัวเล็ก (ตามดีไซน์ Phase 16)
Widget _sec(String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.muted, letterSpacing: 0.4))),
        ?trailing,
      ]),
    );

/// ชื่อชนิดหน้าจอจากขนาด Wireframe
String _deviceOf(WireframeDiagram wf) => wf.width >= 1024 ? tr('เดสก์ท็อป') : (wf.width >= 600 ? tr('แท็บเล็ต') : tr('มือถือ'));

/// "POST /loans" ของ endpoint ที่อ้าง (ไม่พบ = null)
String? _endpointLabel(WorkspaceController w, ApiRef? a) {
  if (a == null) return null;
  final e = w.documentById(a.docId)?.api?.endpointById(a.endpointId);
  return e == null ? null : '${e.method.name.toUpperCase()} ${e.path}';
}

Widget _chip(String text, Color bg, Color fg, {bool mono = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: fg, fontFamily: mono ? kMono : null, fontFamilyFallback: mono ? _kMonoFallback : null),
      ),
    );

// =====================================================================================================
// แผงซ้าย

/// แผงซ้ายของแท็บ Screen Flow (ตามดีไซน์ Phase 16): ค้นหา · ปุ่มวางโหนด (คลิก = เครื่องมือ / ลากไปวาง) + "จาก Wireframe…" ·
/// รายการแยกหน้าจอ / จุดอื่น / การเปลี่ยนหน้า (พับได้)
class ScreenFlowLeftPanel extends StatefulWidget {
  const ScreenFlowLeftPanel({super.key});

  @override
  State<ScreenFlowLeftPanel> createState() => _ScreenFlowLeftPanelState();
}

class _ScreenFlowLeftPanelState extends State<ScreenFlowLeftPanel> {
  String _q = '';
  final _collapsed = <String>{'edges'};

  @override
  Widget build(BuildContext context) {
    final f = context.watchContent<ScreenFlowController>();
    final w = context.watch<WorkspaceController>();
    final dc = C.doc(DocType.screenflow);
    final d = f.diagram;
    final q = _q.trim().toLowerCase();
    bool match(String s) => q.isEmpty || s.toLowerCase().contains(q);
    String name(String id) => d.nodeById(id) == null ? '?' : sfNodeTitle(d.nodeById(id)!);
    final nodes = [for (final n in d.nodes) if (match('${n.title} ${sfKindLabel(n.kind)}')) n];
    final edges = [for (final e in d.edges) if (match('${e.label} ${e.condition} ${name(e.fromId)} ${name(e.toId)}')) e];

    Widget group(String id, String title, int count, List<Widget> rows) {
      final open = q.isNotEmpty || !_collapsed.contains(id);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          key: ValueKey('sf-group-$id'),
          onTap: () => setState(() => _collapsed.contains(id) ? _collapsed.remove(id) : _collapsed.add(id)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(children: [
              Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 15, color: C.muted),
              const SizedBox(width: 2),
              Expanded(child: Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.muted, letterSpacing: 0.4))),
              Text('$count', style: TextStyle(fontSize: 11, color: C.muted)),
            ]),
          ),
        ),
        if (open) ...rows,
      ]);
    }

    Widget row({required Key key, required bool selected, required VoidCallback onTap, Widget? lead, required String title, Widget? trailing}) => Padding(
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
                    if (lead != null) ...[lead, const SizedBox(width: 8)],
                    Expanded(
                      child: Text(title.isEmpty ? tr('(ไม่มีชื่อ)') : title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? dc.ink : C.text)),
                    ),
                    if (trailing != null) ...[const SizedBox(width: 6), trailing],
                  ]),
                ),
              ),
            ),
          ),
        );

    Widget muted(String t) => Flexible(child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: C.muted)));
    final screens = [for (final n in nodes) if (n.kind == SfKind.screen) n];
    final others = [for (final n in nodes) if (n.kind != SfKind.screen) n];

    return Container(
      decoration: BoxDecoration(border: Border(right: BorderSide(color: C.border))),
      child: Material(
        color: C.surface,
        child: ListView(padding: EdgeInsets.zero, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Text(w.activeDocument.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: SizedBox(
              height: kFieldHeight,
              child: TextField(
                key: const ValueKey('sf-search'),
                decoration: InputDecoration(isDense: true, hintText: tr('ค้นหาหน้าจอ / การเปลี่ยนหน้า'), prefixIcon: const Icon(Icons.search_rounded, size: 16)),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(12, 2, 12, 0), child: _Palette()),
          Padding(padding: const EdgeInsets.only(top: 12), child: Divider(height: 1, color: C.borderSoft)),
          group('screens', tr('หน้าจอ'), screens.length, [
            for (final n in screens)
              row(
                key: ValueKey('sf-item-${n.id}'),
                selected: f.selectedIds.contains(n.id),
                lead: Container(width: 8, height: 8, decoration: BoxDecoration(color: n.wireframeId == null ? C.border : C.doc(DocType.wireframe).main, borderRadius: BorderRadius.circular(2))),
                title: sfNodeTitle(n),
                trailing: f.linkedWireframe(n) == null ? muted(tr('ไม่ผูก')) : muted(_deviceOf(f.linkedWireframe(n)!)),
                onTap: () {
                  f.selectBox(n.id);
                  f.reveal(n.id, f.viewport);
                },
              ),
          ]),
          group('others', tr('จุดเริ่ม / จบ / ภายนอก'), others.length, [
            for (final n in others)
              row(
                key: ValueKey('sf-item-${n.id}'),
                selected: f.selectedIds.contains(n.id),
                lead: Icon(sfKindIcon(n.kind), size: 14, color: Color(sfNodeColor(n))),
                title: sfNodeTitle(n),
                trailing: muted(sfKindLabel(n.kind)),
                onTap: () {
                  f.selectBox(n.id);
                  f.reveal(n.id, f.viewport);
                },
              ),
          ]),
          group('edges', tr('การเปลี่ยนหน้า'), edges.length, [
            for (final e in edges)
              row(
                key: ValueKey('sf-edge-${e.id}'),
                selected: f.selectedEdgeId == e.id,
                title: e.caption,
                trailing: muted('${name(e.fromId)} → ${name(e.toId)}'),
                onTap: () => f.selectEdge(e.id),
              ),
          ]),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}

/// ปุ่มวางโหนด 2×2 (คลิก = เครื่องมือ / ลากไปวาง) + "จาก Wireframe…" (เพิ่มหน้าจอที่ผูก Wireframe ที่ยังไม่อยู่ในแผนผัง)
class _Palette extends StatelessWidget {
  const _Palette();

  @override
  Widget build(BuildContext context) {
    final f = context.watchContent<ScreenFlowController>();
    final w = context.watch<WorkspaceController>();
    final dc = C.doc(DocType.screenflow);
    Widget shape(SfKind k) => switch (k) {
          SfKind.screen => Container(
              width: 20,
              height: 26,
              decoration: BoxDecoration(border: Border.all(color: dc.main, width: 1.5), borderRadius: BorderRadius.circular(3)),
              alignment: Alignment.topCenter,
              child: Container(height: 6, color: dc.tint),
            ),
          SfKind.start => Container(width: 30, height: 14, decoration: BoxDecoration(border: Border.all(color: dc.main, width: 1.5), borderRadius: BorderRadius.circular(7))),
          SfKind.end => Container(width: 30, height: 14, decoration: BoxDecoration(border: Border.all(color: C.muted, width: 1.5), borderRadius: BorderRadius.circular(7))),
          SfKind.external => Container(width: 30, height: 18, decoration: BoxDecoration(border: Border.all(color: dc.main), borderRadius: BorderRadius.circular(4))),
        };
    Widget tile(SfKind k) {
      final on = f.tool == SfTool.node && f.toolKind == k;
      final body = Container(
        height: 54,
        decoration: BoxDecoration(
          color: on ? dc.tint : C.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? dc.main : C.borderSoft, width: on ? 1.5 : 1),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          shape(k),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: sfKindLabel(k)),
                TextSpan(text: '  ${sfKindShortcut(k)}', style: TextStyle(fontFamily: kMono, fontFamilyFallback: _kMonoFallback, color: C.muted, fontSize: 10.5)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: on ? dc.ink : C.text, fontWeight: on ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
        ]),
      );
      return Tooltip(
        message: '${sfKindLabel(k)} (${sfKindShortcut(k)})',
        child: Draggable<Object>(
          data: k,
          feedback: Material(color: Colors.transparent, child: Opacity(opacity: 0.8, child: SizedBox(width: 110, child: body))),
          child: Material(
            color: Colors.transparent,
            child: InkWell(key: ValueKey('sf-tool-${k.name}'), borderRadius: BorderRadius.circular(8), onTap: () => f.setNodeTool(k), child: body),
          ),
        ),
      );
    }

    // Wireframe ที่ยังไม่มีหน้าจอในแผนผังนี้ผูกอยู่
    final used = {for (final n in f.diagram.nodes) ?n.wireframeId};
    final free = [for (final x in w.workspace.documentsOf(DocType.wireframe)) if (!used.contains(x.id)) x];
    final fromWf = PopupMenuButton<String>(
      key: const ValueKey('sf-from-wireframe'),
      tooltip: tr('เพิ่มหน้าจอจาก Wireframe ที่มีอยู่'),
      enabled: free.isNotEmpty,
      onSelected: (id) {
        final doc = w.documentById(id);
        if (doc == null) return;
        final c = f.toWorld(f.viewport.center(Offset.zero));
        final n = f.addNode(SfKind.screen, c.dx, c.dy, snap: context.read<AppSettings>().snapToGrid);
        if (n == null) return;
        f.linkWireframe(n.id, id);
        f.setTitle(n.id, doc.name);
      },
      itemBuilder: (_) => [
        for (final x in free) PopupMenuItem(value: x.id, height: 34, child: Text(x.name, style: const TextStyle(fontSize: 13))),
      ],
      child: Container(
        height: 34,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: C.border)),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          Icon(Icons.web_outlined, size: 15, color: free.isEmpty ? C.muted.withValues(alpha: 0.5) : C.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              free.isEmpty ? tr('ทุก Wireframe อยู่ในแผนผังแล้ว') : tr('จาก Wireframe… ({0})', [free.length]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: free.isEmpty ? C.muted : C.text),
            ),
          ),
        ]),
      ),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sec(tr('วางโหนด')),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 2,
        children: [for (final k in const [SfKind.screen, SfKind.start, SfKind.external, SfKind.end]) tile(k)],
      ),
      const SizedBox(height: 6),
      fromWf,
    ]);
  }
}

// =====================================================================================================
// แผงขวา

/// แผงขวาของแท็บ Screen Flow
class ScreenFlowRightPanel extends StatelessWidget {
  const ScreenFlowRightPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final f = context.watchContent<ScreenFlowController>();
    context.watch<WorkspaceController>();
    final node = f.selectedNode;
    final edge = f.selectedEdge;
    final Widget body;
    if (node != null) {
      body = _NodeProps(node: node);
    } else if (edge != null) {
      body = _EdgeProps(edge: edge);
    } else if (f.selectedIds.length > 1) {
      body = _MultiProps(ids: f.selectedIds);
    } else {
      body = const _Overview();
    }
    return Container(
      decoration: BoxDecoration(border: Border(left: BorderSide(color: C.border))),
      child: Material(color: C.surface, child: body),
    );
  }
}

/// โครงแผงขวา: หัว (ไอคอน ชื่อ คำอธิบาย ปุ่มลบ) + เนื้อหาเลื่อนได้ + แถบล่าง
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
    final dc = C.doc(DocType.screenflow);
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
              if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted)),
            ]),
          ),
          if (onDelete != null)
            IconButton(key: const ValueKey('sf-delete'), tooltip: deleteTip, icon: Icon(Icons.delete_outline, color: C.danger, size: 20), onPressed: onDelete),
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

/// แถวการเปลี่ยนหน้า (ไปต่อ / มาจาก): trigger, เงื่อนไข, ปลายอีกด้าน, endpoint ; คลิก = เลือกเส้น
class _EdgeRow extends StatelessWidget {
  const _EdgeRow({required this.edge, required this.outgoing});
  final SfEdge edge;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final f = context.read<ScreenFlowController>();
    final w = context.read<WorkspaceController>();
    final dc = C.doc(DocType.screenflow);
    final other = f.diagram.nodeById(outgoing ? edge.toId : edge.fromId);
    final api = _endpointLabel(w, edge.api);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: C.field,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          key: ValueKey('sf-io-${edge.id}-${outgoing ? 'out' : 'in'}'),
          borderRadius: BorderRadius.circular(7),
          onTap: () => f.selectEdge(edge.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(outgoing ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded, size: 14, color: dc.main),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(edge.label.isEmpty ? tr('(ไม่มีป้าย)') : edge.label,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
                if (edge.condition.trim().isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(child: _chip(edge.condition.trim(), C.palette.warnBg, C.palette.warnText)),
                ],
                const SizedBox(width: 8),
                const Spacer(),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 100),
                  child: Text(other == null ? '?' : sfNodeTitle(other), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted)),
                ),
              ]),
              if (api != null) ...[
                const SizedBox(height: 3),
                Padding(padding: const EdgeInsets.only(left: 20), child: _chip(api, C.palette.infoBg, C.palette.infoText, mono: true)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// การ์ด Wireframe ของหน้าจอ: ภาพย่อ ชื่อ ขนาด จำนวนชิ้น/ปุ่มที่เรียก API + เปิด / เปลี่ยน (หรือสร้างเมื่อยังไม่ผูก)
class _WireframeCard extends StatelessWidget {
  const _WireframeCard({required this.node});
  final SfNode node;

  @override
  Widget build(BuildContext context) {
    final f = context.read<ScreenFlowController>();
    final w = context.watch<WorkspaceController>();
    final a = ScreenFlowActions(context);
    final wc = C.doc(DocType.wireframe);
    final wfDocs = w.workspace.documentsOf(DocType.wireframe).toList();
    final linked = f.linkedWireframe(node);
    final current = node.wireframeId;
    final broken = current != null && linked == null;
    const none = '';
    final picker = KeyedSubtree(
      key: const ValueKey('sf-wireframe'),
      child: Dropdown<String>(
        value: broken ? none : (current ?? none),
        items: [none, for (final x in wfDocs) x.id],
        labelOf: (id) => id == none ? tr('— ไม่ผูก —') : (w.documentById(id)?.name ?? id),
        onChanged: (v) => f.linkWireframe(node.id, v == none ? null : v),
      ),
    );
    if (linked == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: C.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(broken ? tr('Wireframe ที่ผูกไว้ถูกลบไปแล้ว') : tr('ยังไม่ได้ผูกกับ Wireframe'),
              style: TextStyle(fontSize: 12.5, color: broken ? C.danger : C.muted)),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('sf-create-wireframe'),
            style: FilledButton.styleFrom(backgroundColor: wc.main, visualDensity: VisualDensity.compact),
            onPressed: () => f.createWireframeFor(node.id),
            icon: const Icon(Icons.add_box_outlined, size: 16),
            label: Text(tr('สร้าง Wireframe สำหรับหน้าจอนี้')),
          ),
          const SizedBox(height: 8),
          Text(tr('หรือเลือก Wireframe ที่มีอยู่'), style: TextStyle(fontSize: 11.5, color: C.muted)),
          const SizedBox(height: 4),
          picker,
        ]),
      );
    }
    final doc = w.documentById(current!);
    final apiButtons = linked.components.where((c) => c.api != null).length;
    return Container(
      key: const ValueKey('sf-wireframe-card'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: wc.main.withValues(alpha: 0.35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: wc.tint,
          padding: const EdgeInsets.all(10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 72, child: WireframeThumbnail(diagram: linked, height: 64)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(doc?.name ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: wc.ink)),
                const SizedBox(height: 2),
                Text('${_deviceOf(linked)} ${linked.width.round()} × ${linked.height.round()} · ${tr('{0} ชิ้นส่วน', [linked.components.length])}',
                    style: TextStyle(fontSize: 11.5, color: C.muted)),
                if (apiButtons > 0) Text(tr('ปุ่มเรียก API {0}', [apiButtons]), style: TextStyle(fontSize: 11.5, color: C.muted)),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilledButton.icon(
              key: const ValueKey('sf-open-wireframe'),
              style: FilledButton.styleFrom(backgroundColor: wc.main, visualDensity: VisualDensity.compact),
              onPressed: () => a.openWireframe(node.id),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: Text(tr('เปิด Wireframe')),
            ),
            const SizedBox(height: 8),
            Text(tr('เปลี่ยน Wireframe'), style: TextStyle(fontSize: 11.5, color: C.muted)),
            const SizedBox(height: 4),
            picker,
          ]),
        ),
      ]),
    );
  }
}

/// แถบล่างของแผงโหนด: ผลตรวจเฉพาะโหนดนี้
class _NodeRules extends StatelessWidget {
  const _NodeRules({required this.node});
  final SfNode node;

  @override
  Widget build(BuildContext context) {
    final f = context.read<ScreenFlowController>();
    final w = context.read<WorkspaceController>();
    final mine = [
      for (final i in validateScreenFlow(f.diagram, workspace: w.workspace))
        if (i.tableId == node.id && i.severity != Severity.info) i,
    ];
    if (mine.isEmpty) {
      return Container(
        key: const ValueKey('sf-node-ok'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: C.primaryTint.withValues(alpha: 0.5), border: Border(top: BorderSide(color: C.borderSoft))),
        child: Row(children: [
          Icon(Icons.check_rounded, size: 15, color: C.primaryDark),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('ผ่านการตรวจแผนผัง'), style: TextStyle(fontSize: 12, color: C.primaryDark))),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: C.borderSoft))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final i in mine) Padding(padding: const EdgeInsets.only(bottom: 4), child: IssueCard(key: ValueKey('sf-node-issue-${i.code}'), issue: i)),
      ]),
    );
  }
}

class _NodeProps extends StatelessWidget {
  const _NodeProps({required this.node});
  final SfNode node;

  @override
  Widget build(BuildContext context) {
    final f = context.read<ScreenFlowController>();
    final d = f.diagram;
    final outs = [for (final e in d.edges) if (e.fromId == node.id) e];
    final ins = [for (final e in d.edges) if (e.toId == node.id) e];
    final screen = node.kind == SfKind.screen;
    Widget count(int n) => Text('$n', style: TextStyle(fontSize: 11, color: C.muted));
    return _Panel(
      icon: sfKindIcon(node.kind),
      title: node.title.isEmpty ? sfKindLabel(node.kind) : '${sfKindLabel(node.kind)} · ${node.title}',
      subtitle: tr('ไปต่อ {0} · มาจาก {1}', [outs.length, ins.length]),
      onDelete: f.deleteSelection,
      deleteTip: tr('ลบหน้าจอ'),
      footer: _NodeRules(node: node),
      children: [
        CommitField(
          key: ValueKey('sf-title-${node.id}-${node.title}'),
          label: tr('ชื่อ'),
          value: node.title,
          onCommit: (v) => f.setTitle(node.id, v.trim()),
        ),
        const SizedBox(height: 12),
        LabeledField(
          label: tr('ชนิด'),
          child: KeyedSubtree(
            key: const ValueKey('sf-kind'),
            child: Dropdown<SfKind>(
              value: node.kind,
              items: SfKind.values,
              labelOf: sfKindLabel,
              onChanged: (k) => f.updateNodes([node.id], (n) => n.kind = k),
            ),
          ),
        ),
        if (screen) ...[
          const SizedBox(height: 16),
          _sec(tr('Wireframe ของหน้าจอนี้')),
          _WireframeCard(node: node),
        ],
        const SizedBox(height: 16),
        _sec(tr('ไปต่อ'), trailing: count(outs.length)),
        for (final e in outs) _EdgeRow(edge: e, outgoing: true),
        if (outs.isEmpty) Text(tr('— ไม่มี —'), style: TextStyle(fontSize: 12, color: C.muted)),
        const SizedBox(height: 10),
        _sec(tr('มาจาก'), trailing: count(ins.length)),
        for (final e in ins) _EdgeRow(edge: e, outgoing: false),
        if (ins.isEmpty) Text(tr('— ไม่มี —'), style: TextStyle(fontSize: 12, color: C.muted)),
        const SizedBox(height: 16),
        _sec(tr('สีเส้นขอบ')),
        ColorSwatchRow(
          keyPrefix: 'sf-color',
          palette: kWfPalette.take(8).toList(),
          current: node.color,
          onPick: (v) => f.updateNodes([node.id], (n) => n.color = v),
          onCustom: () async {
            final r = await showColorPickerDialog(context, title: tr('สีเส้นขอบ (กำหนดเอง)'), initial: node.color, presets: kWfPalette);
            if (r != null) f.updateNodes([node.id], (n) => n.color = r.argb);
          },
        ),
      ],
    );
  }
}

class _EdgeProps extends StatelessWidget {
  const _EdgeProps({required this.edge});
  final SfEdge edge;

  /// ชิ้นส่วนใน Wireframe ของหน้าต้นทางที่ข้อความตรงกับ trigger และเรียก API อยู่ (ใช้แนะนำ endpoint)
  static WfComponent? suggestion(ScreenFlowController f, SfEdge e) {
    if (e.api != null) return null;
    final from = f.diagram.nodeById(e.fromId);
    final wf = from == null ? null : f.linkedWireframe(from);
    final t = e.label.trim().toLowerCase();
    if (wf == null || t.isEmpty) return null;
    for (final c in wf.components) {
      final ct = c.text.trim().toLowerCase();
      if (c.api != null && ct.isNotEmpty && (ct == t || ct.contains(t) || t.contains(ct))) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final f = context.read<ScreenFlowController>();
    final w = context.read<WorkspaceController>();
    final dc = C.doc(DocType.screenflow);
    final d = f.diagram;
    final from = d.nodeById(edge.fromId), to = d.nodeById(edge.toId);
    Widget end(SfNode? n) {
      final wf = n == null ? null : f.linkedWireframe(n);
      return Expanded(
        child: Column(children: [
          if (wf != null)
            SizedBox(width: 72, child: WireframeThumbnail(diagram: wf, height: 44))
          else
            Icon(n == null ? Icons.help_outline_rounded : sfKindIcon(n.kind), size: 22, color: dc.main),
          const SizedBox(height: 4),
          Text(n == null ? '?' : sfNodeTitle(n),
              maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
    }

    final s = suggestion(f, edge);
    final sLabel = s == null ? null : _endpointLabel(w, s.api);
    return _Panel(
      icon: Icons.arrow_right_alt_rounded,
      title: tr('การเปลี่ยนหน้า'),
      subtitle: '${from == null ? '?' : sfKindLabel(from.kind)} → ${to == null ? '?' : sfKindLabel(to.kind)}',
      onDelete: f.deleteSelection,
      deleteTip: tr('ลบเส้นการเปลี่ยนหน้า'),
      children: [
        CommitField(
          key: ValueKey('sf-label-${edge.id}-${edge.label}'),
          label: tr('เมื่อ (trigger) เช่น กด Login'),
          value: edge.label,
          onCommit: (v) => f.updateEdge(edge.id, (e) => e.label = v.trim()),
        ),
        const SizedBox(height: 12),
        CommitField(
          key: ValueKey('sf-condition-${edge.id}-${edge.condition}'),
          label: tr('เงื่อนไข (ไม่บังคับ)'),
          value: edge.condition,
          onCommit: (v) => f.updateEdge(edge.id, (e) => e.condition = v.trim()),
        ),
        const SizedBox(height: 16),
        _sec(tr('จากหน้าไหนไปหน้าไหน')),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: C.borderSoft)),
          child: Row(children: [
            end(from),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward_rounded, size: 18, color: dc.main)),
            end(to),
          ]),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('sf-reverse'),
          onPressed: () => f.reverseEdge(edge.id),
          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
          label: Text(tr('สลับทิศทาง')),
        ),
        const SizedBox(height: 16),
        ApiRefPicker(value: edge.api, onChanged: (r) => f.updateEdge(edge.id, (e) => e.api = r)),
        if (s != null && sLabel != null) ...[
          const SizedBox(height: 6),
          Container(
            key: const ValueKey('sf-api-suggestion'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: C.palette.infoBg, borderRadius: BorderRadius.circular(9)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('ปุ่ม “{0}” ใน Wireframe เรียก {1}', [s.text.trim(), sLabel]), style: TextStyle(fontSize: 12, color: C.palette.infoText)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('sf-api-suggest'),
                  onPressed: () => f.updateEdge(edge.id, (e) => e.api = s.api),
                  child: Text(tr('ใช้ endpoint เดียวกัน')),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        _sec(tr('เส้นและป้าย')),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              key: const ValueKey('sf-reset-route'),
              onPressed: edge.hasManualRoute ? () => f.resetEdgeRoute(edge.id) : null,
              child: Text(tr('จัดเส้นอัตโนมัติ'), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: OutlinedButton(
              key: const ValueKey('sf-reset-label'),
              onPressed: edge.labelDx != 0 || edge.labelDy != 0 ? () => f.resetEdgeLabelPosition(edge.id) : null,
              child: Text(tr('ป้ายกลับที่เดิม'), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(tr('ลากจุดกลางเส้นเพื่อดัด · ลากป้ายเพื่อย้าย'), style: TextStyle(fontSize: 11.5, color: C.muted)),
      ],
    );
  }
}

class _MultiProps extends StatelessWidget {
  const _MultiProps({required this.ids});
  final Set<String> ids;

  @override
  Widget build(BuildContext context) {
    final f = context.read<ScreenFlowController>();
    Widget btn(String key, IconData icon, String tip, VoidCallback tap) =>
        IconButton(key: ValueKey(key), tooltip: tip, visualDensity: VisualDensity.compact, icon: Icon(icon, size: 18, color: C.muted), onPressed: tap);
    return _Panel(
      icon: Icons.select_all_rounded,
      title: tr('เลือก {0} หน้าจอ', [ids.length]),
      onDelete: f.deleteSelection,
      deleteTip: tr('ลบหน้าจอ'),
      children: [
        _sec(tr('จัดแนว')),
        Wrap(children: [
          btn('sf-al-left', Icons.align_horizontal_left_rounded, tr('จัดชิดซ้าย'), () => f.align(BoxAlign.left)),
          btn('sf-al-center', Icons.align_horizontal_center_rounded, tr('จัดกึ่งกลางแนวตั้ง'), () => f.align(BoxAlign.centerH)),
          btn('sf-al-top', Icons.align_vertical_top_rounded, tr('จัดชิดบน'), () => f.align(BoxAlign.top)),
          btn('sf-al-middle', Icons.align_vertical_center_rounded, tr('จัดกึ่งกลางแนวนอน'), () => f.align(BoxAlign.middle)),
        ]),
        const SizedBox(height: 10),
        _sec(tr('กระจาย / ขนาด')),
        Wrap(children: [
          btn('sf-dist-h', Icons.horizontal_distribute_rounded, tr('กระจายแนวนอน (3 ชิ้นขึ้นไป)'), () => f.distribute(horizontal: true)),
          btn('sf-dist-v', Icons.vertical_distribute_rounded, tr('กระจายแนวตั้ง (3 ชิ้นขึ้นไป)'), () => f.distribute(horizontal: false)),
          btn('sf-same-size', Icons.photo_size_select_small_rounded, tr('ขนาดเท่ากับชิ้นแรกที่เลือก'), f.sameSize),
        ]),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('sf-duplicate'),
          onPressed: f.duplicateSelection,
          icon: const Icon(Icons.file_copy_outlined, size: 16),
          label: Text(tr('ทำสำเนา')),
        ),
      ],
    );
  }
}

/// เส้นทางจากจุดเริ่มแรก: เดินตามเส้นแรกที่ยังไม่เคยไป (ไม่วน) สูงสุด 8 ขั้น
List<SfNode> sfMainPath(ScreenFlowDiagram d) {
  final start = d.nodes.where((n) => n.kind == SfKind.start).firstOrNull;
  if (start == null) return const [];
  final path = <SfNode>[start];
  final seen = {start.id};
  var cur = start;
  while (path.length < 8) {
    SfNode? next;
    for (final e in d.edges) {
      if (e.fromId != cur.id || seen.contains(e.toId)) continue;
      next = d.nodeById(e.toId);
      if (next != null) break;
    }
    if (next == null) break;
    path.add(next);
    seen.add(next.id);
    cur = next;
  }
  return path;
}

/// ไม่ได้เลือกอะไร: ตัวเลขสรุป · ปัญหา · หน้าจอที่ยังไม่ผูก Wireframe · เส้นทางจากจุดเริ่ม · จัดวาง
class _Overview extends StatelessWidget {
  const _Overview();

  @override
  Widget build(BuildContext context) {
    final f = context.watchContent<ScreenFlowController>();
    final w = context.watch<WorkspaceController>();
    final dc = C.doc(DocType.screenflow);
    final d = f.diagram;
    final issues = validateScreenFlow(d, workspace: w.workspace);
    final screens = [for (final n in d.nodes) if (n.kind == SfKind.screen) n];
    final unlinked = [for (final n in screens) if (f.linkedWireframe(n) == null) n];
    final withApi = d.edges.where((e) => e.api != null).length;
    final path = sfMainPath(d);
    Widget stat(String key, String value, String label) => Container(
          key: ValueKey(key),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: C.borderSoft)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: C.muted)),
          ]),
        );
    return _Panel(
      icon: Icons.alt_route_rounded,
      title: w.activeDocument.name,
      subtitle: tr('{0} หน้าจอ · {1} การเปลี่ยนหน้า', [d.nodes.length, d.edges.length]),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.1,
          children: [
            stat('sf-stat-nodes', '${d.nodes.length}', tr('หน้าจอ / จุด')),
            stat('sf-stat-edges', '${d.edges.length}', tr('การเปลี่ยนหน้า')),
            stat('sf-stat-linked', '${screens.length - unlinked.length}/${screens.length}', tr('หน้าจอผูก Wireframe')),
            stat('sf-stat-api', '$withApi', tr('เส้นที่เรียก API')),
          ],
        ),
        const SizedBox(height: 16),
        _sec(tr('ตรวจสอบแผนผัง'), trailing: Text('${issues.length}', style: TextStyle(fontSize: 11, color: C.muted))),
        if (d.nodes.isEmpty)
          Text(tr('วางจุดเริ่มและหน้าจอแล้วลากเส้นการเปลี่ยนหน้า ระบบจะตรวจให้'), style: TextStyle(fontSize: 12.5, color: C.muted))
        else if (issues.isEmpty)
          Text(tr('✓ ไม่พบปัญหา'), key: const ValueKey('sf-no-issues'), style: TextStyle(fontSize: 12.5, color: C.primaryDark))
        else
          for (final i in issues)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: IssueCard(
                key: ValueKey('sf-issue-${i.code}-${i.tableId ?? i.relationId}'),
                issue: i,
                onTap: () {
                  if (i.tableId != null) {
                    f.selectBox(i.tableId!);
                    f.reveal(i.tableId!, f.viewport);
                  } else if (i.relationId != null) {
                    f.selectEdge(i.relationId);
                  }
                },
              ),
            ),
        if (unlinked.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sec(tr('หน้าจอที่ยังไม่ผูก Wireframe')),
          for (final n in unlinked)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Expanded(child: Text(sfNodeTitle(n), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                TextButton(
                  key: ValueKey('sf-unlinked-${n.id}'),
                  onPressed: () => f.createWireframeFor(n.id),
                  child: Text(tr('สร้าง Wireframe')),
                ),
              ]),
            ),
        ],
        if (path.length > 1) ...[
          const SizedBox(height: 16),
          _sec(tr('เส้นทางจากจุดเริ่ม')),
          Wrap(spacing: 4, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final (i, n) in path.indexed) ...[
              if (i > 0) Icon(Icons.arrow_forward_rounded, size: 13, color: dc.main),
              InkWell(
                key: ValueKey('sf-path-${n.id}'),
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  f.selectBox(n.id);
                  f.reveal(n.id, f.viewport);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: n.kind == SfKind.screen ? dc.tint : null,
                    borderRadius: BorderRadius.circular(n.kind == SfKind.screen ? 4 : 10),
                    border: n.kind == SfKind.screen ? null : Border.all(color: dc.main),
                  ),
                  child: Text(sfNodeTitle(n), style: TextStyle(fontSize: 12, color: dc.ink)),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 4),
          Text(tr('ตามเส้นแรกของแต่ละหน้า · คลิกชื่อเพื่อไปที่หน้านั้น'), style: TextStyle(fontSize: 11.5, color: C.muted)),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const ValueKey('sf-layout'),
          onPressed: d.nodes.length < 2
              ? null
              : () {
                  if (f.autoLayout()) f.fit(f.viewport);
                },
          icon: const Icon(Icons.east_rounded, size: 16),
          label: Text(tr('จัดวางซ้ายไปขวา')),
        ),
      ],
    );
  }
}
