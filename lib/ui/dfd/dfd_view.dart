import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/layout/diagram_geometry.dart' show kGridSize;
import '../../core/models/dfd_model.dart';
import '../../core/validate/dfd_validator.dart';
import '../../core/validate/issue.dart';
import '../../state/app_settings.dart';
import '../../state/dfd_controller.dart';
import '../../state/project_controller.dart';
import '../../state/workspace_controller.dart';
import '../../core/models/workspace.dart';
import '../workspace_issues_dialog.dart';
import '../canvas/context_menu.dart';
import '../canvas/dot_grid_painter.dart';
import '../shortcuts.dart' show Cmd;
import '../theme.dart';
import 'dfd_actions.dart';
import 'dfd_minimap.dart';
import 'dfd_painter.dart';
import '../note_pins.dart';
import '../../state/doc_controller.dart';

/// พื้นที่วาดของแท็บ DFD: เลื่อน/ซูม, วางวัตถุ, ลากย้าย, กรอบเลือก, ต่อเส้นข้อมูล, เมนูคลิกขวา
class DfdCanvas extends StatefulWidget {
  const DfdCanvas({super.key, this.focusNode});

  /// โฟกัสของหน้าหลัก (รับคีย์ลัด) — ขอกลับมาทุกครั้งที่คลิกบนแคนวาส
  final FocusNode? focusNode;

  @override
  State<DfdCanvas> createState() => _DfdCanvasState();
}

enum _Drag { none, move, marquee, pan, resize, boundary, flowHandle, label }

class _DfdCanvasState extends State<DfdCanvas> {
  _Drag _drag = _Drag.none;
  Offset? _marqueeStart, _marqueeEnd; // พิกัดจอ (ในพื้นที่แคนวาส)
  final ValueNotifier<Offset?> _cursor = ValueNotifier(null); // พิกัดแผนภาพ ใช้ทำเส้นพรีวิวตอนต่อ flow
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastTapId;
  String? _labelFlow; // เส้นที่กำลังลากป้ายชื่อ

  @override
  void dispose() {
    _cursor.dispose();
    super.dispose();
  }

