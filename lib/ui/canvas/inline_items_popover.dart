import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/l10n.dart';
import '../theme.dart';

/// แก้รายการของชิ้นที่มีหลายค่า (หัวคอลัมน์ตาราง, แท็บ, เมนู, รายการ, แถบนำทางล่าง ฯลฯ) ในการ์ดเล็กใต้ชิ้นส่วน
/// — หนึ่งแถวต่อหนึ่งรายการ (ลากเรียงลำดับ / ลบ / เพิ่ม) ; ชิ้นส่วนบนแคนวาสยังมองเห็นครบและอัปเดตตามที่พิมพ์ ([onChanged])
/// ไม่ขึ้นกับรูปทรงของชิ้น (หมุนอยู่ หรือเล็กจนวาดรายการไม่ครบ ก็ใช้ได้) ; Enter = เพิ่มรายการต่อจากแถวนี้ ;
/// Esc = ยกเลิก ; Ctrl+Enter หรือคลิกที่อื่น (ไม่มีช่องไหนมีโฟกัส) = บันทึก ; ช่องว่าง = ลบรายการนั้นตอนบันทึก
/// ต้องวางเป็นลูกของ Stack ของแคนวาส
class InlineItemsPopover extends StatefulWidget {
  const InlineItemsPopover({
    super.key,
    required this.anchor,
    required this.viewport,
    required this.title,
    required this.values,
    required this.newItemText,
    required this.onChanged,
    required this.onCommit,
    required this.onCancel,
    this.onDone,
    this.initialFocus = 0,
  });

  /// กรอบของชิ้นส่วนบนจอ (กรอบที่ครอบชิ้นที่หมุนแล้ว) — การ์ดวางใต้กรอบนี้ (ไม่พอที่ = วางเหนือ)
  final Rect anchor;

  /// ขนาดพื้นที่แคนวาส (กันการ์ดล้นขอบ)
  final Size viewport;
  final String title;
  final List<String> values;
  final String newItemText;

  /// เรียกทุกครั้งที่แก้ (รายการที่ไม่ว่างเท่านั้น) — ให้ชิ้นส่วนแสดงสด
  final ValueChanged<List<String>> onChanged;
  final ValueChanged<List<String>> onCommit;
  final VoidCallback onCancel;
  final VoidCallback? onDone;
  final int initialFocus;

  @override
  State<InlineItemsPopover> createState() => _InlineItemsPopoverState();
}

class _Row {
  _Row(String text) : ctl = TextEditingController(text: text);
  final Key key = UniqueKey();
  final TextEditingController ctl;
  final FocusNode focus = FocusNode();
}

class _InlineItemsPopoverState extends State<InlineItemsPopover> {
  static const _rowH = 38.0;
  late final List<_Row> _rows = [for (final v in widget.values) _Row(v)];
  bool _done = false;

