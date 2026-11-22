import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/layout/box_ops.dart' show BoxAlign;
import '../../core/layout/ortho_route.dart';
import '../../core/layout/screenflow_geometry.dart';
import '../../core/models/screenflow_model.dart';
import '../../core/models/workspace.dart';
import '../../core/validate/issue.dart';
import '../../state/app_settings.dart';
import '../flowchart/fc_minimap.dart' show MinimapFrame, kFcMinimapSize, kFcMinimapMinCanvasWidth;
import '../../core/validate/screenflow_validator.dart';
import '../../state/screenflow_controller.dart';
import '../../state/workspace_controller.dart';
import '../canvas/box_canvas.dart';
import '../canvas/canvas_chrome.dart';
import '../canvas/context_menu.dart';
import '../canvas/inline_text_editor.dart';
import '../shortcuts.dart' show Cmd;
import '../theme.dart';
import 'sf_actions.dart';
import 'sf_painter.dart';
import '../../core/layout/route_edit.dart' show routeLabelPoint;
import '../../core/layout/diagram_geometry.dart' show kGridSize;
import '../../state/doc_controller.dart';

IconData sfKindIcon(SfKind k) => switch (k) {
      SfKind.start => Icons.play_circle_outline_rounded,
      SfKind.screen => Icons.web_outlined,
      SfKind.external => Icons.open_in_new_rounded,
      SfKind.end => Icons.stop_circle_outlined,
    };

/// คีย์ลัดของเครื่องมือวางโหนด
String sfKindShortcut(SfKind k) => switch (k) {
      SfKind.start || SfKind.end => 'O',
      SfKind.screen => 'P',
      SfKind.external => 'E',
    };

/// พื้นที่วาดของแท็บ Screen Flow
class ScreenFlowCanvas extends StatefulWidget {
  const ScreenFlowCanvas({super.key, this.focusNode});
  final FocusNode? focusNode;

  @override
  State<ScreenFlowCanvas> createState() => _ScreenFlowCanvasState();
}

class _ScreenFlowCanvasState extends BoxCanvasState<ScreenFlowCanvas, ScreenFlowController> {
  @override
  FocusNode? get focusNode => widget.focusNode;

  @override
  String get canvasKey => 'sf-canvas';

  @override
  BoxHit hitTest(ScreenFlowController c, Offset world) {
    final d = c.diagram;
    final routes = sfRoutes(d);
    for (final e in d.edges.reversed) {
      final r = routes[e.id];
      final rect = r == null ? null : sfLabelRect(e, r);
      if (rect != null && rect.contains(world)) return (box: null, edge: e.id);
    }
    final edge = sfEdgeAt(d, world.dx, world.dy, tolerance: 6 / c.scale, routes: routes);
    final node = sfNodeAt(d, world.dx, world.dy, tol: 2 / c.scale);
    if (node != null && edge != null) {
      if (distanceToRoute(routes[edge]!, world.dx, world.dy) <= 3 / c.scale) return (box: null, edge: edge);
      return (box: node.id, edge: null);
    }
    return (box: node?.id, edge: edge);
  }

  @override
  bool isSelectTool(ScreenFlowController c) => c.tool == SfTool.select;

  bool _handleDrag = false; // กำลังลากจุดจับของเส้น (false = ลากป้าย)
  String? _labelEdge;

  @override
  bool edgeDragStart(ScreenFlowController c, Offset world) {
    final h = c.edgeHandleAt(world);
    if (h != null) {
      c.beginEdgeHandle(h);
      _handleDrag = true;
      _labelEdge = null;
      return true;
    }
    final e = c.selectedEdge;
    final r = e == null ? null : sfRoutes(c.diagram)[e.id];
    if (e != null && r != null && sfLabelRect(e, r)?.contains(world) == true) {
      c.beginEdgeLabelDrag();
      _handleDrag = false;
      _labelEdge = e.id;
      return true;
    }
    return false;
  }

