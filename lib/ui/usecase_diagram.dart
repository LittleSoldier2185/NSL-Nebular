import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/export/usecase_export.dart';
import '../core/export/usecase_svg.dart';
import '../core/l10n/l10n.dart';
import '../core/layout/usecase_layout.dart';
import '../state/workspace_controller.dart';
import 'export/diagram_png.dart' show PngExport, kMaxPngSide;
import 'file_actions.dart';
import 'theme.dart';
import 'usecase_view.dart' show UcIssueTile;

// ===================================================================== วาดแผนภาพ

TextPainter _text(String s, TextStyle style, double maxWidth, {int maxLines = 1, TextAlign align = TextAlign.center}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textAlign: align,
    textDirection: TextDirection.ltr,
    maxLines: maxLines,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  return tp;
}

void _dashed(Canvas c, Offset a, Offset b, Paint p, {double dash = 7, double gap = 5}) {
  final d = b - a;
  final len = d.distance;
  if (len == 0) return;
  final u = d / len;
  for (var t = 0.0; t < len; t += dash + gap) {
    c.drawLine(a + u * t, a + u * math.min(t + dash, len), p);
  }
}

/// วาดแผนภาพ Use Case ที่จัดวางแล้วลง [canvas] (พิกัดแคนวาสของแผนภาพ) — ใช้ทั้งบนจอและตอนส่งออก PNG
/// [selectedKey] = โหนดที่เลือก (ไฮไลต์) ; สีมาจากธีมปัจจุบัน ([C])
void paintUseCaseDiagram(Canvas canvas, UcDiagram d, {String? selectedKey}) {
  final b = d.boundary;
  if (b != null) {
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(b.x, b.y, b.w, b.h), const Radius.circular(10));
    canvas.drawRRect(r, Paint()..color = C.surface.withValues(alpha: 0.6));
    canvas.drawRRect(r, Paint()..color = C.muted..style = PaintingStyle.stroke..strokeWidth = 1.2);
    _text(d.systemName, TextStyle(fontFamily: kThai, fontSize: 13, fontWeight: FontWeight.w700, color: C.muted), b.w - 28, align: TextAlign.left)
        .paint(canvas, Offset(b.x + 14, b.y + 12));
  }

  // ---- เส้น ----
  final line = Paint()..color = C.muted..style = PaintingStyle.stroke..strokeWidth = 1.3;
  for (final e in d.edges) {
    final l = ucEdgeLine(d, e);
    if (l == null) continue;
    final a = Offset(l.x1, l.y1), z = Offset(l.x2, l.y2);
    if (e.kind == UcEdgeKind.association) {
      canvas.drawLine(a, z, line);
      continue;
    }
    _dashed(canvas, a, z, line);
    // หัวลูกศรปลายเปิดที่ปลายทาง
    final ang = math.atan2(z.dy - a.dy, z.dx - a.dx);
    for (final s in [-1, 1]) {
      canvas.drawLine(z, z - Offset(math.cos(ang + s * 0.45), math.sin(ang + s * 0.45)) * 11, line);
    }
    // ป้ายกลางเส้น (มีพื้นกันเส้นทับตัวอักษร)
    final mid = Offset((a.dx + z.dx) / 2, (a.dy + z.dy) / 2);
    final tag = e.kind == UcEdgeKind.include ? '«include»' : '«extend»';
    final style = TextStyle(fontFamily: kThai, fontSize: 11.5, fontStyle: FontStyle.italic, color: C.muted);
    final tp = _text(e.condition.isEmpty ? tag : '$tag\n[${e.condition}]', style, 170, maxLines: 3);
    final rect = Rect.fromCenter(center: mid, width: tp.width + 8, height: tp.height + 4);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), Paint()..color = C.canvas.withValues(alpha: 0.9));
    tp.paint(canvas, Offset(rect.left + 4, rect.top + 2));
  }

  // ---- โหนด ----
  for (final n in d.nodes) {
    final sel = n.key == selectedKey;
    if (n.isActor) {
      if (sel) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(n.x - 8, n.y - 4, n.w + 16, n.h + 8), const Radius.circular(10)),
          Paint()..color = C.primaryTint,
        );
      }
      final stroke = Paint()..color = C.text..style = PaintingStyle.stroke..strokeWidth = 1.6..strokeCap = StrokeCap.round;
      final cx = n.cx, top = n.y;
      canvas.drawCircle(Offset(cx, top + 12), 10, stroke);
      canvas.drawLine(Offset(cx, top + 22), Offset(cx, top + 52), stroke);
      canvas.drawLine(Offset(cx - 18, top + 33), Offset(cx + 18, top + 33), stroke);
      canvas.drawLine(Offset(cx, top + 52), Offset(cx - 14, top + 72), stroke);
      canvas.drawLine(Offset(cx, top + 52), Offset(cx + 14, top + 72), stroke);
      final tp = _text(n.label, TextStyle(fontFamily: kThai, fontSize: 12.5, fontWeight: FontWeight.w600, color: C.text), n.w + 20, maxLines: 2);
      tp.paint(canvas, Offset(cx - tp.width / 2, top + 80));
    } else {
      final rect = Rect.fromLTWH(n.x, n.y, n.w, n.h);
      canvas.drawOval(rect, Paint()..color = sel ? C.primaryTint : C.surface);
      canvas.drawOval(rect, Paint()..color = C.primary..style = PaintingStyle.stroke..strokeWidth = sel ? 2.8 : 1.7);
      final name = _text(n.label, TextStyle(fontFamily: kThai, fontSize: 13, fontWeight: FontWeight.w600, color: C.text), n.w - 44, maxLines: 2);
      final code = _text(n.sub, TextStyle(fontFamily: kThai, fontSize: 11, color: C.muted), n.w - 44);
      final total = name.height + code.height;
      name.paint(canvas, Offset(n.cx - name.width / 2, n.cy - total / 2));
      code.paint(canvas, Offset(n.cx - code.width / 2, n.cy - total / 2 + name.height));
    }
  }
}