  @override
  void initState() {
    super.initState();
    for (final r in _rows) {
      _watch(r);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _rows.isNotEmpty) _rows[widget.initialFocus.clamp(0, _rows.length - 1)].focus.requestFocus();
    });
  }

  void _watch(_Row r) {
    r.focus.addListener(() {
      if (r.focus.hasFocus) r.ctl.selection = TextSelection(baseOffset: 0, extentOffset: r.ctl.text.length);
    });
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.ctl.dispose();
      r.focus.dispose();
    }
    super.dispose();
  }

  List<String> get _values => [
        for (final r in _rows)
          if (r.ctl.text.trim().isNotEmpty) r.ctl.text.trim(),
      ];

  void _changed() => widget.onChanged(_values);

  void _commit() {
    if (_done) return;
    _done = true;
    widget.onCommit(_values);
    widget.onDone?.call();
  }

  void _cancel() {
    if (_done) return;
    _done = true;
    widget.onCancel();
    widget.onDone?.call();
  }

  void _insert(int at) {
    final r = _Row(widget.newItemText);
    _watch(r);
    setState(() => _rows.insert(at.clamp(0, _rows.length), r));
    _changed();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) r.focus.requestFocus();
    });
  }

  void _remove(int i) {
    final r = _rows[i];
    setState(() => _rows.removeAt(i));
    _changed();
    // โฟกัสต้องไม่หลุดจากกลุ่ม ไม่งั้นนับเป็นคลิกที่อื่น = บันทึก
    if (_rows.isNotEmpty) {
      final next = _rows[i.clamp(0, _rows.length - 1)];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) next.focus.requestFocus();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      r.ctl.dispose();
      r.focus.dispose();
    });
  }

  void _reorder(int from, int to) {
    setState(() {
      _rows.insert(to, _rows.removeAt(from));
    });
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final listH = (_rows.length.clamp(1, 7)) * _rowH;
    return PopoverShell(
      cardKey: const ValueKey('wf-items-card'),
      anchor: widget.anchor,
      viewport: widget.viewport,
      estimatedHeight: 136.0 + listH,
      onCommit: _commit,
      onCancel: _cancel,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
          Text(tr('{0} รายการ', [_rows.length]), style: const TextStyle(fontSize: 11.5, color: Color(0xFF93A1B0))),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: listH,
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: EdgeInsets.zero,
            itemCount: _rows.length,
            onReorderItem: _reorder,
            proxyDecorator: (child, i, a) => Material(color: Colors.transparent, child: child),
            itemBuilder: (context, i) => _rowWidget(i),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('wf-items-add'),
            onPressed: () => _insert(_rows.length),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text(tr('เพิ่มรายการ'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF5EEAD4),
              side: const BorderSide(color: Color(0xFF3B4B5B)),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1, color: Color(0xFF2F3D4B)),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 4, children: [
          _popHint('Enter', tr('รายการใหม่')),
          _popHint('Esc', tr('ยกเลิก')),
          Text(tr('คลิกที่อื่น = บันทึก'), style: const TextStyle(fontSize: 11.5, color: Color(0xFF93A1B0))),
        ]),
      ]),
    );
  }

  Widget _rowWidget(int i) {
    final r = _rows[i];
    return SizedBox(
      key: r.key,
      height: _rowH,
      child: Row(children: [
        ReorderableDragStartListener(
          index: i,
          child: const MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: SizedBox(width: 26, height: 30, child: Icon(Icons.drag_indicator_rounded, size: 16, color: Color(0xFF93A1B0))),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 32,
            child: TextField(
              key: ValueKey('wf-item-$i'),
              controller: r.ctl,
              focusNode: r.focus,
              maxLines: 1,
              onChanged: (_) => _changed(),
              onSubmitted: (_) => _insert(i + 1),
              style: const TextStyle(fontSize: 13.5, color: Color(0xFFE2E8F0)),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF0F172A),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF3B4B5B))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: C.primary, width: 1.5)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        ExcludeFocus(
          child: IconButton(
          key: ValueKey('wf-item-del-$i'),
          tooltip: tr('ลบรายการ'),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 30, height: 30),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF93A1B0)),
          onPressed: () => _remove(i),
        ),
        ),
      ]),
    );
  }
}

Widget _popHint(String key, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(color: const Color(0xFF33465A), borderRadius: BorderRadius.circular(4)),
        child: Text(key, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
      ),
      const SizedBox(width: 5),
      Text(text, style: const TextStyle(fontSize: 11.5, color: Color(0xFF93A1B0))),
    ]);

/// กรอบการ์ดแก้ไขใต้ชิ้นส่วน (ใช้ร่วมกันของการ์ดรายการและการ์ดข้อความ) : วางใต้ [anchor] (ไม่พอที่ = เหนือ) ไม่ล้นขอบ ;
/// Esc = [onCancel] ; Ctrl+Enter = [onCommit] ; กดเมาส์นอกการ์ด (คลิกที่อื่น) = [onCommit]
/// ต้องวางเป็นลูกของ Stack ของแคนวาส
class PopoverShell extends StatefulWidget {
  const PopoverShell({
    super.key,
    required this.cardKey,
    required this.anchor,
    required this.viewport,
    required this.estimatedHeight,
    required this.onCommit,
    required this.onCancel,
    required this.child,
    this.width = 340,
  });

  final Key cardKey;
  final Rect anchor;
  final Size viewport;
  final double estimatedHeight;
  final VoidCallback onCommit, onCancel;
  final Widget child;
  final double width;

  @override
  State<PopoverShell> createState() => _PopoverShellState();
}

class _PopoverShellState extends State<PopoverShell> {
  /// เวลาตั้งแต่เปิดการ์ด — การกดเมาส์ที่ตามมาทันทีหลังเปิด (ปล่อยเมาส์/คลิกที่ 2 ของดับเบิลคลิก) ไม่นับเป็น "คลิกที่อื่น"
  final Stopwatch _opened = Stopwatch()..start();