  @override
  void edgeDragUpdate(ScreenFlowController c, DragUpdateDetails u) {
    if (_handleDrag) {
      c.edgeHandleTo(c.toWorld(u.localPosition), grid: snap ? kGridSize : null);
    } else if (_labelEdge != null) {
      c.edgeLabelDragBy(_labelEdge!, u.delta.dx / c.scale, u.delta.dy / c.scale);
    }
  }

  @override
  void edgeDragEnd(ScreenFlowController c) {
    if (_handleDrag) {
      c.endEdgeHandle();
    } else if (_labelEdge != null) {
      c.endEdgeLabelDrag();
    }
    _handleDrag = false;
    _labelEdge = null;
  }

  @override
  void resetTool(ScreenFlowController c) => c.setTool(SfTool.select);

  @override
  bool trackCursor(ScreenFlowController c) => c.linkSource != null;

  @override
  void selectEdge(ScreenFlowController c, String id) => c.selectEdge(id);

  @override
  void doubleTap(ScreenFlowController c, BoxHit hit) {
    final n = hit.box == null ? null : c.diagram.nodeById(hit.box!);
    if (n != null && n.kind == SfKind.screen) {
      // ดับเบิลคลิกหน้าจอ = เปิด Wireframe ที่ผูกไว้ (ยังไม่ผูก = พิมพ์ชื่อ)
      if (c.linkedWireframe(n) != null) {
        ScreenFlowActions(context).openWireframe(n.id);
        return;
      }
    }
    if (hit.edge != null) {
      c.beginEditEdge(hit.edge!);
    } else if (hit.box != null) {
      c.beginEdit(hit.box!);
    }
  }

  @override
  void toolTap(ScreenFlowController c, Offset world, BoxHit hit) {
    switch (c.tool) {
      case SfTool.node:
        final n = c.addNode(c.toolKind, world.dx, world.dy, snap: snap);
        if (n != null) c.beginEdit(n.id);
      case SfTool.edge:
        if (hit.box == null) {
          c.escape();
          return;
        }
        final e = c.linkClick(hit.box!);
        if (e != null) c.beginEditEdge(e.id);
      case SfTool.select:
        break;
    }
  }

  @override
  bool acceptsDrop(Object? data) => data is SfKind;

  @override
  void drop(ScreenFlowController c, Object data, Offset world) {
    if (data is! SfKind) return;
    final n = c.addNode(data, world.dx, world.dy, snap: snap);
    if (n != null) c.beginEdit(n.id);
  }

