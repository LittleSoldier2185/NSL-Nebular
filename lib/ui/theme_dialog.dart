import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nsl_ui/nsl_ui.dart' show NslThemeController;
import 'package:provider/provider.dart';

import '../core/l10n/l10n.dart';
import 'theme.dart';

/// ปุ่มเปิดหน้าเลือกธีมกลางของ NSL — ซ่อนเมื่อแอปไม่มีที่เก็บธีม (เช่นเปิดที่เก็บไม่ได้)
class ThemeButton extends StatelessWidget {
  const ThemeButton({super.key, required this.builder});

  /// สร้างปุ่มจริงจาก [open] (หน้าตาปุ่มเป็นของแถบบนเอง)
  final Widget Function(VoidCallback open) builder;

  @override
  Widget build(BuildContext context) {
    final c = themeControllerOf(context);
    if (c == null) return const SizedBox.shrink();
    return builder(() => showThemeDialog(context, c));
  }
}

/// ตัวควบคุมธีมกลางของแอป (null = ไม่มีที่เก็บ หรือหน้าจอนี้ไม่ได้อยู่ใต้ `NslDevApp`)
NslThemeController? themeControllerOf(BuildContext context) {
  try {
    return Provider.of<NslThemeController?>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}

Future<void> showThemeDialog(BuildContext context, NslThemeController c) =>
    showDialog<void>(context: context, builder: (_) => ThemeDialog(controller: c));

/// ไฟล์ธีมใหญ่เกินนี้ไม่อ่าน (ตัวเก็บธีมของ core ก็ข้ามไฟล์ใหญ่เกิน 64KB)
const kMaxThemeFileBytes = 64 * 1024;

class ThemeDialog extends StatefulWidget {
  const ThemeDialog({super.key, required this.controller});
  final NslThemeController controller;

  @override
  State<ThemeDialog> createState() => _ThemeDialogState();
}

class _ThemeDialogState extends State<ThemeDialog> {
  String? _message;
  bool _error = false;

  NslThemeController get _c => widget.controller;

  void _say(String m, {bool error = false}) => setState(() {
        _message = m;
        _error = error;
      });

  /// เปลี่ยนธีมแล้วแอปสร้างต้นไม้วิดเจ็ตใหม่ทั้งหมด (สีมาจากตัวแปรกลาง) หน้านี้จึงปิดไปกับต้นไม้เดิม — ปิดเองก่อนให้ชัดเจน
  void _apply(Future<void> Function() change) {
    final nav = Navigator.of(context);
    nav.pop();
    change();
  }

  Future<void> _import() async {
    final f = await FilePicker.pickFile(dialogTitle: tr('นำเข้าธีม'), type: FileType.custom, allowedExtensions: const ['nslt']);
    final path = f?.path;
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.length() > kMaxThemeFileBytes) {
        _say(tr('ไฟล์ธีมใหญ่เกินไป (ไม่เกิน 64 KB)'), error: true);
        return;
      }
      final r = await _c.importThemeText(await file.readAsString());
      if (!mounted) return;
      if (!r.ok) {
        _say(tr('นำเข้าไม่ได้: {0}', [r.errors.join('; ')]), error: true);
        return;
      }
      await _c.select(r.id);
      if (!mounted) return;
      _say(r.warnings.isEmpty
          ? tr('นำเข้าและใช้ธีม "{0}" แล้ว', [r.id])
          : tr('นำเข้าแล้ว (มีคำเตือน {0} ข้อ): {1}', [r.warnings.length, r.warnings.join('; ')]));
    } catch (e) {
      if (mounted) _say(tr('อ่านไฟล์ไม่ได้: {0}', [e]), error: true);
    }
  }

  Future<void> _export(String id) async {
    final text = _c.exportThemeText(id);
    if (text == null) return;
    try {
      final uri = await FilePicker.saveFile(dialogTitle: tr('ส่งออกธีม'), fileName: '$id.nslt', bytes: utf8.encode(text));
      if (uri != null && mounted) _say(tr('ส่งออกแล้ว'));
    } catch (e) {
      if (mounted) _say(tr('ส่งออกไม่ได้: {0}', [e]), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListenableBuilder(
          listenable: _c,
          builder: (context, _) {
            final active = _c.settings.activeThemeId;
            final themes = [..._c.userThemes]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
            return Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('ธีม'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(tr('ธีมที่สร้างด้วย NSL Palette ใช้ร่วมกับโปรแกรม NSL อื่นได้ เปลี่ยนแล้วมีผลทันที'), style: TextStyle(fontSize: 12.5, color: C.muted)),
                  SwitchListTile(
                    key: const ValueKey('theme-safe'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('โหมดปลอดภัย')),
                    subtitle: Text(tr('ไม่ใช้ธีมของผู้ใช้ (ใช้เมื่อธีมทำให้อ่านไม่ออก)')),
                    value: _c.safeMode,
                    onChanged: (v) => _apply(() => _c.setSafeMode(v)),
                  ),
                  const Divider(height: 12),
                  _option(key: 'theme-builtin', id: null, title: tr('ธีมในตัว (NSL Nebular)'), active: active),
                  for (final t in themes)
                    _option(
                      key: 'theme-${t.id}',
                      id: t.id,
                      title: t.name,
                      subtitle: t.id,
                      active: active,
                      trailing: IconButton(
                        tooltip: tr('ส่งออกธีมนี้'),
                        icon: const Icon(Icons.file_download_outlined, size: 20),
                        onPressed: () => _export(t.id),
                      ),
                    ),
                  if (themes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(tr('ยังไม่มีธีมของผู้ใช้ — นำเข้าไฟล์ .nslt หรือสร้างจาก NSL Palette'), style: TextStyle(fontSize: 12.5, color: C.muted)),
                    ),
                  for (final p in _c.problems)
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text(p, style: TextStyle(fontSize: 11.5, color: C.danger))),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_message!, key: const ValueKey('theme-message'), style: TextStyle(fontSize: 12.5, color: _error ? C.danger : C.muted)),
                    ),
                  const SizedBox(height: 10),
                  Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 6, children: [
                    OutlinedButton.icon(
                      key: const ValueKey('theme-import'),
                      onPressed: _import,
                      icon: const Icon(Icons.file_upload_outlined, size: 18),
                      label: Text(tr('นำเข้าไฟล์ธีม')),
                    ),
                    TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('ปิด'))),
                  ]),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }

  /// แถวเลือกธีม (ทำเองแทน Radio ของ Material เพื่อไม่ผูกกับ API ของ Radio ที่เปลี่ยนตามรุ่น Flutter)
  Widget _option({required String key, required String? id, required String title, String? subtitle, required String? active, Widget? trailing}) {
    final selected = id == active;
    return ListTile(
      key: ValueKey(key),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20, color: selected ? C.primary : C.muted),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle, style: TextStyle(fontSize: 11.5, color: C.muted)),
      trailing: trailing,
      selected: selected,
      onTap: () => _apply(() => _c.select(id)),
    );
  }
}
