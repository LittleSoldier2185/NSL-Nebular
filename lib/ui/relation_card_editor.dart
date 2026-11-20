import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/l10n.dart';
import '../core/layout/diagram_geometry.dart';
import '../core/models/column_model.dart';
import '../core/models/enums.dart';
import '../core/models/relation_model.dart';
import '../core/models/table_model.dart';
import '../state/project_controller.dart';
import 'canvas/relation_symbols.dart';
import 'theme.dart';

/// ส่วน "ความสัมพันธ์" ในกล่อง Foreign Key ของแผงขวา (Phase 17b, ดีไซน์แบบ B):
/// ภาพตัวอย่างสดของเส้น + ปุ่มรูปสัญลักษณ์ 3 กลุ่ม (ฝั่งแม่ / ฝั่งลูกจำนวน / ฝั่งลูกขั้นต่ำ) ทุกกลุ่มมี "อัตโนมัติ"
/// ค่าที่เลือกเป็นเอกสารล้วน ไม่เปลี่ยน DDL ; เลือกขัดกับสคีมาจะมีแถบเตือนพร้อมปุ่มแก้สคีมา (ผู้ใช้กดเอง)
class RelationCardEditor extends StatelessWidget {
  const RelationCardEditor({super.key, required this.relation});
  final RelationModel relation;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProjectController>();
    final child = c.project.tableById(relation.fromTableId);
    final parent = c.project.tableById(relation.toTableId);
    final col = child?.columnById(relation.fromColumnId);
    if (child == null || parent == null || col == null) return const SizedBox.shrink();
    final auto = autoCardinality(child, col);
    final eff = relationCardinality(relation, child, col);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('ความสัมพันธ์'), style: TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      _Preview(parentName: parent.name, childName: child.name, card: eff),
      const SizedBox(height: 10),
      _group<ParentCard>(
        keyPrefix: 'card-parent',
        title: tr('ปลายฝั่งแม่'),
        tableName: parent.name,
        current: relation.parentCard,
        autoNote: col.notNull || col.isPrimaryKey ? tr('อัตโนมัติ: FK เป็น NOT NULL') : tr('อัตโนมัติ: FK เป็น NULL ได้'),
        onPick: (v) => c.setRelationParentCard(relation.id, v),
        options: [
          (null, tr('อัตโนมัติ'), _GlyphSpec.parent(auto.parentRequired)),
          (ParentCard.zeroOne, tr('ศูนย์หรือหนึ่ง'), const _GlyphSpec.parent(false)),
          (ParentCard.one, tr('หนึ่งเดียว'), const _GlyphSpec.parent(true)),
        ],
      ),
      const SizedBox(height: 10),
      _group<ChildMax>(
        keyPrefix: 'card-cmax',
        title: tr('ปลายฝั่งลูก'),
        tableName: child.name,
        current: relation.childMax,
        autoNote: auto.childOne ? tr('อัตโนมัติ: FK เป็น UNIQUE') : tr('อัตโนมัติ: FK ไม่ UNIQUE'),
        onPick: (v) => c.setRelationChildMax(relation.id, v),
        options: [
          (null, tr('อัตโนมัติ'), _GlyphSpec.child(auto.childOne, false)),
          (ChildMax.one, tr('หนึ่ง'), const _GlyphSpec.child(true, false)),
          (ChildMax.many, tr('หลาย'), const _GlyphSpec.child(false, false)),
        ],
      ),
      const SizedBox(height: 10),
      _group<ChildMin>(
        keyPrefix: 'card-cmin',
        title: tr('ลูกขั้นต่ำ'),
        tableName: null,
        current: relation.childMin,
        autoNote: tr('อัตโนมัติ: ไม่มีข้อมูลในสคีมา จึงเป็น 0'),
        onPick: (v) => c.setRelationChildMin(relation.id, v),
        options: [
          (null, tr('อัตโนมัติ'), _GlyphSpec.child(eff.childOne, auto.childRequired)),
          (ChildMin.zero, tr('0 (ไม่บังคับ)'), _GlyphSpec.child(eff.childOne, false)),
          (ChildMin.one, tr('อย่างน้อย 1'), _GlyphSpec.child(eff.childOne, true)),
        ],
      ),
      ..._warnings(context, c, child, col, auto, eff),
    ]);
  }

  Widget _group<T>({
    required String keyPrefix,
    required String title,
    required String? tableName,
    required T? current,
    required String autoNote,
    required void Function(T?) onPick,
    required List<(T?, String, _GlyphSpec)> options,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: title, style: TextStyle(fontSize: 12, color: C.muted)),
              if (tableName != null) ...[
                const TextSpan(text: '  '),
                TextSpan(text: tableName, style: monoStyle.copyWith(fontSize: 11.5, color: C.text)),
              ],
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (current != null)
          InkWell(
            key: ValueKey('$keyPrefix-reset'),
            onTap: () => onPick(null),
            child: Text(tr('กลับเป็นอัตโนมัติ'), style: TextStyle(fontSize: 11.5, color: C.primaryDark, decoration: TextDecoration.underline)),
          )
        else
          Flexible(child: Text(autoNote, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: C.muted))),
      ]),
      const SizedBox(height: 4),
      Row(children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _GlyphButton(
              key: ValueKey('$keyPrefix-${options[i].$1?.toString().split('.').last ?? 'auto'}'),
              label: options[i].$2,
              spec: options[i].$3,
              selected: current == options[i].$1,
              onTap: () => onPick(options[i].$1),
            ),
          ),
        ],
      ]),
    ]);
  }

  /// แถบเตือนเมื่อสัญลักษณ์ที่เลือกขัดกับสคีมา (พร้อมปุ่มแก้สคีมา) และข้อความของ "อย่างน้อย 1"
  List<Widget> _warnings(BuildContext context, ProjectController c, TableModel child, ColumnModel col,
      RelationCardinality auto, RelationCardinality eff) {
    final out = <Widget>[];
    void warn(String key, String text, String? action, VoidCallback? fix) {
      out.add(Container(
        key: ValueKey(key),
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(color: C.warnBg, borderRadius: BorderRadius.circular(8)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(text, style: TextStyle(fontSize: 11.5, color: C.warnText))),
          if (action != null) ...[
            const SizedBox(width: 6),
            OutlinedButton(
              key: ValueKey('$key-fix'),
              onPressed: fix,
              style: OutlinedButton.styleFrom(
                foregroundColor: C.warnText,
                side: BorderSide(color: C.warnText),
                minimumSize: const Size(0, 26),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(fontSize: 11.5),
              ),
              child: Text(action),
            ),
          ],
        ]),
      ));
    }

    void edit(void Function(ColumnModel) f) => c.updateColumn(child.id, col.id, f);

    if (eff.childOne && !auto.childOne) {
      warn('card-warn-uq', tr('เลือก "หนึ่ง" แต่ FK ยังไม่ UNIQUE ฐานข้อมูลยังให้ลูกซ้ำได้'), tr('ตั้ง UNIQUE'), () => edit((x) => x.unique = true));
    } else if (!eff.childOne && auto.childOne && relation.childMax != null) {
      warn('card-warn-uqoff', tr('เลือก "หลาย" แต่ FK เป็น UNIQUE ฐานข้อมูลไม่ให้ซ้ำ'),
          col.unique ? tr('เอา UNIQUE ออก') : null, col.unique ? () => edit((x) => x.unique = false) : null);
    }
    if (eff.parentRequired && !auto.parentRequired) {
      warn('card-warn-nn', tr('เลือก "หนึ่งเดียว" แต่ FK เป็น NULL ได้ ลูกบางแถวไม่มีแม่ได้'), tr('ตั้ง NOT NULL'), () => edit((x) => x.notNull = true));
    } else if (!eff.parentRequired && auto.parentRequired && relation.parentCard != null) {
      final canOff = col.notNull && !col.isPrimaryKey;
      warn('card-warn-nnoff', tr('เลือก "ศูนย์หรือหนึ่ง" แต่ FK เป็น NOT NULL ลูกต้องมีแม่เสมอ'),
          canOff ? tr('เอา NOT NULL ออก') : null, canOff ? () => edit((x) => x.notNull = false) : null);
    }
    if (eff.childRequired) {
      warn('card-warn-min1', tr('"ต้องมีลูกอย่างน้อย 1" ฐานข้อมูลบังคับให้ไม่ได้ บังคับที่ฝั่งแอปหรือทริกเกอร์ ค่านี้เป็นเอกสารอย่างเดียว'), null, null);
    }
    return out;
  }
}