  @override
  void contextMenu(ScreenFlowController c, TapDownDetails t, Offset world, BoxHit hit) {
    final a = ScreenFlowActions(context);
    if (hit.box != null) {
      final n = c.diagram.nodeById(hit.box!)!;
      if (!c.selectedIds.contains(n.id)) c.selectBox(n.id);
      final ids = c.selectedIds;
      final many = ids.length > 1;
      final linked = c.linkedWireframe(n) != null;
      showContextMenu(context, t.globalPosition, [
        MenuSpec(tr('แก้ชื่อ'), Icons.edit_outlined, () => c.beginEdit(n.id), shortcut: 'F2', enabled: !many),
        if (n.kind == SfKind.screen && !many)
          linked
              ? MenuSpec(tr('เปิด Wireframe ของหน้าจอนี้'), Icons.web_outlined, () => a.openWireframe(n.id))
              : MenuSpec(tr('สร้าง Wireframe สำหรับหน้าจอนี้'), Icons.add_box_outlined, () => c.createWireframeFor(n.id)),
        MenuSpec(tr('ลากเส้นการเปลี่ยนหน้าออกจากตัวนี้'), Icons.arrow_right_alt_rounded, () {
          c.setTool(SfTool.edge);
          c.linkClick(n.id);
        }, enabled: !many),
        MenuSpec(tr('คัดลอก'), Icons.copy_rounded, a.copy, shortcut: 'Ctrl+C'),
        MenuSpec(tr('ทำสำเนา'), Icons.file_copy_outlined, c.duplicateSelection, shortcut: 'Ctrl+D'),
        if (many) ...[
          null,
          MenuSpec(tr('จัดชิดบน'), Icons.align_vertical_top_rounded, () => c.align(BoxAlign.top)),
          MenuSpec(tr('จัดชิดซ้าย'), Icons.align_horizontal_left_rounded, () => c.align(BoxAlign.left)),
        ],
        null,
        MenuSpec(many ? tr('ลบ {0} หน้าจอ', [ids.length]) : tr('ลบหน้าจอ'), Icons.delete_outline, c.deleteSelection,
            shortcut: 'Del', danger: true),
      ]);
      return;
    }
    if (hit.edge != null) {
      final e = c.diagram.edgeById(hit.edge!)!;
      c.selectEdge(e.id);
      showContextMenu(context, t.globalPosition, [
        MenuSpec(tr('แก้ป้ายเส้น'), Icons.edit_outlined, () => c.beginEditEdge(e.id), shortcut: 'F2'),
        MenuSpec(tr('สลับทิศทาง'), Icons.swap_horiz_rounded, () => c.reverseEdge(e.id)),
        MenuSpec(tr('รีเซ็ตเส้น (จัดอัตโนมัติ)'), Icons.timeline_rounded, () => c.resetEdgeRoute(e.id), enabled: e.hasManualRoute),
        MenuSpec(tr('ย้ายป้ายกลับที่เดิม'), Icons.label_outline_rounded, () => c.resetEdgeLabelPosition(e.id),
            enabled: e.labelDx != 0 || e.labelDy != 0),
        null,
        MenuSpec(tr('ลบเส้นการเปลี่ยนหน้า'), Icons.delete_outline, c.deleteSelection, shortcut: 'Del', danger: true),
      ]);
      return;
    }
    c.clearSelection();
    void add(SfKind k) {
      final n = c.addNode(k, world.dx, world.dy, snap: snap);
      if (n != null) c.beginEdit(n.id);
    }

    showContextMenu(context, t.globalPosition, [
      for (final k in SfKind.values) MenuSpec(tr('วาง{0}ที่นี่', [sfKindLabel(k)]), sfKindIcon(k), () => add(k), shortcut: sfKindShortcut(k)),
      null,
      MenuSpec(tr('วาง'), Icons.paste_rounded, a.paste, shortcut: 'Ctrl+V'),
      MenuSpec(tr('เลือกทั้งหมด'), Icons.select_all_rounded, c.selectAll, shortcut: 'Ctrl+A', enabled: c.diagram.nodes.isNotEmpty),
      MenuSpec(tr('จัดวางอัตโนมัติ (ซ้ายไปขวา)'), Icons.account_tree_outlined, () {
        if (c.autoLayout()) c.fit(c.viewport);
      }, enabled: c.diagram.nodes.length > 1),
      MenuSpec(tr('พอดีหน้าจอ'), Icons.fit_screen_outlined, () => c.fit(c.viewport), shortcut: 'Ctrl+0'),
      MenuSpec(tr('Export ภาพ PNG / SVG'), Icons.image_outlined, () => a.run(Cmd.exportImage)),
    ]);
  }

  @override
  CustomPainter foregroundPainter(ScreenFlowController c, Rect? marquee) {
    final w = context.read<WorkspaceController>();
    // ป้าย endpoint ของเส้นที่เรียก API
    final apiBadges = <String, String>{};
    for (final e in c.diagram.edges) {
      final a = e.api;
      if (a == null) continue;
      final ep = w.documentById(a.docId)?.api?.endpointById(a.endpointId);
      if (ep != null) apiBadges[e.id] = '${ep.method.name.toUpperCase()} ${ep.path}';
    }
    return ScreenFlowScreenPainter(
      diagram: c.diagram,
      offset: c.offset,
      scale: c.scale,
      wireframeOf: (id) => w.documentById(id)?.wireframe,
      selectedNodes: c.selectedIds,
      selectedEdge: c.selectedEdgeId,
      dropNode: c.dropNodeId,
      dropPort: c.dropPort,
      linkSource: c.linkSource,
      linkCursor: cursor,
      marquee: marquee,
      hideTextOf: c.editing?.id,
      thumbnails: c.showThumbnails,
      apiBadges: apiBadges,
      repaint: cursor,
    );
  }