  bool get _ctrlOrShift => HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isShiftPressed;
  bool get _spaceDown => HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.space);

  /// ชนิดที่คลิกโดน: วัตถุก่อน แล้วค่อยเส้น/ป้ายชื่อ
  ({DfdNode? node, String? flow, DfdBoundary? boundary}) _hit(DfdController d, Offset world) {
    final n = dfdNodeAt(d.diagram, world.dx, world.dy);
    if (n != null) return (node: n, flow: null, boundary: null);
    final tol = 7 / d.scale;
    var flow = dfdFlowAt(d.diagram, world.dx, world.dy, tolerance: tol);
    if (flow == null) {
      // ป้ายชื่อที่ยื่นออกนอกเส้นก็คลิกโดนได้
      final routes = dfdRoutes(d.diagram);
      for (final f in d.diagram.flows) {
        final r = routes[f.id];
        if (r != null && f.label.trim().isNotEmpty && dfdLabelRect(f, r).contains(world)) {
          flow = f.id;
          break;
        }
      }
    }
    if (flow != null) return (node: null, flow: flow, boundary: null);
    return (node: null, flow: null, boundary: dfdBoundaryAt(d.diagram, world.dx, world.dy, tol: tol));
  }

  Future<void> _tapUp(Offset local) async {
    widget.focusNode?.requestFocus();
    final d = context.read<DfdController>();
    final actions = DfdActions(context);
    final world = d.toWorld(local);
    final snap = context.read<AppSettings>().snapToGrid;
    final hit = _hit(d, world);

    switch (d.tool) {
      case DfdTool.select:
        final now = clock.now();
        final id = hit.node?.id ?? hit.flow ?? hit.boundary?.id;
        final doubleTap = id != null && id == _lastTapId && now.difference(_lastTap).inMilliseconds < 400;
        _lastTap = now;
        _lastTapId = id;
        if (hit.node != null) {
          d.selectNode(hit.node!.id, add: _ctrlOrShift);
          if (doubleTap) await actions.renameNode(hit.node!);
        } else if (hit.flow != null) {
          d.selectFlow(hit.flow);
          if (doubleTap) await actions.editFlowLabel(d.diagram.flowById(hit.flow!)!);
        } else if (hit.boundary != null) {
          d.selectBoundary(hit.boundary!.id);
          if (doubleTap) await actions.renameBoundary(hit.boundary!);
        } else {
          d.clearSelection();
        }
      case DfdTool.entity || DfdTool.process || DfdTool.store:
        final kind = switch (d.tool) {
          DfdTool.entity => DfdKind.entity,
          DfdTool.process => DfdKind.process,
          _ => DfdKind.store,
        };
        final n = d.addNode(kind, world.dx, world.dy, snap: snap);
        if (n != null) await actions.renameNode(n);
      case DfdTool.flow:
        if (hit.node == null) {
          d.escape();
          return;
        }
        final f = d.linkClick(hit.node!.id);
        if (f != null) await actions.editFlowLabel(f);
    }
  }

  void _secondaryTap(TapDownDetails t) {
    final d = context.read<DfdController>();
    final actions = DfdActions(context);
    if (d.tool != DfdTool.select) {
      d.setTool(DfdTool.select);
      return;
    }
    final world = d.toWorld(t.localPosition);
    final hit = _hit(d, world);
    final snap = context.read<AppSettings>().snapToGrid;
    if (hit.node != null) {
      final n = hit.node!;
      if (!d.selectedNodeIds.contains(n.id)) d.selectNode(n.id);
      final ids = d.selectedNodeIds;
      final many = ids.length > 1;
      showContextMenu(context, t.globalPosition, [
        MenuSpec(tr('เปลี่ยนชื่อ'), Icons.drive_file_rename_outline, () => actions.renameNode(n), shortcut: 'F2', enabled: !many),
        MenuSpec(tr('ลากเส้นข้อมูลออกจากตัวนี้'), Icons.arrow_right_alt_rounded, () {
          d.setTool(DfdTool.flow);
          d.linkClick(n.id);
        }, enabled: !many),
        MenuSpec(tr('สีวัตถุ…'), Icons.palette_outlined, () => actions.pickNodesColor(ids, current: n.color)),
        MenuSpec(tr('ใช้สีตามชนิด'), Icons.format_color_reset_outlined, () => d.setNodesColor(ids, null),
            enabled: ids.any((i) => d.diagram.nodeById(i)?.color != null)),
        MenuSpec(tr('คัดลอก'), Icons.copy_rounded, actions.copy, shortcut: 'Ctrl+C'),
        MenuSpec(tr('ทำสำเนา'), Icons.file_copy_outlined, d.duplicateSelection, shortcut: 'Ctrl+D'),
        MenuSpec(tr('ครอบด้วยขอบเขตระบบ'), Icons.crop_free_rounded, d.addBoundaryAround),
        null,
        MenuSpec(many ? tr('ลบ {0} วัตถุ', [ids.length]) : tr('ลบวัตถุ'), Icons.delete_outline, d.deleteSelection,
            shortcut: 'Del', danger: true),
      ]);
    } else if (hit.boundary != null) {
      final b = hit.boundary!;
      d.selectBoundary(b.id);
      showContextMenu(context, t.globalPosition, [
        MenuSpec(tr('เปลี่ยนชื่อ'), Icons.drive_file_rename_outline, () => actions.renameBoundary(b), shortcut: 'F2'),
        MenuSpec(tr('สีขอบเขต…'), Icons.palette_outlined, () => actions.pickBoundaryColor(b)),
        MenuSpec(tr('ใช้สีเริ่มต้น'), Icons.format_color_reset_outlined, () => d.setBoundaryColor(b.id, null),
            enabled: b.color != null),
        null,
        MenuSpec(tr('ลบขอบเขต (ไม่ลบวัตถุข้างใน)'), Icons.delete_outline, d.deleteSelection, shortcut: 'Del', danger: true),
      ]);
    } else if (hit.flow != null) {
      final f = d.diagram.flowById(hit.flow!)!;
      d.selectFlow(f.id);
      showContextMenu(context, t.globalPosition, [
        MenuSpec(tr('แก้ชื่อเส้นข้อมูล'), Icons.edit_outlined, () => actions.editFlowLabel(f), shortcut: 'F2'),
        MenuSpec(tr('สลับทิศทาง'), Icons.swap_horiz_rounded, () => d.reverseFlow(f.id)),
        MenuSpec(tr('ข้อมูลไหลสองทาง'), Icons.sync_alt_rounded, () => d.setFlowBidirectional(f.id, !f.bidirectional),
            checked: f.bidirectional ? true : null),
        MenuSpec(tr('สีเส้น…'), Icons.colorize_rounded, () => actions.pickFlowColor(f)),
        MenuSpec(tr('รีเซ็ตเส้น (จัดอัตโนมัติ)'), Icons.timeline_rounded, () => d.resetEdgeRoute(f.id), enabled: f.hasManualRoute),
        MenuSpec(tr('ย้ายป้ายกลับที่เดิม'), Icons.label_outline_rounded, () => d.resetEdgeLabelPosition(f.id),
            enabled: f.labelDx != 0 || f.labelDy != 0),
        null,
        MenuSpec(tr('ลบเส้นข้อมูล'), Icons.delete_outline, d.deleteSelection, shortcut: 'Del', danger: true),
      ]);
    } else {
      d.clearSelection();
      Future<void> add(DfdKind k) async {
        final n = d.addNode(k, world.dx, world.dy, snap: snap);
        if (n != null) await actions.renameNode(n);
      }

      showContextMenu(context, t.globalPosition, [
        MenuSpec(tr('วางผู้ใช้ภายนอกที่นี่'), Icons.crop_square_rounded, () => add(DfdKind.entity), shortcut: 'E'),
        MenuSpec(tr('วางกระบวนการที่นี่'), Icons.rounded_corner_rounded, () => add(DfdKind.process), shortcut: 'P'),
        MenuSpec(tr('วางที่เก็บข้อมูลที่นี่'), Icons.storage_rounded, () => add(DfdKind.store), shortcut: 'D'),
        MenuSpec(tr('วางขอบเขตระบบที่นี่'), Icons.crop_free_rounded, () {
          final b = d.addBoundaryAt(world.dx, world.dy, snap: snap);
          if (b != null) actions.renameBoundary(b);
        }),
        null,
        MenuSpec(tr('วาง'), Icons.paste_rounded, actions.paste, shortcut: 'Ctrl+V'),
        MenuSpec(tr('เลือกทั้งหมด'), Icons.select_all_rounded, d.selectAll, shortcut: 'Ctrl+A', enabled: d.diagram.nodes.isNotEmpty),
        MenuSpec(tr('จัดวางอัตโนมัติ'), Icons.grid_view_rounded, () {
          if (d.autoLayout()) d.fit(d.viewport);
        }, enabled: d.diagram.nodes.length > 1),
        MenuSpec(tr('พอดีหน้าจอ'), Icons.fit_screen_outlined, () => d.fit(d.viewport), shortcut: 'Ctrl+0'),
        MenuSpec(tr('Export ภาพ PNG / SVG'), Icons.image_outlined, () => actions.run(Cmd.exportImage)),
      ]);
    }
  }

  void _panStart(DragStartDetails s) {
    final d = context.read<DfdController>();
    if (d.tool != DfdTool.select) {
      _drag = _Drag.none;
      return;
    }
    if (_spaceDown) {
      _drag = _Drag.pan;
      return;
    }
    final world = d.toWorld(s.localPosition);
    final handle = d.handleAt(world);
    if (handle != null) {
      d.beginResize(handle);
      _drag = _Drag.resize;
      return;
    }
    // จุดจับของเส้นที่เลือก (ปลาย/กลางช่วง) และป้ายชื่อของเส้นนั้น
    final fh = d.edgeHandleAt(world);
    if (fh != null) {
      d.beginEdgeHandle(fh);
      _drag = _Drag.flowHandle;
      return;
    }
    final sel = d.selectedFlow;
    if (sel != null && sel.label.trim().isNotEmpty) {
      final r = dfdRoutes(d.diagram)[sel.id];
      if (r != null && dfdLabelRect(sel, r).contains(world)) {
        _labelFlow = sel.id;
        d.beginEdgeLabelDrag();
        _drag = _Drag.label;
        return;
      }
    }
    final hit = _hit(d, world);
    if (hit.node == null && hit.flow == null && hit.boundary != null) {
      d.selectBoundary(hit.boundary!.id);
      d.beginBoundaryMove();
      _drag = _Drag.boundary;
      return;
    }
    if (hit.node != null) {
      if (!d.selectedNodeIds.contains(hit.node!.id)) d.selectNode(hit.node!.id, add: _ctrlOrShift);
      d.beginMove();
      _drag = _Drag.move;
    } else {
      _drag = _Drag.marquee;
      _marqueeStart = s.localPosition;
      _marqueeEnd = s.localPosition;
      if (!_ctrlOrShift) d.clearSelection();
    }
  }

  Set<String> _marqueeBase = const {};

  void _panUpdate(DragUpdateDetails u) {
    final d = context.read<DfdController>();
    switch (_drag) {
      case _Drag.pan:
        d.panBy(u.delta);
      case _Drag.move:
        d.moveBy(u.delta.dx / d.scale, u.delta.dy / d.scale, grid: context.read<AppSettings>().snapToGrid ? kGridSize : null);
      case _Drag.boundary:
        d.moveBoundaryBy(u.delta.dx / d.scale, u.delta.dy / d.scale, grid: context.read<AppSettings>().snapToGrid ? kGridSize : null);
      case _Drag.resize:
        d.resizeBy(u.delta.dx / d.scale, u.delta.dy / d.scale, grid: context.read<AppSettings>().snapToGrid ? kGridSize : null);
      case _Drag.flowHandle:
        d.edgeHandleTo(d.toWorld(u.localPosition), grid: context.read<AppSettings>().snapToGrid ? kGridSize : null);
      case _Drag.label:
        final id = _labelFlow;
        if (id != null) d.edgeLabelDragBy(id, u.delta.dx / d.scale, u.delta.dy / d.scale);
      case _Drag.marquee:
        setState(() => _marqueeEnd = u.localPosition);
        final a = d.toWorld(_marqueeStart!), b = d.toWorld(_marqueeEnd!);
        final r = Rect.fromPoints(a, b);
        final inside = {
          for (final n in d.diagram.nodes)
            if (r.overlaps(Rect.fromLTWH(n.x, n.y, n.w, n.h))) n.id,
        };
        d.setNodeSelection({..._marqueeBase, ...inside});
      case _Drag.none:
        break;
    }
  }

  void _panEnd() {
    final d = context.read<DfdController>();
    if (_drag == _Drag.move) d.endMove();
    if (_drag == _Drag.resize) d.endResize();
    if (_drag == _Drag.boundary) d.endBoundaryMove();
    if (_drag == _Drag.flowHandle) d.endEdgeHandle();
    if (_drag == _Drag.label) d.endEdgeLabelDrag();
    _labelFlow = null;
    setState(() {
      _drag = _Drag.none;
      _marqueeStart = null;
      _marqueeEnd = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DfdController>();
    context.watch<ProjectController>(); // เนื้อหา/ชื่อเปลี่ยน -> วาดใหม่
    final w = context.watch<WorkspaceController>();
    final marquee = _marqueeStart == null ? null : Rect.fromPoints(_marqueeStart!, _marqueeEnd ?? _marqueeStart!);
    // ป้ายบนแคนวาส: endpoint ของกระบวนการ, ตาราง ER ของที่เก็บข้อมูล
    final apiBadges = <String, String>{};
    final tableBadges = <String, String>{};
    for (final n in d.diagram.nodes) {
      final a = n.api;
      if (a != null) {
        final e = w.documentById(a.docId)?.api?.endpointById(a.endpointId);
        if (e != null) apiBadges[n.id] = '${e.method.name.toUpperCase()} ${e.path}';
      }
      final tid = n.tableId;
      if (n.kind == DfdKind.store && tid != null) {
        final t = w.erDocumentWithTable(n.tableDocId, tid)?.er?.tableById(tid);
        if (t != null) tableBadges[n.id] = t.name;
      }
    }
    return Column(children: [
      LayoutBuilder(builder: (context, box) => _Toolbar(compact: box.maxWidth < 760, medium: box.maxWidth < 1000)),
      Expanded(child: LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      d.viewport = size;
      return Listener(
        onPointerSignal: (e) {
          if (e is! PointerScrollEvent) return;
          if (HardwareKeyboard.instance.isControlPressed) {
            d.zoomAt(e.localPosition, e.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1);
          } else {
            d.panBy(-e.scrollDelta);
          }
        },
        onPointerMove: (e) {
          // ปุ่มกลางลาก = เลื่อนมุมมอง
          if (e.buttons == kMiddleMouseButton) d.panBy(e.delta);
        },
        onPointerHover: (e) {
          if (d.linkSource != null) _cursor.value = d.toWorld(e.localPosition);
        },
        child: MouseRegion(
          cursor: switch (d.tool) {
            DfdTool.select => _drag == _Drag.pan ? SystemMouseCursors.grabbing : SystemMouseCursors.basic,
            DfdTool.flow => SystemMouseCursors.precise,
            _ => SystemMouseCursors.precise,
          },
          child: ClipRect(child: Stack(children: [
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('dfd-canvas'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (t) => _tapUp(t.localPosition),
                onSecondaryTapDown: _secondaryTap,
                dragStartBehavior: DragStartBehavior.down,
                onPanStart: (s) {
                  _marqueeBase = _ctrlOrShift ? d.selectedNodeIds : const {};
                  _panStart(s);
                },
                onPanUpdate: _panUpdate,
                onPanEnd: (_) => _panEnd(),
                onPanCancel: _panEnd,
                child: CustomPaint(
                  painter: DotGridPainter(d.offset, d.scale),
                  foregroundPainter: DfdScreenPainter(
                    diagram: d.diagram,
                    offset: d.offset,
                    scale: d.scale,
                    selectedNodes: d.selectedNodeIds,
                    selectedFlow: d.selectedFlowId,
                    dropNode: d.dropNodeId,
                    dropPort: d.dropPort,
                    selectedBoundary: d.selectedBoundaryId,
                    linkSource: d.linkSource,
                    linkCursor: _cursor.value,
                    marquee: marquee,
                    apiBadges: apiBadges,
                    tableBadges: tableBadges,
                    repaint: _cursor,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Positioned.fill(child: NotePinsLayer(doc: d, view: d, scale: () => d.scale, offset: () => d.offset)),
            // ระดับของแผนภาพ (ตามดีไซน์ Phase 15): แผนภาพแม่ › กระบวนการ › แผนภาพนี้ + ป้ายสมดุล
            Positioned(left: 12, top: 12, right: 12, child: Align(alignment: Alignment.centerLeft, child: _LevelBar(maxWidth: size.width - 24))),
            Positioned(
              right: 14,
              bottom: 14,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (size.width >= kDfdMinimapMinCanvasWidth && size.height >= 360 && d.diagram.nodes.isNotEmpty) ...[
                  DfdMinimap(canvas: size),
                  const SizedBox(height: 8),
                ],
                _ZoomBar(size: size),
              ]),
            ),
            if (d.diagram.nodes.isEmpty)
              IgnorePointer(
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.account_tree_outlined, size: 44, color: C.muted.withValues(alpha: 0.6)),
                    const SizedBox(height: 10),
                    Text(tr('แผนภาพ DFD ว่างอยู่'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.muted)),
                    const SizedBox(height: 4),
                    Text(tr('เลือกวัตถุจากแผงซ้าย (E / P / D) แล้วคลิกบนพื้นที่ว่างเพื่อวาง'), style: TextStyle(color: C.muted)),
                  ]),
                ),
              ),
          ])),
        ),
      );
      })),
    ]);
  }
}

