import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/models/flowchart_model.dart';
import '../../core/validate/flowchart_validator.dart';
import '../../state/flowchart_controller.dart';
import '../theme.dart';
import 'fc_painter.dart';
import 'fc_view.dart';

/// หมวดของคลังรูปทรง (ตาม Artboard `Flowchart` ใน design/)
enum FcShapeCategory { basic, data, operation, operator, general }

/// รูปทรงในแต่ละหมวด ตามลำดับที่แสดง — ทุกค่าใน [FcShape] อยู่ในหมวดใดหมวดหนึ่งพอดี (มีเทสต์ตรวจ)
const Map<FcShapeCategory, List<FcShape>> kFcShapeCategories = {
  FcShapeCategory.basic: [
    FcShape.start,
    FcShape.end,
    FcShape.process,
    FcShape.decision,
    FcShape.io,
    FcShape.subroutine,
    FcShape.hexagon,
    FcShape.connector,
    FcShape.offPage,
    FcShape.annotation,
  ],
  FcShapeCategory.data: [
    FcShape.document,
    FcShape.multiDocument,
    FcShape.cylinder,
    FcShape.directData,
    FcShape.storedData,
    FcShape.internalStorage,
    FcShape.sequentialData,
    FcShape.paperTape,
    FcShape.card,
  ],
  FcShapeCategory.operation: [
    FcShape.manualInput,
    FcShape.manualOperation,
    FcShape.delay,
    FcShape.display,
    FcShape.loopLimit,
    FcShape.parallelMode,
    FcShape.transfer,
  ],
  FcShapeCategory.operator: [
    FcShape.collate,
    FcShape.sort,
    FcShape.extract,
    FcShape.merge,
    FcShape.summingJunction,
    FcShape.or,
  ],
  FcShapeCategory.general: [
    FcShape.note,
    FcShape.text,
    FcShape.rounded,
    FcShape.ellipse,
  ],
};

String fcCategoryLabel(FcShapeCategory c) => switch (c) {
      FcShapeCategory.basic => tr('พื้นฐาน'),
      FcShapeCategory.data => tr('ข้อมูลและการจัดเก็บ'),
      FcShapeCategory.operation => tr('การทำงาน'),
      FcShapeCategory.operator => tr('ตัวดำเนินการ'),
      FcShapeCategory.general => tr('ทั่วไป'),
    };

/// ข้อความที่ใช้ค้นหารูปทรง: ชื่อมาตรฐานอังกฤษ + ป้ายชื่อตามภาษา + ชื่อในไฟล์
String fcShapeSearchText(FcShape s) => '${fcShapeStdName(s)} ${fcShapeLabel(s)} ${s.name}'.toLowerCase();

/// ชื่อที่แสดงในคลัง: "Process · กระบวนการ" (ภาษาอังกฤษแสดงชื่อมาตรฐานอย่างเดียวถ้าซ้ำกัน)
String fcShapeLibraryName(FcShape s) {
  final std = fcShapeStdName(s), label = fcShapeLabel(s);
  return std.toLowerCase() == label.toLowerCase() ? std : '$std · $label';
}

/// คลังรูปทรงของแผงซ้าย: หมวดพับได้ (ค้นหาอยู่ = กางทุกหมวดที่มีผล) · กริด 4 คอลัมน์ หรือมุมมองรายชื่อ
/// คลิก = เลือกเครื่องมือวาง ; ลากไปวางบนแคนวาสได้
class FcShapeLibrary extends StatefulWidget {
  const FcShapeLibrary({super.key, required this.query});

  /// ข้อความค้นหา (ตัวพิมพ์เล็ก ตัดช่องว่างแล้ว) ; ว่าง = แสดงทั้งหมด
  final String query;

  @override
  State<FcShapeLibrary> createState() => _FcShapeLibraryState();
}

class _FcShapeLibraryState extends State<FcShapeLibrary> {
  final Set<FcShapeCategory> _collapsed = {};
  bool _list = false;