  @override
  List<Widget> overlays(ScreenFlowController c, Size size) {
    final editing = c.editing;
    Widget? editor;
    if (editing != null) {
      Rect? world;
      String initial = '';
      if (editing.isEdge) {
        final e = c.diagram.edgeById(editing.id);
        final r = e == null ? null : sfRoutes(c.diagram)[e.id];
        if (r != null) {
          final (ax, ay) = routeLabelPoint(r, e!);
          world = Rect.fromCenter(center: Offset(ax, ay), width: 180, height: 26);
          initial = e.label;
        }
      } else {
        final n = c.diagram.nodeById(editing.id);
        if (n != null) {
          world = n.kind == SfKind.screen
              ? Rect.fromLTWH(n.x, n.y, n.w, kSfTitleBar)
              : Rect.fromLTWH(n.x, n.y, n.w, n.h);
          initial = n.title;
        }
      }
      if (world != null) {
        var r = toScreenRect(c, world);
        if (r.height < 28) r = Rect.fromLTWH(r.left, r.top, r.width, 28);
        if (r.width < 120) r = Rect.fromCenter(center: r.center, width: 120, height: r.height);
        editor = InlineTextEditor(
          key: ValueKey('sf-edit-${editing.id}'),
          fieldKey: const ValueKey('sf-inline-field'),
          rect: r,
          initial: initial,
          multiline: false,
          fontSize: 13 * c.scale,
          onCommit: (text) {
            if (c.editing == editing) c.commitEditing(text);
          },
          onCancel: c.cancelEditing,
          onDone: () => widget.focusNode?.requestFocus(),
        );
      }
    }
    return [
      ?editor,
      Positioned(
        right: 14,
        bottom: 14,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (size.width >= kFcMinimapMinCanvasWidth && size.height >= 360 && c.diagram.nodes.isNotEmpty) ...[
            _SfMinimap(canvas: size),
            const SizedBox(height: 8),
          ],
          CanvasZoomBar(controller: c, size: size, keyPrefix: 'sf', extra: [
          IconButton(
            key: const ValueKey('sf-autolayout'),
            tooltip: tr('จัดวางอัตโนมัติ (ซ้ายไปขวา)'),
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: () {
              if (c.autoLayout()) c.fit(size);
            },
            icon: const Icon(Icons.account_tree_outlined),
          ),
        ]),
        ]),
      ),
      if (c.diagram.nodes.isEmpty)
        IgnorePointer(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.alt_route_rounded, size: 44, color: C.muted.withValues(alpha: 0.6)),
              const SizedBox(height: 10),
              Text(tr('Screen Flow ว่างอยู่'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.muted)),
              const SizedBox(height: 4),
              Text(tr('วางจุดเริ่มและหน้าจอจากแผงซ้าย (O / P / E) แล้วลากเส้นการเปลี่ยนหน้า (F)'), style: TextStyle(color: C.muted)),
            ]),
          ),
        ),
    ];
  }
}

/// แถบเครื่องมือเต็มความกว้างเหนือแคนวาส Screen Flow (ตามดีไซน์ Phase 16):
/// [เลือก S | การเปลี่ยนหน้า F] · จัดวางซ้ายไปขวา · ภาพย่อ Wireframe ······ ผลตรวจ · Snap · ส่งออกภาพ
/// การวางโหนดอยู่ที่แผงซ้าย ; แคบ = ไอคอนอย่างเดียว ; ปานกลาง = ป้ายสั้น
class ScreenFlowToolbar extends StatelessWidget {
  const ScreenFlowToolbar({super.key});

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, box) => _ToolbarBody(compact: box.maxWidth < 760, medium: box.maxWidth < 1000));
}

class _ToolbarBody extends StatelessWidget {
  const _ToolbarBody({required this.compact, required this.medium});
  final bool compact, medium;