/// วาดแผนภาพ Use Case เป็นภาพ PNG (ตัดเฉพาะส่วนที่มีเนื้อหา) — null ถ้าไม่มี Use Case ; ตัวพิมพ์เดียวกับบนจอ
Future<PngExport?> exportUseCasePng(UcDiagram d, {double scale = 2, bool dark = false}) async {
  final bounds = d.bounds;
  if (d.isEmpty || bounds == null) return null;
  final width = bounds.right - bounds.left, height = bounds.bottom - bounds.top;
  final s = math.min(scale, kMaxPngSide / math.max(width, height));
  final w = (width * s).ceil(), h = (height * s).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(s);
  canvas.translate(-bounds.left, -bounds.top);
  C.withPalette(dark ? kDarkPalette : kLightPalette, () {
    canvas.drawRect(Rect.fromLTWH(bounds.left, bounds.top, width, height), Paint()..color = C.canvas);
    paintUseCaseDiagram(canvas, d);
  });
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) return null;
  return PngExport(data.buffer.asUint8List(), w, h, s);
}

class _DiagramPainter extends CustomPainter {
  _DiagramPainter(this.d, this.selectedKey, this.scale, this.pan);
  final UcDiagram d;
  final String? selectedKey;
  final double scale;
  final Offset pan;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = C.canvas);
    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(scale);
    paintUseCaseDiagram(canvas, d, selectedKey: selectedKey);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DiagramPainter old) => true;
}

// ===================================================================== แท็บแผนภาพ

/// แท็บ "แผนภาพ" ของหน้า Use Case (แบบ B ของ `design/use-case-phase30-32`) : ผืนผ้าใบ + แผงสรุปด้านขวา
/// สร้างจากสเปกอัตโนมัติ — แก้ที่แท็บสเปกเท่านั้น ; ที่นี่ลากย้ายตำแหน่ง (เก็บในไฟล์) แพน/ซูม เลือกดูสรุป และส่งออกภาพ
class UcDiagramView extends StatefulWidget {
  const UcDiagramView({super.key, required this.w, required this.onOpenSpec, this.initialUcId});
  final WorkspaceController w;