  @override
  Widget build(BuildContext context) {
    final left = widget.anchor.left.clamp(8.0, (widget.viewport.width - widget.width - 8).clamp(8.0, double.infinity)).toDouble();
    var top = widget.anchor.bottom + 12;
    if (top + widget.estimatedHeight > widget.viewport.height && widget.anchor.top - widget.estimatedHeight - 12 >= 0) top = widget.anchor.top - widget.estimatedHeight - 12;
    // ไม่พอทั้งใต้และเหนือ (หน้าต่างเตี้ย) = ดันขึ้นให้การ์ดอยู่ในพื้นที่ที่มองเห็น (ทับชิ้นส่วนได้)
    top = top.clamp(8.0, (widget.viewport.height - widget.estimatedHeight - 8).clamp(8.0, double.infinity)).toDouble();
    return Positioned.fill(
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
            const SingleActivator(LogicalKeyboardKey.enter, control: true): widget.onCommit,
          },
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: left,
              top: top,
              width: widget.width,
              // คลิกนอกการ์ด = บันทึก (นับจากการกดเมาส์ ไม่ใช่โฟกัสหลุด — แคนวาสแย่งโฟกัสกลับหลังเปิดการ์ดได้โดยไม่ใช่การคลิกที่อื่น)
              child: TextFieldTapRegion(
                onTapOutside: (_) {
                  if (_opened.elapsedMilliseconds >= 400) widget.onCommit();
                },
                child: Material(
                  key: widget.cardKey,
                  color: const Color(0xFF1E2A36),
                  elevation: 10,
                  shadowColor: const Color(0x66000000),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFF2F3D4B))),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: DefaultTextStyle(style: const TextStyle(fontSize: 12, color: Color(0xFFE2E8F0)), child: widget.child),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// แก้ข้อความของชิ้นที่มีข้อความเดียว/ข้อความอิสระ (ปุ่ม ป้าย สวิตช์ ย่อหน้า ฯลฯ) ในการ์ดแบบเดียวกับการ์ดรายการ
/// — ชิ้นส่วนบนแคนวาสแสดงสดตามที่พิมพ์ ([onChanged]) ; บรรทัดเดียว: Enter = บันทึก ; หลายบรรทัด: Enter = ขึ้นบรรทัดใหม่ Ctrl+Enter = บันทึก
class InlineTextPopover extends StatefulWidget {
  const InlineTextPopover({
    super.key,
    required this.anchor,
    required this.viewport,
    required this.title,
    required this.initial,
    required this.multiline,
    required this.onChanged,
    required this.onCommit,
    required this.onCancel,
    this.onDone,
  });

  final Rect anchor;
  final Size viewport;
  final String title;
  final String initial;
  final bool multiline;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onCommit;
  final VoidCallback onCancel;
  final VoidCallback? onDone;

  @override
  State<InlineTextPopover> createState() => _InlineTextPopoverState();
}

class _InlineTextPopoverState extends State<InlineTextPopover> {
  late final TextEditingController _ctl = TextEditingController(text: widget.initial);
  final FocusNode _focus = FocusNode();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ctl.selection = TextSelection(baseOffset: 0, extentOffset: _ctl.text.length);
    // แคนวาสแย่งโฟกัสกลับหลังเปิดการ์ดได้ (เช่น ตอนปล่อยเมาส์จากดับเบิลคลิก) : คืนโฟกัสให้ช่อง ไม่งั้น Esc / พิมพ์ไม่เข้า
    // การคลิกนอกการ์ด/Esc/Ctrl+Enter ปิดการ์ดผ่าน _done จึงไม่ถูกดึงกลับ
    _focus.addListener(() {
      if (_focus.hasFocus || _done) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_done && !_focus.hasFocus) _focus.requestFocus();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    if (_done) return;
    _done = true;
    widget.onCommit(_ctl.text);
    widget.onDone?.call();
  }

  void _cancel() {
    if (_done) return;
    _done = true;
    widget.onCancel();
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    return PopoverShell(
      cardKey: const ValueKey('wf-text-card'),
      anchor: widget.anchor,
      viewport: widget.viewport,
      estimatedHeight: widget.multiline ? 200 : 116,
      onCommit: _commit,
      onCancel: _cancel,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('wf-inline-field'),
          controller: _ctl,
          focusNode: _focus,
          minLines: widget.multiline ? 3 : 1,
          maxLines: widget.multiline ? 8 : 1,
          keyboardType: widget.multiline ? TextInputType.multiline : TextInputType.text,
          onChanged: widget.onChanged,
          onSubmitted: widget.multiline ? null : (_) => _commit(),
          style: const TextStyle(fontSize: 13.5, color: Color(0xFFE2E8F0), height: 1.3),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: const Color(0xFF0F172A),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF3B4B5B))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: C.primary, width: 1.5)),
          ),
        ),
        const SizedBox(height: 10),
        const Divider(height: 1, color: Color(0xFF2F3D4B)),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 4, children: [
          _popHint(widget.multiline ? 'Ctrl+Enter' : 'Enter', tr('บันทึก')),
          _popHint('Esc', tr('ยกเลิก')),
          Text(tr('คลิกที่อื่น = บันทึก'), style: const TextStyle(fontSize: 11.5, color: Color(0xFF93A1B0))),
        ]),
      ]),
    );
  }
}