  @override
  Widget build(BuildContext context) {
    final f = context.watchContentIdle<ScreenFlowController>();
    final w = context.watch<WorkspaceController>();
    final s = context.watch<AppSettings>();
    final dc = C.doc(DocType.screenflow);
    final issues = validateScreenFlow(f.diagram, workspace: w.workspace);
    final problems = issues.where((i) => i.severity != Severity.info).length;

    Widget tool(String key, String label, IconData icon, String shortcut, bool on, VoidCallback onTap) => Tooltip(
          message: '$label ($shortcut)',
          child: InkWell(
            key: ValueKey(key),
            borderRadius: BorderRadius.circular(7),
            onTap: onTap,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: on ? C.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                boxShadow: on ? [BoxShadow(color: C.palette.shadow.withValues(alpha: 0.12), blurRadius: 2, offset: const Offset(0, 1))] : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 15, color: on ? dc.ink : C.muted),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(fontSize: 12, fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
                  const SizedBox(width: 5),
                  Text(shortcut, style: TextStyle(fontSize: 11, color: C.muted, fontFamily: kMono, fontFamilyFallback: const ['Consolas'])),
                ],
              ]),
            ),
          ),
        );

    Widget button(String key, IconData icon, String label, VoidCallback? onTap, {bool outlined = false, bool on = false}) => Tooltip(
          message: label,
          child: InkWell(
            key: ValueKey(key),
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Container(
              height: 30,
              padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: outlined ? Border.all(color: C.border) : null,
                color: on ? dc.tint : (outlined ? C.surface : null),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 15, color: onTap == null ? C.muted.withValues(alpha: 0.5) : (on ? dc.ink : C.muted)),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(fontSize: 12, color: onTap == null ? C.muted : (on ? dc.ink : C.text))),
                ],
              ]),
            ),
          ),
        );

    final ok = problems == 0;
    final rules = Tooltip(
      message: ok ? tr('ตรวจแผนผังแล้วไม่พบปัญหา') : tr('ดูปัญหาในแผนผังนี้'),
      child: InkWell(
        key: const ValueKey('sf-rules'),
        borderRadius: BorderRadius.circular(11),
        onTap: f.clearSelection, // ไม่ได้เลือกอะไร = แผงขวาแสดงภาพรวมพร้อมรายการปัญหา
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: ok ? C.primaryTint : C.palette.warnBg, borderRadius: BorderRadius.circular(11)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ok ? Icons.check_rounded : Icons.warning_amber_rounded, size: 13, color: ok ? C.primaryDark : C.palette.warnText),
            const SizedBox(width: 4),
            Text(
              ok ? (compact || medium ? tr('ผ่าน') : tr('ไม่พบปัญหา')) : tr('{0} ปัญหา', [problems]),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: ok ? C.primaryDark : C.palette.warnText),
            ),
          ]),
        ),
      ),
    );

    final snap = Tooltip(
      message: tr('จัดแนวตามตาราง (Snap) — กด Alt ค้างตอนลากเพื่อข้ามชั่วคราว'),
      child: InkWell(
        key: const ValueKey('sf-snap'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => s.setSnapToGrid(!s.snapToGrid),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: s.snapToGrid ? C.primaryTint : null, borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.grid_4x4_rounded, size: 15, color: s.snapToGrid ? C.primaryDark : C.muted),
            if (!compact && !medium) ...[
              const SizedBox(width: 5),
              Text('Snap', style: TextStyle(fontSize: 12, color: s.snapToGrid ? C.primaryDark : C.text)),
            ],
          ]),
        ),
      ),
    );

    final export = Tooltip(
      message: tr('Export ภาพ PNG / SVG'),
      child: Material(
        color: dc.main,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: const ValueKey('sf-export'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => ScreenFlowActions(context).run(Cmd.exportImage),
          child: SizedBox(
            height: 30,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.image_outlined, size: 15, color: Colors.white),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(tr('ส่งออกภาพ'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );

    return Container(
      key: const ValueKey('sf-toolbar'),
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: C.surface, border: Border(bottom: BorderSide(color: C.borderSoft))),
      child: Row(children: [
        Flexible(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(9)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  tool('sf-tool-select', tr('เลือก'), Icons.near_me_outlined, 'S', f.tool == SfTool.select, () => f.setTool(SfTool.select)),
                  const SizedBox(width: 2),
                  tool('sf-tool-edge', tr('การเปลี่ยนหน้า'), Icons.arrow_right_alt_rounded, 'F', f.tool == SfTool.edge, () => f.setTool(SfTool.edge)),
                ]),
              ),
              Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 8), color: C.border),
              button('sf-autolayout', Icons.east_rounded, tr('จัดวางซ้ายไปขวา'), f.diagram.nodes.length < 2
                  ? null
                  : () {
                      if (f.autoLayout()) f.fit(f.viewport);
                    }, outlined: true),
              const SizedBox(width: 4),
              button('sf-thumbnails', Icons.web_outlined, tr('ภาพย่อ Wireframe'), f.toggleThumbnails, on: f.showThumbnails),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        rules,
        const SizedBox(width: 6),
        snap,
        const SizedBox(width: 6),
        export,
      ]),
    );
  }
}