  /// ดับเบิลคลิกวงรี / ปุ่ม "แก้สเปก" → ไปแท็บสเปกของ Use Case นี้
  final ValueChanged<String> onOpenSpec;
  final String? initialUcId;

  @override
  State<UcDiagramView> createState() => _UcDiagramViewState();
}

class _UcDiagramViewState extends State<UcDiagramView> {
  double _scale = 1;
  Offset _pan = Offset.zero;
  bool _needFit = true;
  bool _legend = true;
  String? _sel;
  String? _dragKey;
  Offset _dragWorld0 = Offset.zero, _dragOrigin = Offset.zero;
  Size _view = Size.zero;
  String? _lastTapKey;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    final id = widget.initialUcId;
    if (id != null && widget.w.useCaseById(id) != null) _sel = ucNodeKey(id);
  }

  Offset _toWorld(Offset p) => (p - _pan) / _scale;

  UcDiagram _diagram() => layoutUseCaseDiagram(widget.w.workspace, overrides: widget.w.useCaseLayout);

  void _zoomAt(Offset focus, double factor) {
    final s = (_scale * factor).clamp(0.2, 3.0).toDouble();
    if (s == _scale) return;
    final world = _toWorld(focus);
    setState(() {
      _scale = s;
      _pan = focus - world * s;
    });
  }

  void _fit(UcDiagram d) {
    final b = d.bounds;
    if (b == null || _view.isEmpty) return;
    final t = ucFitTransform(b, _view.width, _view.height);
    setState(() {
      _scale = t.scale;
      _pan = Offset(t.dx, t.dy);
    });
  }

  void _onTapDown(UcDiagram d, Offset local) {
    final hit = ucHitTest(d, _toWorld(local).dx, _toWorld(local).dy);
    final now = clock.now();
    // ดับเบิลคลิกวงรี = ไปแก้สเปก (จับเวลาเอง : ไม่ใช้ onDoubleTap ที่ทำให้คลิกเดี่ยวช้า)
    if (hit != null && !hit.isActor && hit.key == _lastTapKey && now.difference(_lastTapAt) < const Duration(milliseconds: 400)) {
      _lastTapKey = null;
      widget.onOpenSpec(hit.ucId!);
      return;
    }
    _lastTapKey = hit?.key;
    _lastTapAt = now;
    setState(() => _sel = hit?.key);
  }

  void _onPanStart(UcDiagram d, Offset local) {
    final world = _toWorld(local);
    final hit = ucHitTest(d, world.dx, world.dy);
    if (hit == null) {
      _dragKey = null;
      return;
    }
    _dragKey = hit.key;
    _dragWorld0 = world;
    _dragOrigin = Offset(hit.x, hit.y);
    setState(() => _sel = hit.key);
  }

  void _onPanUpdate(Offset local, Offset delta) {
    final key = _dragKey;
    if (key == null) {
      setState(() => _pan += delta);
      return;
    }
    final to = _dragOrigin + (_toWorld(local) - _dragWorld0);
    widget.w.setUseCaseNodePosition(key, to.dx, to.dy);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final d = _diagram();
    if (d.isEmpty) {
      return Center(
        child: Text(tr('ยังไม่มี Use Case — เขียนในแท็บ "สเปก" แล้วแผนภาพจะสร้างให้เอง'), key: const ValueKey('uc-dg-empty'), style: TextStyle(color: C.muted)),
      );
    }
    final selKey = d.node(_sel ?? '') == null ? null : _sel;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _toolbar(context, d),
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final canvas = LayoutBuilder(builder: (context, c) {
            _view = Size(c.maxWidth, c.maxHeight);
            if (_needFit && d.bounds != null) {
              _needFit = false;
              final t = ucFitTransform(d.bounds!, c.maxWidth, c.maxHeight);
              _scale = t.scale;
              _pan = Offset(t.dx, t.dy);
              // แถบเครื่องมือ (ป้ายเปอร์เซ็นต์) ถูกสร้างก่อนผืนผ้าใบ : รีเฟรชหลังได้ค่าพอดีจอครั้งแรก ไม่ให้แสดงค่าเก่า
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
            }
            return ClipRect(
              child: Stack(children: [
                Positioned.fill(
                  child: Listener(
                    onPointerSignal: (e) {
                      if (e is PointerScrollEvent) _zoomAt(e.localPosition, e.scrollDelta.dy > 0 ? 0.9 : 1.1);
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (det) => _onTapDown(d, det.localPosition),
                      onPanStart: (det) => _onPanStart(d, det.localPosition),
                      onPanUpdate: (det) => _onPanUpdate(det.localPosition, det.delta),
                      onPanEnd: (_) => _dragKey = null,
                      child: CustomPaint(key: const ValueKey('uc-diagram'), painter: _DiagramPainter(d, selKey, _scale, _pan)),
                    ),
                  ),
                ),
                if (_legend)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: IgnorePointer(
                      child: Container(
                        key: const ValueKey('uc-dg-legend-box'),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: C.border)),
                        child: Text(tr('เส้นทึบ = ผู้กระทำ · เส้นประ = «include» / «extend»'), style: TextStyle(fontSize: 11.5, color: C.muted)),
                      ),
                    ),
                  ),
              ]),
            );
          });
          final inspector = _Inspector(
            key: const ValueKey('uc-dg-inspector'),
            w: w,
            d: d,
            selKey: selKey,
            onSelect: (k) => setState(() => _sel = k),
            onOpenSpec: widget.onOpenSpec,
          );
          if (wide) {
            return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: canvas),
              Container(width: 296, decoration: BoxDecoration(color: C.surface, border: Border(left: BorderSide(color: C.border))), child: inspector),
            ]);
          }
          return Column(children: [
            Expanded(child: canvas),
            Container(height: 240, decoration: BoxDecoration(color: C.surface, border: Border(top: BorderSide(color: C.border))), child: inspector),
          ]);
        }),
      ),
    ]);
  }

  Widget _toolbar(BuildContext context, UcDiagram d) {
    final w = widget.w;
    final actors = d.nodes.where((n) => n.isActor).length;
    Widget iconBtn(String key, IconData icon, String tip, VoidCallback? onTap) => IconButton(
          key: ValueKey(key),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: onTap,
          icon: Icon(icon),
        );
    final center = Offset(_view.width / 2, _view.height / 2);
    return Container(
      decoration: BoxDecoration(color: C.surface, border: Border(bottom: BorderSide(color: C.border))),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(tr('แผนภาพ'), style: TextStyle(fontWeight: FontWeight.w700, color: C.text)),
        Text(tr('{0} Use Case · {1} ผู้กระทำ', [d.nodes.length - actors, actors]), key: const ValueKey('uc-dg-counts'), style: TextStyle(color: C.muted)),
        iconBtn('uc-dg-zoom-out', Icons.remove_rounded, tr('ซูมออก'), () => _zoomAt(center, 0.8)),
        SizedBox(width: 46, child: Text('${(_scale * 100).round()}%', key: const ValueKey('uc-dg-zoom-label'), textAlign: TextAlign.center, style: monoStyle.copyWith(fontSize: 12, color: C.muted))),
        iconBtn('uc-dg-zoom-in', Icons.add_rounded, tr('ซูมเข้า'), () => _zoomAt(center, 1.25)),
        OutlinedButton(key: const ValueKey('uc-dg-fit'), onPressed: () => _fit(d), child: Text(tr('พอดีจอ'))),
        OutlinedButton(
          key: const ValueKey('uc-dg-reset'),
          onPressed: w.useCaseLayout.isEmpty ? null : () => w.resetUseCaseLayout(),
          child: Text(tr('จัดวางใหม่')),
        ),
        FilterChip(
          key: const ValueKey('uc-dg-legend'),
          label: Text(tr('ตำนาน')),
          selected: _legend,
          onSelected: (v) => setState(() => _legend = v),
        ),
        PopupMenuButton<String>(
          key: const ValueKey('uc-dg-export'),
          tooltip: tr('ส่งออกแผนภาพ'),
          onSelected: (v) => v == 'png' ? _exportPng(context, d) : _exportSvg(context),
          itemBuilder: (_) => [
            PopupMenuItem(key: const ValueKey('uc-dg-export-png'), value: 'png', child: Text(tr('PNG — ภาพสำหรับเอกสาร'))),
            PopupMenuItem(key: const ValueKey('uc-dg-export-svg'), value: 'svg', child: Text(tr('SVG — เวกเตอร์ แก้ต่อได้'))),
          ],
          child: IgnorePointer(child: FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.ios_share_rounded, size: 16), label: Text(tr('ส่งออก')))),
        ),
      ]),
    );
  }

  String get _fileBase => FileActions.safeName(widget.w.workspace.name);

  Future<void> _exportSvg(BuildContext context) async {
    final svg = exportUseCaseSvg(widget.w.workspace, overrides: widget.w.useCaseLayout);
    if (svg == null) return;
    await FileActions.saveText(context, svg, '$_fileBase-usecase.svg', tr('ส่งออกแผนภาพ Use Case เป็น SVG'));
  }

  Future<void> _exportPng(BuildContext context, UcDiagram d) async {
    final png = await exportUseCasePng(d);
    if (png == null || !context.mounted) return;
    await FileActions.saveBytes(context, png.bytes, '$_fileBase-usecase.png', tr('ส่งออกแผนภาพ Use Case เป็น PNG'),
        note: png.scale < 2 ? tr(' (ลดสเกลเหลือ {0}x เพราะภาพใหญ่เกินไป)', [png.scale.toStringAsFixed(1)]) : '');
  }
}