/// แถบเครื่องมือเต็มความกว้างเหนือแคนวาส (ตามดีไซน์ Phase 15):
/// [เลือก S | เส้นข้อมูล F] · ขอบเขตระบบ · จัดวางอัตโนมัติ ······ ผลตรวจกฎ DFD · Snap · ส่งออกภาพ
/// การวางวัตถุ (E / P / D) อยู่ที่แผงซ้าย ; [compact] = ไอคอนอย่างเดียว (ชื่ออยู่ในทูลทิป)
class _Toolbar extends StatelessWidget {
  const _Toolbar({this.compact = false, this.medium = false});
  final bool compact;

  /// แคนวาสกว้างปานกลาง: ป้ายผลตรวจแบบสั้น และ Snap เป็นไอคอน
  final bool medium;

  @override
  Widget build(BuildContext context) {
    final d = context.watchContent<DfdController>();
    final w = context.watch<WorkspaceController>();
    final s = context.watch<AppSettings>();
    final dc = C.doc(DocType.dfd);
    final issues = validateDfd(d.diagram, workspace: w.workspace, diagramId: w.activeId);
    final problems = issues.where((i) => i.severity != Severity.info).length;

    Widget tool(DfdTool t, String label, String key, IconData icon, String shortcut) {
      final on = d.tool == t;
      return Tooltip(
        message: '$label ($shortcut)',
        child: InkWell(
          key: ValueKey('dfd-tool-$key'),
          borderRadius: BorderRadius.circular(7),
          onTap: () => d.setTool(t),
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
                Text(label, style: TextStyle(fontSize: 12, fontWeight: on ? FontWeight.w600 : FontWeight.w400, color: on ? C.text : C.text)),
                const SizedBox(width: 5),
                Text(shortcut, style: TextStyle(fontSize: 11, color: C.muted, fontFamily: kMono, fontFamilyFallback: const ['Consolas'])),
              ],
            ]),
          ),
        ),
      );
    }

    Widget button(String key, IconData icon, String label, VoidCallback? onTap, {bool outlined = false}) => Tooltip(
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
                color: outlined ? C.surface : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 15, color: onTap == null ? C.muted.withValues(alpha: 0.5) : C.muted),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(fontSize: 12, color: onTap == null ? C.muted : C.text)),
                ],
              ]),
            ),
          ),
        );

    final ok = problems == 0;
    final rules = Tooltip(
      message: ok ? tr('กฎ DFD ผ่านทั้งหมด') : tr('ดูปัญหาในแผนภาพนี้'),
      child: InkWell(
        key: const ValueKey('dfd-rules'),
        borderRadius: BorderRadius.circular(11),
        onTap: ok ? d.clearSelection : () => showWorkspaceIssues(context, docId: w.activeId),
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: ok ? C.primaryTint : C.palette.warnBg,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ok ? Icons.check_rounded : Icons.warning_amber_rounded, size: 13, color: ok ? C.primaryDark : C.palette.warnText),
            const SizedBox(width: 4),
            Text(
              ok ? (compact || medium ? tr('ผ่าน') : tr('กฎ DFD ผ่านทั้งหมด')) : tr('{0} ปัญหา', [problems]),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: ok ? C.primaryDark : C.palette.warnText),
            ),
          ]),
        ),
      ),
    );

    final snap = Tooltip(
      message: tr('จัดแนวตามตาราง (Snap) — กด Alt ค้างตอนลากเพื่อข้ามชั่วคราว'),
      child: InkWell(
        key: const ValueKey('dfd-snap'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => s.setSnapToGrid(!s.snapToGrid),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: s.snapToGrid ? C.primaryTint : null,
            borderRadius: BorderRadius.circular(8),
          ),
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
          key: const ValueKey('dfd-export'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => DfdActions(context).run(Cmd.exportImage),
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
      key: const ValueKey('dfd-toolbar'),
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: C.surface, border: Border(bottom: BorderSide(color: C.borderSoft))),
      child: Row(children: [
        // ส่วนซ้ายเลื่อนแนวนอนได้เมื่อแคนวาสแคบ (ไม่ล้น) ; ส่วนขวาอยู่ชิดขวาเสมอ
        Flexible(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: C.palette.field, borderRadius: BorderRadius.circular(9)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  tool(DfdTool.select, tr('เลือก'), 'select', Icons.near_me_outlined, 'S'),
                  const SizedBox(width: 2),
                  tool(DfdTool.flow, tr('เส้นข้อมูล'), 'flow', Icons.arrow_right_alt_rounded, 'F'),
                ]),
              ),
              Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 8), color: C.border),
              button('dfd-wrap-boundary', Icons.crop_free_rounded, tr('ครอบด้วยขอบเขตระบบ'),
                  d.selectedNodeIds.isEmpty ? null : d.addBoundaryAround),
              const SizedBox(width: 4),
              button('dfd-autolayout', Icons.grid_view_rounded, tr('จัดวางอัตโนมัติ'), d.diagram.nodes.length < 2
                  ? null
                  : () {
                      if (d.autoLayout()) d.fit(d.viewport);
                    }, outlined: true),
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