/// minimap มุมขวาล่างของแคนวาส Screen Flow : โหนดย่อ + กรอบส่วนที่มองเห็น ; คลิก/ลาก = เลื่อนมุมมอง
class _SfMinimap extends StatelessWidget {
  const _SfMinimap({required this.canvas});
  final Size canvas;

  @override
  Widget build(BuildContext context) {
    final f = context.watch<ScreenFlowController>();
    final nodes = f.diagram.nodes;
    if (nodes.isEmpty || canvas.isEmpty) return const SizedBox.shrink();
    Rect? b;
    for (final n in nodes) {
      final r = Rect.fromLTWH(n.x, n.y, n.w, n.h);
      b = b == null ? r : b.expandToInclude(r);
    }
    final visible = Rect.fromPoints(f.toWorld(Offset.zero), f.toWorld(Offset(canvas.width, canvas.height)));
    final frame = MinimapFrame(b!.inflate(20).expandToInclude(visible), kFcMinimapSize);
    void go(Offset local) => f.revealPoint(frame.toWorld(local), canvas);
    return Semantics(
      label: tr('แผนที่ย่อ'),
      child: Tooltip(
        message: tr('แผนที่ย่อ — คลิกหรือลากเพื่อเลื่อนมุมมอง'),
        waitDuration: const Duration(milliseconds: 600),
        child: GestureDetector(
          key: const ValueKey('sf-minimap'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (e) => go(e.localPosition),
          onPanStart: (e) => go(e.localPosition),
          onPanUpdate: (e) => go(e.localPosition),
          child: Container(
            width: kFcMinimapSize.width,
            height: kFcMinimapSize.height,
            decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: C.border)),
            clipBehavior: Clip.antiAlias,
            child: CustomPaint(painter: _SfMinimapPainter(f, frame, visible)),
          ),
        ),
      ),
    );
  }
}

class _SfMinimapPainter extends CustomPainter {
  _SfMinimapPainter(this.f, this.frame, this.visible);
  final ScreenFlowController f;
  final MinimapFrame frame;
  final Rect visible;

  @override
  void paint(Canvas canvas, Size size) {
    final col = C.doc(DocType.screenflow).main;
    canvas.save();
    canvas.translate(frame.origin.dx - frame.world.left * frame.k, frame.origin.dy - frame.world.top * frame.k);
    canvas.scale(frame.k);
    for (final n in f.diagram.nodes) {
      final r = Rect.fromLTWH(n.x, n.y, n.w, n.h);
      final screen = n.kind == SfKind.screen;
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(screen ? 6 : r.shortestSide / 2)),
        Paint()..color = (n.kind == SfKind.end ? C.muted : col).withValues(alpha: screen ? 0.35 : 0.5),
      );
    }
    canvas.restore();
    final view = frame.rectToMini(visible);
    canvas.drawRect(view, Paint()..color = col.withValues(alpha: 0.08));
    canvas.drawRect(view, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = col);
  }

  @override
  bool shouldRepaint(_SfMinimapPainter old) => true;
}