// ===================================================================== แผงสรุปด้านขวา

class _Inspector extends StatelessWidget {
  const _Inspector({super.key, required this.w, required this.d, required this.selKey, required this.onSelect, required this.onOpenSpec});
  final WorkspaceController w;
  final UcDiagram d;
  final String? selKey;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String> onOpenSpec;

  @override
  Widget build(BuildContext context) {
    final node = selKey == null ? null : d.node(selKey!);
    final head = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: C.muted, letterSpacing: 0.5);
    Widget sec(String t) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(t.toUpperCase(), style: head));
    Widget chip(String t, {bool mono = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: C.primaryTint, borderRadius: BorderRadius.circular(6), border: Border.all(color: C.primary)),
          child: Text(t, style: (mono ? monoStyle : const TextStyle()).copyWith(fontSize: 11.5, color: C.primaryDark)),
        );

    Widget body;
    if (node == null) {
      final n = d.nodes.length;
      final actors = d.nodes.where((e) => e.isActor).length;
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('ภาพรวม'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.text)),
        const SizedBox(height: 4),
        Text(tr('{0} Use Case · {1} ผู้กระทำ', [n - actors, actors]), style: TextStyle(color: C.muted)),
        sec(tr('วิธีใช้')),
        for (final t in [
          tr('คลิกวงรีเพื่อดูสรุปของ Use Case'),
          tr('ดับเบิลคลิกวงรีเพื่อไปแก้สเปก'),
          tr('ลากวงรีหรือผู้กระทำเพื่อจัดตำแหน่ง ลากพื้นว่างเพื่อเลื่อนภาพ เมาส์ล้อ = ซูม'),
          tr('แผนภาพสร้างจากสเปกเสมอ — เพิ่ม/แก้ Use Case ที่แท็บ "สเปก"'),
        ])
          Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $t', style: TextStyle(fontSize: 12.5, color: C.muted))),
      ]);
    } else if (node.isActor) {
      final mine = [
        for (final u in w.useCases)
          if (u.actor.trim() == node.label || u.secondaryActors.contains(node.label)) u,
      ];
      final primary = w.useCases.any((u) => u.actor.trim() == node.label);
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(node.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.text)),
        const SizedBox(height: 4),
        Text(primary ? tr('ผู้กระทำหลัก') : tr('ผู้กระทำรอง / ระบบภายนอก'), style: TextStyle(color: C.muted)),
        sec(tr('Use Case ({0})', [mine.length])),
        for (final u in mine)
          InkWell(
            key: ValueKey('uc-dg-actor-uc-${u.id}'),
            onTap: () => onSelect(ucNodeKey(u.id)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                SizedBox(width: 48, child: Text(u.code, style: monoStyle.copyWith(fontSize: 11.5, color: C.muted))),
                Expanded(child: Text(u.name.trim().isEmpty ? tr('(ไม่มีชื่อ)') : u.name.trim(), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
      ]);
    } else {
      final u = w.useCaseById(node.ucId!)!;
      final actors = [if (u.actor.trim().isNotEmpty) u.actor.trim(), ...u.secondaryActors];
      final reqs = [
        for (final id in u.reqIds)
          for (final r in w.requirements)
            if (r.id == id) r.code,
      ];
      String ref(String id) => w.useCaseById(id) == null ? '?' : '${w.useCaseById(id)!.code} ${w.useCaseById(id)!.name}'.trim();
      final incoming = [
        for (final o in w.useCases)
          if (o.id != u.id && (o.includes.contains(u.id) || o.extendsFrom.any((e) => e.baseId == u.id))) o,
      ];
      final mine = [for (final i in w.useCaseIssues) if (i.ucId == u.id) i];
      final alt = u.branches.where((b) => !b.exception).length, ex = u.branches.where((b) => b.exception).length;
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(u.name.trim().isEmpty ? tr('(ไม่มีชื่อ)') : u.name.trim(), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.text)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          Text(u.code, style: monoStyle.copyWith(fontSize: 12, color: C.muted)),
          Text('· ${ucStatusLabel(u.status)} · ${ucPriorityLabel(u.priority)}', style: TextStyle(fontSize: 12, color: C.muted)),
        ]),
        sec(tr('ผู้กระทำ')),
        Text(actors.isEmpty ? '-' : actors.join(' · ')),
        if (u.goal.trim().isNotEmpty) ...[sec(tr('เป้าหมาย')), Text(u.goal.trim())],
        sec(tr('ขั้นตอน · ทางเลือก')),
        Text(tr('{0} ขั้นตอน · {1} ทางเลือก · {2} ข้อผิดพลาด', [u.steps.length, alt, ex]), key: const ValueKey('uc-dg-counts-sel')),
        if (reqs.isNotEmpty) ...[sec(tr('ความต้องการ')), Wrap(spacing: 6, runSpacing: 6, children: [for (final r in reqs) chip(r, mono: true)])],
        if (u.includes.isNotEmpty || u.extendsFrom.isNotEmpty || incoming.isNotEmpty) ...[
          sec(tr('ความสัมพันธ์')),
          for (final id in u.includes) Text('«include» ${ref(id)}', style: const TextStyle(fontSize: 12.5)),
          for (final e in u.extendsFrom) Text('«extend» ${ref(e.baseId)}${e.condition.trim().isEmpty ? '' : ' [${e.condition.trim()}]'}', style: const TextStyle(fontSize: 12.5)),
          for (final o in incoming) Text('← ${o.code} ${o.name}'.trim(), style: TextStyle(fontSize: 12.5, color: C.muted)),
        ],
        sec('${tr('ตรวจ')} · ${mine.length}'),
        if (mine.isEmpty)
          Text(tr('✓ ไม่พบปัญหา'), style: TextStyle(fontSize: 12.5, color: C.primaryDark))
        else
          for (final i in mine) Padding(padding: const EdgeInsets.only(bottom: 6), child: UcIssueTile(issue: i)),
        const SizedBox(height: 14),
        FilledButton(key: const ValueKey('uc-dg-open-spec'), onPressed: () => onOpenSpec(u.id), child: Text(tr('แก้สเปก →'))),
      ]);
    }
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: body);
  }
}