/// ภาพปลายเส้นของปุ่มหนึ่งปุ่ม
class _GlyphSpec {
  const _GlyphSpec.parent(this.required)
      : isParent = true,
        one = false;
  const _GlyphSpec.child(this.one, this.required) : isParent = false;

  final bool isParent;
  final bool one;
  final bool required;
}

class _GlyphButton extends StatelessWidget {
  const _GlyphButton({super.key, required this.label, required this.spec, required this.selected, required this.onTap});
  final String label;
  final _GlyphSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 5),
          decoration: BoxDecoration(
            color: selected ? C.primaryTint : C.surface,
            border: Border.all(color: selected ? C.primary : C.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CustomPaint(size: const Size(double.infinity, 26), painter: _GlyphPainter(spec, C.text, C.surface)),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.25,
                color: selected ? C.primaryDark : C.muted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ]),
        ),
      );
}

Paint _linePaint(Color color) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = 1.6
  ..strokeCap = StrokeCap.round;

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.spec, this.color, this.knockout);
  final _GlyphSpec spec;
  final Color color;
  final Color knockout;

  @override
  void paint(Canvas canvas, Size size) {
    final p = _linePaint(color);
    final y = size.height / 2;
    final w = size.width;
    canvas.drawLine(Offset(2, y), Offset(w - 2, y), p);
    if (spec.isParent) {
      // ปลายแม่ ยื่นไปทางขวาจากขอบที่กึ่งกลาง ; ขอบการ์ดจริงคือเส้นประเล็กน้อย
      drawParentEnd(canvas, p, w / 2 - 10, y, 1, required: spec.required, knockout: knockout);
    } else {
      drawChildEnd(canvas, p, w / 2 + 14, y, -1, one: spec.one, required: spec.required, knockout: knockout);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.spec.isParent != spec.isParent ||
      old.spec.one != spec.one ||
      old.spec.required != spec.required ||
      old.color != color ||
      old.knockout != knockout;
}

/// ภาพตัวอย่างสดของเส้น: ตารางแม่ซ้าย — ตารางลูกขวา
class _Preview extends StatelessWidget {
  const _Preview({required this.parentName, required this.childName, required this.card});
  final String parentName, childName;
  final RelationCardinality card;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('card-preview'),
        height: 64,
        decoration: BoxDecoration(color: C.canvas, border: Border.all(color: C.borderSoft), borderRadius: BorderRadius.circular(8)),
        child: LayoutBuilder(
          builder: (context, box) => Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _PreviewPainter(card, C.text, C.canvas, C.surface, C.border))),
            Positioned(left: 8, top: 14, width: 64, height: 36, child: Center(child: _name(parentName))),
            Positioned(right: 8, top: 14, width: 64, height: 36, child: Center(child: _name(childName))),
          ]),
        ),
      );

  Widget _name(String s) => Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: monoStyle.copyWith(fontSize: 10, color: C.text));
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.card, this.line, this.knockout, this.boxFill, this.boxBorder);
  final RelationCardinality card;
  final Color line, knockout, boxFill, boxBorder;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final left = 8 + 64.0, right = size.width - 8 - 64.0;
    for (final r in [Rect.fromLTWH(8, 14, 64, 36), Rect.fromLTWH(size.width - 72, 14, 64, 36)]) {
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(6));
      canvas.drawRRect(rr, Paint()..color = boxFill);
      canvas.drawRRect(rr, Paint()..color = boxBorder..style = PaintingStyle.stroke);
    }
    final p = _linePaint(line);
    canvas.drawLine(Offset(left, y), Offset(right, y), p);
    drawParentEnd(canvas, p, left, y, 1, required: card.parentRequired, knockout: knockout);
    drawChildEnd(canvas, p, right, y, -1, one: card.childOne, required: card.childRequired, knockout: knockout);
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.card.parentRequired != card.parentRequired ||
      old.card.childOne != card.childOne ||
      old.card.childRequired != card.childRequired ||
      old.line != line ||
      old.knockout != knockout ||
      old.boxFill != boxFill ||
      old.boxBorder != boxBorder;
}