/// ระดับของแผนภาพบนแคนวาส: แผนภาพแม่ (คลิก = กลับไป) › เลข+ชื่อกระบวนการ › แผนภาพนี้ + ป้ายสมดุล ; ไม่มีแม่ = ไม่แสดง
class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.maxWidth});
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final d = context.watchContent<DfdController>();
    final w = context.watch<WorkspaceController>();
    final parents = d.parentsOf(w.activeId);
    if (parents.isEmpty || maxWidth < 200) return const SizedBox.shrink();
    final (tab, proc) = parents.first;
    final dc = C.doc(DocType.dfd);
    // สมดุล: ตัวตรวจรายงานที่กระบวนการของแผนภาพแม่
    final unbalanced = validateDfd(tab.dfd!, workspace: w.workspace, diagramId: tab.id)
        .any((i) => i.code == 'dfd_unbalanced' && i.tableId == proc.id);
    final muted = TextStyle(fontSize: 12.5, color: C.muted);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Container(
          key: const ValueKey('dfd-level-bar'),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: C.surface, border: Border.all(color: C.border), borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              key: ValueKey('dfd-parent-${proc.id}'),
              onTap: () {
                w.openDocument(tab.id);
                w.dfdController(tab.id)?.selectNode(proc.id);
              },
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.subdirectory_arrow_left_rounded, size: 15, color: dc.ink),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth * 0.35),
                  child: Text(tab.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: dc.ink)),
                ),
              ]),
            ),
            Text('  ›  ', style: muted),
            if (proc.number.isNotEmpty) Text('${proc.number} ', style: TextStyle(fontSize: 12, fontFamily: kMono, fontFamilyFallback: const ['Consolas'], color: dc.ink)),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth * 0.3),
              child: Text(proc.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        Container(
          key: const ValueKey('dfd-balance'),
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: unbalanced ? C.palette.warnBg : C.primaryTint,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(unbalanced ? Icons.warning_amber_rounded : Icons.balance_rounded, size: 13,
                color: unbalanced ? C.palette.warnText : C.primaryDark),
            const SizedBox(width: 4),
            Text(
              unbalanced ? tr('ไม่สมดุลกับแผนภาพแม่') : tr('สมดุลกับแผนภาพแม่'),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: unbalanced ? C.palette.warnText : C.primaryDark),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ZoomBar extends StatelessWidget {
  const _ZoomBar({required this.size});
  final Size size;

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DfdController>();
    Widget btn(IconData i, String tip, VoidCallback f, Key k) => IconButton(
          key: k,
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: f,
          icon: Icon(i),
        );
    return Container(
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.remove_rounded, tr('ย่อ'), () => d.zoomAt(size.center(Offset.zero), 1 / 1.2), const ValueKey('dfd-zoom-out')),
        Text('${(d.scale * 100).round()}%', key: const ValueKey('dfd-zoom-label'), style: const TextStyle(fontSize: 12.5)),
        btn(Icons.add_rounded, tr('ขยาย'), () => d.zoomAt(size.center(Offset.zero), 1.2), const ValueKey('dfd-zoom-in')),
        btn(Icons.fit_screen_outlined, tr('พอดีหน้าจอ'), () => d.fit(size), const ValueKey('dfd-fit')),
      ]),
    );
  }
}
