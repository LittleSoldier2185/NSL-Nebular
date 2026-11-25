import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../theme.dart';

/// ตัวแก้รายการหลายค่าในแผงขวาของ Wireframe (หัวคอลัมน์ตาราง, แท็บ, เมนู, รายการ ฯลฯ) — หนึ่งแถวต่อหนึ่งรายการ
/// มีที่จับลากเรียงลำดับ เลขลำดับ ช่องชื่อ และปุ่มลบ ; ปุ่ม "เพิ่ม" ท้ายรายการ ; Enter ในช่อง = เพิ่มรายการต่อจากแถวนั้น
/// บันทึก ([onChanged]) เมื่อออกจากช่อง / เพิ่ม / ลบ / ลากเรียง (ไม่ใช่ทุกตัวอักษร — ไม่ให้ Undo ละเอียดเกินไป)
/// แถวที่ว่างตอนออกจากช่อง = ลบ ; ค่าที่เปลี่ยนจากภายนอก (Undo ฯลฯ) ขณะไม่ได้พิมพ์อยู่ = โหลดใหม่
class WfItemsEditor extends StatefulWidget {
  const WfItemsEditor({
    super.key,
    required this.label,
    required this.values,
    required this.newItemText,
    required this.onChanged,
    this.addLabel,
    this.hint,
  });

  final String label;
  final List<String> values;
  final String newItemText;
  final ValueChanged<List<String>> onChanged;
  final String? addLabel;
  final String? hint;

  @override
  State<WfItemsEditor> createState() => _WfItemsEditorState();
}

class _Row {
  _Row(String text) : ctl = TextEditingController(text: text);
  final Key key = UniqueKey();
  final TextEditingController ctl;
  final FocusNode focus = FocusNode();
  void dispose() {
    ctl.dispose();
    focus.dispose();
  }
}

class _WfItemsEditorState extends State<WfItemsEditor> {
  late List<_Row> _rows = [for (final v in widget.values) _newRow(v)];

  /// ค่าที่ส่งออก/โหลดล่าสุด — ใช้แยกว่า widget.values เปลี่ยนจากเราเองหรือจากภายนอก
  late List<String> _synced = List.of(widget.values);

  _Row _newRow(String text) {
    final r = _Row(text);
    r.focus.addListener(() => _onFocus(r));
    return r;
  }

  void _onFocus(_Row r) {
    if (r.focus.hasFocus) {
      r.ctl.selection = TextSelection(baseOffset: 0, extentOffset: r.ctl.text.length);
      return;
    }
    if (!mounted || !_rows.contains(r)) return;
    if (r.ctl.text.trim().isEmpty) {
      // ช่องว่างตอนออกจากช่อง = ลบรายการนั้น
      setState(() => _rows.remove(r));
      WidgetsBinding.instance.addPostFrameCallback((_) => r.dispose());
    }
    // รอท้ายเฟรมก่อนบันทึก : กด Enter ทำให้ช่องเสียโฟกัสแล้วเพิ่มแถวในจังหวะเดียวกัน ให้รวมเป็นการบันทึกครั้งเดียว (undo ขั้นเดียว)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _commit();
    });
  }

  List<String> get _values => [
        for (final r in _rows)
          if (r.ctl.text.trim().isNotEmpty) r.ctl.text.trim(),
      ];

  void _commit() {
    final v = _values;
    if (listEquals(v, _synced)) return;
    _synced = v;
    widget.onChanged(v);
  }

  @override
  void didUpdateWidget(WfItemsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (listEquals(widget.values, _synced)) return;
    if (!listEquals(_values, _synced)) return; // มีที่พิมพ์ค้างยังไม่บันทึก ไม่ทับ
    final dropped = _rows;
    _rows = [for (final v in widget.values) _newRow(v)];
    _synced = List.of(widget.values);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final r in dropped) {
        r.dispose();
      }
    });
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _insert(int at) {
    final r = _newRow(widget.newItemText);
    setState(() => _rows.insert(at.clamp(0, _rows.length), r));
    _commit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) r.focus.requestFocus();
    });
  }

  void _remove(int i) {
    final r = _rows[i];
    setState(() => _rows.removeAt(i));
    _commit();
    WidgetsBinding.instance.addPostFrameCallback((_) => r.dispose());
  }

  void _reorder(int from, int to) {
    setState(() => _rows.insert(to, _rows.removeAt(from)));
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(widget.label, style: TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w600))),
        Text(tr('{0} รายการ', [_rows.length]), key: const ValueKey('wf-prop-items-count'), style: TextStyle(fontSize: 11.5, color: C.muted)),
      ]),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: C.bg, border: Border.all(color: C.borderSoft), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_rows.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              padding: EdgeInsets.zero,
              itemCount: _rows.length,
              onReorderItem: _reorder,
              proxyDecorator: (child, i, a) => Material(color: Colors.transparent, child: child),
              itemBuilder: (context, i) => _rowWidget(i),
            ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            key: const ValueKey('wf-prop-items-add'),
            onPressed: () => _insert(_rows.length),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text(widget.addLabel ?? tr('เพิ่มรายการ'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: C.primaryDark,
              side: BorderSide(color: C.border),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ]),
      ),
      if (widget.hint != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
          child: Text(widget.hint!, style: TextStyle(fontSize: 11.5, color: C.muted)),
        ),
    ]);
  }

  Widget _rowWidget(int i) {
    final r = _rows[i];
    return SizedBox(
      key: r.key,
      height: 38,
      child: Row(children: [
        ReorderableDragStartListener(
          index: i,
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: SizedBox(width: 24, height: 32, child: Icon(Icons.drag_indicator_rounded, size: 16, color: C.muted)),
          ),
        ),
        SizedBox(width: 18, child: Text('${i + 1}', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: C.muted))),
        const SizedBox(width: 4),
        Expanded(
          child: SizedBox(
            height: 34,
            child: TextField(
              key: ValueKey('wf-prop-item-$i'),
              controller: r.ctl,
              focusNode: r.focus,
              maxLines: 1,
              onSubmitted: (_) => _insert(i + 1),
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ),
        ExcludeFocus(
          child: IconButton(
            key: ValueKey('wf-prop-item-del-$i'),
            tooltip: tr('ลบรายการ'),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            padding: EdgeInsets.zero,
            icon: Icon(Icons.close_rounded, size: 16, color: C.muted),
            onPressed: () => _remove(i),
          ),
        ),
      ]),
    );
  }
}