  @override
  Widget build(BuildContext context) {
    final q = widget.query;
    final groups = [
      for (final e in kFcShapeCategories.entries)
        (cat: e.key, shapes: [for (final s in e.value) if (q.isEmpty || fcShapeSearchText(s).contains(q)) s]),
    ].where((g) => g.shapes.isNotEmpty).toList();
    final total = groups.fold<int>(0, (a, g) => a + g.shapes.length);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: tr('คลังสัญลักษณ์'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
              TextSpan(text: ' ($total)', style: TextStyle(color: C.muted, fontSize: 12.5)),
            ])),
          ),
          IconButton(
            key: const ValueKey('fc-lib-view'),
            tooltip: _list ? tr('มุมมองไอคอน') : tr('มุมมองรายชื่อ'),
            style: IconButton.styleFrom(
              minimumSize: const Size(28, 28),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(color: C.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
            ),
            icon: Icon(_list ? Icons.grid_view_rounded : Icons.view_list_rounded, size: 16, color: C.muted),
            onPressed: () => setState(() => _list = !_list),
          ),
        ]),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(tr('ไม่พบรูปทรงที่ตรงกับคำค้น'), style: TextStyle(fontSize: 12, color: C.muted)),
          ),
        for (final g in groups) ...[
          const SizedBox(height: 6),
          _header(g.cat, g.shapes.length, q.isNotEmpty),
          if (q.isNotEmpty || !_collapsed.contains(g.cat)) ...[
            const SizedBox(height: 4),
            if (_list) for (final s in g.shapes) _ShapeRow(shape: s) else _grid(g.shapes),
          ],
        ],
      ]),
    );
  }

  Widget _header(FcShapeCategory c, int n, bool searching) {
    final open = searching || !_collapsed.contains(c);
    return InkWell(
      key: ValueKey('fc-lib-cat-${c.name}'),
      borderRadius: BorderRadius.circular(4),
      onTap: searching ? null : () => setState(() => open ? _collapsed.add(c) : _collapsed.remove(c)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(open ? Icons.arrow_drop_down_rounded : Icons.arrow_right_rounded, size: 18, color: C.muted),
          Expanded(
            child: Text(fcCategoryLabel(c),
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: C.muted, letterSpacing: 0.3)),
          ),
          Text('$n', style: TextStyle(fontSize: 11.5, color: C.muted)),
        ]),
      ),
    );
  }

  Widget _grid(List<FcShape> shapes) => LayoutBuilder(builder: (context, c) {
        const gap = 4.0;
        final w = ((c.maxWidth - gap * 3) / 4).floorToDouble();
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final s in shapes) SizedBox(width: w, height: 40, child: _ShapeTile(shape: s)),
        ]);
      });
}

/// เลือกเครื่องมือ / ลากไปวาง — ใช้ร่วมกันทั้งช่องไอคอนและแถวรายชื่อ
Widget _draggable(BuildContext context, FcShape shape, Widget child, {required Key key}) {
  final f = context.read<FlowchartController>();
  final k = fcShapeShortcut(shape);
  final name = fcShapeLibraryName(shape);
  return Tooltip(
    message: k.isEmpty ? name : '$name ($k)',
    waitDuration: const Duration(milliseconds: 400),
    child: Draggable<FcShape>(
      data: shape,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.8, child: SizedBox(width: 56, height: 40, child: CustomPaint(painter: FcShapePreview(shape)))),
      ),
      child: InkWell(key: key, borderRadius: BorderRadius.circular(7), onTap: () => f.setShapeTool(shape), child: child),
    ),
  );
}

class _ShapeTile extends StatelessWidget {
  const _ShapeTile({required this.shape});
  final FcShape shape;

  @override
  Widget build(BuildContext context) {
    final f = context.watch<FlowchartController>();
    final on = f.tool == FcTool.shape && f.toolShape == shape;
    final k = fcShapeShortcut(shape);
    return _draggable(
      context,
      shape,
      key: ValueKey('fc-shape-${shape.name}'),
      Container(
        decoration: BoxDecoration(
          color: on ? C.primaryTint : null,
          border: Border.all(color: on ? C.primary : C.borderSoft),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Stack(children: [
          Positioned.fill(
            child: Padding(padding: const EdgeInsets.fromLTRB(6, 7, 6, 5), child: CustomPaint(painter: FcShapePreview(shape))),
          ),
          if (k.isNotEmpty)
            Positioned(
              top: 1,
              right: 3,
              child: Text(k, style: TextStyle(fontSize: 9, color: C.muted, fontFamily: 'monospace')),
            ),
        ]),
      ),
    );
  }
}

class _ShapeRow extends StatelessWidget {
  const _ShapeRow({required this.shape});
  final FcShape shape;

  @override
  Widget build(BuildContext context) {
    final f = context.watch<FlowchartController>();
    final on = f.tool == FcTool.shape && f.toolShape == shape;
    final k = fcShapeShortcut(shape);
    return _draggable(
      context,
      shape,
      key: ValueKey('fc-shape-${shape.name}'),
      Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(color: on ? C.primaryTint : null, borderRadius: BorderRadius.circular(7)),
        child: Row(children: [
          SizedBox(width: 34, height: 22, child: CustomPaint(painter: FcShapePreview(shape))),
          const SizedBox(width: 8),
          Expanded(
            child: Text(fcShapeLibraryName(shape),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: on ? C.primary : C.text)),
          ),
          if (k.isNotEmpty) Text(k, style: TextStyle(fontSize: 10, color: C.muted, fontFamily: 'monospace')),
        ]),
      ),
    );
  }
}

/// ภาพย่อของรูปทรงจริง (วาดด้วยตัววาดเดียวกับแคนวาส)
class FcShapePreview extends CustomPainter {
  FcShapePreview(this.shape);
  final FcShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final (w, h) = fcDefaultSize(shape);
    final s = (size.width / w) < (size.height / h) ? size.width / w : size.height / h;
    canvas.save();
    canvas.translate((size.width - w * s) / 2, (size.height - h * s) / 2);
    canvas.scale(s);
    // ข้อความลอยไม่มีกรอบ — ใส่ "Aa" ให้เห็นในภาพย่อ (ตามดีไซน์)
    final n = FcNode(id: 'p', shape: shape, text: shape == FcShape.text ? 'Aa' : '');
    paintFlowchart(canvas, FlowchartDiagram(nodes: [n]), shadows: false);
    canvas.restore();
  }

  @override
  bool shouldRepaint(FcShapePreview old) => old.shape != shape;
}
