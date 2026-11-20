import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import 'theme.dart';

/// ยืนยันการทำสิ่งที่เลิกทำไม่ได้ (Phase 21 ข้อ 7) : ต้องพิมพ์ [phrase] ให้ตรงจึงกดปุ่มได้ — คืน true เมื่อยืนยัน
/// ใช้เฉพาะงานที่ลบแล้วกู้ไม่ได้ ; ถ้าเลิกทำ (Ctrl+Z) ได้ ให้ใช้ปุ่มธรรมดา
Future<bool> confirmTyped(BuildContext context, {required String title, required String message, required String phrase, required String action}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => _TypedConfirm(title: title, message: message, phrase: phrase, action: action),
  );
  return r == true;
}

class _TypedConfirm extends StatefulWidget {
  const _TypedConfirm({required this.title, required this.message, required this.phrase, required this.action});
  final String title, message, phrase, action;

  @override
  State<_TypedConfirm> createState() => _TypedConfirmState();
}

class _TypedConfirmState extends State<_TypedConfirm> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _c.text.trim() == widget.phrase;
    return AlertDialog(
      key: const ValueKey('typed-confirm'),
      title: Text(widget.title, style: TextStyle(color: C.danger, fontSize: 16, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.message, style: const TextStyle(height: 1.45)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: C.dangerBg, borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('พิมพ์ {0} เพื่อยืนยัน', [widget.phrase]), style: TextStyle(fontSize: 12.5, color: C.danger)),
              const SizedBox(height: 6),
              TextField(
                key: const ValueKey('typed-confirm-input'),
                controller: _c,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(isDense: true),
              ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('ยกเลิก'))),
        FilledButton(
          key: const ValueKey('typed-confirm-ok'),
          style: FilledButton.styleFrom(backgroundColor: C.danger),
          onPressed: ok ? () => Navigator.pop(context, true) : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}
