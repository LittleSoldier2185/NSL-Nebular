import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../core/l10n/l10n.dart' show currentLang;
import 'theme.dart';

/// ความสูงมาตรฐานของช่องกรอก/ดรอปดาวน์ในแผงข้าง (ให้เรียงกันแล้วสมส่วน)
const double kFieldHeight = 36;

/// ช่องกรอกที่บันทึกค่าตอนกด Enter หรือออกจากช่อง (ไม่สร้างประวัติ undo ทุกตัวอักษร)
/// ใส่ key ที่ผูกกับ id ของข้อมูล เพื่อให้ค่าในช่องรีเซ็ตเมื่อเปลี่ยนรายการที่เลือก
class CommitField extends StatefulWidget {
  const CommitField({
    super.key,
    required this.value,
    required this.onCommit,
    this.hint,
    this.mono = false,
    this.height = kFieldHeight,
    this.label,
    this.fontSize = 13,
    this.minLines,
    this.maxLines,
  });

  final String value;
  final ValueChanged<String> onCommit;
  final String? hint;
  final bool mono;
  final double height;
  final String? label;
  final double fontSize;

  /// ไม่ null = ช่องหลายบรรทัด (สูงตามจำนวนบรรทัด Enter ขึ้นบรรทัดใหม่ บันทึกเมื่อออกจากช่อง)
  final int? minLines;
  final int? maxLines;

  @override
  State<CommitField> createState() => _CommitFieldState();
}

class _CommitFieldState extends State<CommitField> {
  late final TextEditingController _ctl = TextEditingController(text: widget.value);
  late final FocusNode _focus = FocusNode()..addListener(_onFocus);

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    if (_ctl.text != widget.value) widget.onCommit(_ctl.text);
  }

  @override
  void didUpdateWidget(CommitField old) {
    super.didUpdateWidget(old);
    // ค่าเปลี่ยนจากภายนอก (undo ฯลฯ) และผู้ใช้ไม่ได้กำลังพิมพ์อยู่
    if (widget.value != old.value && !_focus.hasFocus && _ctl.text != widget.value) {
      _ctl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.minLines != null;
    // ช่องบรรทัดเดียว: SizedBox สูงคงที่ + expands ให้ตัวแก้ไขเต็มความสูง กรอบจึงสูงเท่าดรอปดาวน์ข้างเคียง
    // (InputDecoration.constraints ขยายแค่กล่อง กรอบที่วาดยังเตี้ยเท่าตัวอักษร)
    final field = SizedBox(
      height: multi ? null : widget.height,
      child: TextField(
        controller: _ctl,
        focusNode: _focus,
        onSubmitted: multi ? null : (_) => _commit(),
        minLines: multi ? widget.minLines : null,
        maxLines: multi ? widget.maxLines : null,
        expands: !multi,
        keyboardType: multi ? TextInputType.multiline : TextInputType.text,
        textAlignVertical: multi ? TextAlignVertical.top : TextAlignVertical.center,
        style: (widget.mono ? monoStyle : const TextStyle()).copyWith(fontSize: widget.fontSize, color: C.text),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(fontSize: widget.fontSize, color: C.muted),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: multi ? 10 : 0),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: C.inputBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: C.primary, width: 1.5),
          ),
        ),
      ),
    );
    return widget.label == null ? field : LabeledField(label: widget.label!, child: field);
  }
}

class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w500)),
          const SizedBox(height: 5),
          child,
        ],
      );
}

/// กล่องเลือกค่าจากรายการ — จำวิดเจ็ตที่สร้างไว้ : แผงขวาถูกสร้างใหม่บ่อย (เช่น ทุกเฟรมตอนลากวัตถุ) และ
/// [DropdownButton] สร้างทุกรายการทุกครั้ง (วัดความกว้าง) ; ค่า/รายการ/ธีม/ภาษาเดิม = ใช้ของเดิม (กดเลือกเรียก [onChanged] ล่าสุดเสมอ)
class Dropdown<T> extends StatefulWidget {
  const Dropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.labelOf,
    this.height = kFieldHeight,
  });

  final T value;
  final List<T> items;
  final ValueChanged<T> onChanged;
  final String Function(T) labelOf;
  final double height;

  @override
  State<Dropdown<T>> createState() => _DropdownState<T>();
}

class _DropdownState<T> extends State<Dropdown<T>> {
  List<Object?>? _key;
  Widget? _built;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final key = <Object?>[
      w.value,
      w.height,
      identityHashCode(C.palette),
      currentLang,
      for (final i in w.items) ...[i, w.labelOf(i)],
    ];
    final old = _key;
    if (_built != null && old != null && listEquals(old, key)) return _built!;
    _key = key;
    return _built = Container(
      height: w.height,
      padding: const EdgeInsets.only(left: 10, right: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: C.inputBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        // ค่าของเมนูเป็น "ลำดับในรายการ" ไม่ใช่ตัวข้อมูลเอง : ถ้าใช้ตัวข้อมูล ค่า null (เช่น "ทุกชนิด" / "ไม่ผูกตาราง") จะแยกไม่ออกจาก "ไม่ได้เลือก" และถูกทิ้ง
        child: DropdownButton<int>(
          value: () {
            final idx = w.items.indexOf(w.value);
            return idx < 0 ? null : idx; // ค่าที่ไม่อยู่ในรายการ = ไม่เลือก (เดิมจะ error)
          }(),
          isExpanded: true,
          isDense: true,
          style: TextStyle(fontSize: 13, color: C.text, fontFamily: kThai),
          items: [
            // บรรทัดเดียวเสมอ (เช่น NO ACTION ในแผงแคบ ย่อด้วย … ไม่ตัดขึ้นบรรทัดใหม่จนกล่องสูงไม่เท่ากัน)
            for (final (n, i) in w.items.indexed)
              DropdownMenuItem(
                value: n,
                child: Text(w.labelOf(i), maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (n) {
            // widget ล่าสุด ไม่ใช่ตัวที่จับไว้ตอนสร้าง ; รายการเปลี่ยน = สร้างเมนูใหม่ (คีย์แคชรวมรายการ) จึงลำดับตรงกันเสมอ
            if (n != null && n < widget.items.length) widget.onChanged(widget.items[n]);
          },
        ),
      ),
    );
  }
}

/// ปุ่มเล็กขอบบาง ใช้ซ้ำทั้งแอป
class SmallButton extends StatelessWidget {
  const SmallButton({super.key, required this.label, required this.onTap, this.icon});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onTap,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 15),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: C.primary,
          side: BorderSide(color: C.border),
          minimumSize: const Size(0, 28),
          padding: EdgeInsets.symmetric(horizontal: icon == null ? 10 : 8),
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      );
}

class Chip2 extends StatelessWidget {
  const Chip2(this.text, this.bg, this.fg, {super.key});
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: monoStyle.copyWith(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
      );
}
