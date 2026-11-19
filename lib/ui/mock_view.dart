import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/l10n/l10n.dart';
import '../core/mock/mock_engine.dart';
import '../core/mock/mock_settings.dart';
import '../core/models/api_model.dart';
import '../state/mock_controller.dart';
import '../state/workspace_controller.dart';
import 'api/api_view.dart' show ApiMethodChip;
import 'theme.dart';

String mockScenarioLabel(MockScenario s) => switch (s) {
  MockScenario.normal => tr('ปกติ'),
  MockScenario.conflict => tr('409 ซ้ำ'),
  MockScenario.unauthorized => tr('401 ไม่ได้ล็อกอิน'),
  MockScenario.serverError => tr('500 ผิดพลาด'),
  MockScenario.random => tr('สุ่ม'),
};

Color _statusColor(int s) => s >= 500 ? C.danger : (s >= 400 ? C.warnText : C.primaryDark);

String _clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

/// หน้า Mock Server (Artboard `Mock`): เริ่ม/หยุดเซิร์ฟเวอร์ localhost จาก API Designer · สถานการณ์ต่อ endpoint · บันทึกคำขอ
/// แสดงแทนแคนวาสขณะ [WorkspaceController.page] == [WorkspacePage.mock]
class MockView extends StatefulWidget {
  const MockView({super.key});

  @override
  State<MockView> createState() => _MockViewState();
}

class _MockViewState extends State<MockView> {
  late final TextEditingController _port;

  @override
  void initState() {
    super.initState();
    _port = TextEditingController(text: '${context.read<WorkspaceController>().mockSettings.port}');
  }

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));

  /// พอร์ตที่พิมพ์ (ผิดรูป = ค่าเดิมในไฟล์)
  int _typedPort(WorkspaceController w) {
    final n = int.tryParse(_port.text.trim());
    return n != null && n >= 0 && n <= 65535 ? n : w.mockSettings.port;
  }

  Future<void> _toggle(WorkspaceController w, MockController m) async {
    if (m.running) {
      await m.stop();
      return;
    }
    w.setMockSettings(w.mockSettings.copyWith(port: _typedPort(w)));
    await m.start();
  }

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    final m = context.watch<MockController>();
    final doc = w.mockApiDocument;
    final api = doc?.api;
    final settings = w.mockSettings;
    final apiDocs = [for (final d in w.workspace.documents) if (d.api != null) d];

    if (api == null) {
      return Container(
        key: const ValueKey('mock-view'),
        color: C.bg,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_rounded, size: 40, color: C.muted),
            const SizedBox(height: 12),
            Text(
              tr('Mock Server สร้างจากเอกสาร API — ยังไม่มีเอกสาร API ในโปรเจกต์'),
              key: const ValueKey('mock-empty'),
              textAlign: TextAlign.center,
              style: TextStyle(color: C.muted),
            ),
          ],
        ),
      );
    }

    final header = Material(
      color: C.surface,
      shape: Border(bottom: BorderSide(color: C.border)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(tr('Mock Server'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: C.text)),
            if (apiDocs.length > 1)
              DropdownButton<String>(
                key: const ValueKey('mock-api-doc'),
                value: doc!.id,
                isDense: true,
                onChanged: m.running ? null : (v) => w.setMockSettings(settings.copyWith(apiDocId: v)),
                items: [for (final d in apiDocs) DropdownMenuItem(value: d.id, child: Text(d.name, style: const TextStyle(fontSize: 13)))],
              )
            else
              Text(doc!.name, style: TextStyle(fontSize: 13, color: C.muted)),
            SizedBox(
              width: 120,
              child: TextField(
                key: const ValueKey('mock-port'),
                controller: _port,
                enabled: !m.running,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                decoration: InputDecoration(isDense: true, labelText: tr('พอร์ต')),
              ),
            ),
            FilledButton.icon(
              key: const ValueKey('mock-toggle'),
              style: m.running ? FilledButton.styleFrom(backgroundColor: C.danger) : null,
              onPressed: m.busy ? null : () => _toggle(w, m),
              icon: Icon(m.running ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
              label: Text(m.running ? tr('หยุด') : tr('เริ่ม')),
            ),
            if (m.running) ...[
              Container(
                key: const ValueKey('mock-url'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: C.primaryTint, borderRadius: BorderRadius.circular(8)),
                child: SelectableText(m.url!, style: TextStyle(fontSize: 12.5, fontFamily: 'monospace', color: C.primaryDark)),
              ),
              IconButton(
                key: const ValueKey('mock-copy-url'),
                tooltip: tr('คัดลอกที่อยู่'),
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: m.url!));
                  _toast(tr('คัดลอกแล้ว'));
                },
                icon: const Icon(Icons.copy_rounded, size: 17),
              ),
            ],
            OutlinedButton(
              key: const ValueKey('mock-reset'),
              onPressed: m.running ? m.resetData : null,
              child: Text(tr('รีเซ็ตข้อมูล')),
            ),
            if (m.error != null)
              Text(m.error!, key: const ValueKey('mock-error'), style: TextStyle(fontSize: 12.5, color: C.dangerText)),
          ],
        ),
      ),
    );

    final endpoints = Material(
      color: C.surface,
      shape: Border(right: BorderSide(color: C.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
            child: Text(tr('Endpoint · {0}', [api.endpoints.length]), style: TextStyle(fontWeight: FontWeight.w700, color: C.text)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(
              tr('สุ่ม = ปกติ 70% · 500 20% · 409 10% ; หน่วงใช้ได้ทุกสถานการณ์'),
              style: TextStyle(fontSize: 11.5, color: C.muted),
            ),
          ),
          Expanded(
            child: api.endpoints.isEmpty
                ? Center(child: Text(tr('API นี้ยังไม่มี endpoint'), style: TextStyle(color: C.muted)))
                : ListView(
                    children: [
                      for (final e in api.endpoints)
                        _EndpointRow(
                          key: ValueKey('mock-ep-${e.id}'),
                          endpoint: e,
                          setting: settings.of(e.id),
                          onChanged: (s) => w.setMockSettings(settings.withEndpoint(e.id, s)),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );

    final entries = m.log.reversed.toList();
    final logPane = Container(
      color: C.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(tr('บันทึกคำขอ · {0}', [entries.length]), key: const ValueKey('mock-log-count'), style: TextStyle(fontWeight: FontWeight.w700, color: C.text)),
                ),
                TextButton(key: const ValueKey('mock-clear-log'), onPressed: entries.isEmpty ? null : m.clearLog, child: Text(tr('ล้างบันทึก'))),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        m.running ? tr('ยังไม่มีคำขอ — ลองเรียก {0}', [m.url!]) : tr('กด "เริ่ม" แล้วเรียก API จากแอปหรือเครื่องมือของคุณ'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: C.muted),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (_, i) => _LogRow(
                      key: ValueKey('mock-log-${entries.length - i}'),
                      entry: entries[i],
                      onAdd: () {
                        final made = m.addEndpointFromLog(entries[i]);
                        if (made != null) _toast(tr('เพิ่ม endpoint {0} แล้ว', [made.title]));
                      },
                    ),
                  ),
          ),
        ],
      ),
    );

    return Container(
      key: const ValueKey('mock-view'),
      color: C.bg,
      child: Column(
        children: [
          header,
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                if (box.maxWidth < 900) {
                  return Column(
                    children: [
                      Expanded(child: endpoints),
                      Expanded(child: logPane),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 470, child: endpoints),
                    Expanded(child: logPane),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({super.key, required this.endpoint, required this.setting, required this.onChanged});
  final ApiEndpoint endpoint;
  final MockEndpointSetting setting;
  final ValueChanged<MockEndpointSetting> onChanged;

  @override
  Widget build(BuildContext context) {
    final e = endpoint;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          ApiMethodChip(e.method),
          const SizedBox(width: 8),
          Expanded(
            child: Text(e.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontFamily: 'monospace', color: C.text)),
          ),
          DropdownButton<MockScenario>(
            key: ValueKey('mock-scenario-${e.id}'),
            value: setting.scenario,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: TextStyle(fontSize: 12.5, color: setting.scenario == MockScenario.normal ? C.text : C.warnText),
            onChanged: (v) => onChanged(setting.copyWith(scenario: v)),
            items: [for (final s in MockScenario.values) DropdownMenuItem(value: s, child: Text(mockScenarioLabel(s)))],
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 64,
            child: TextFormField(
              key: ValueKey('mock-delay-${e.id}'),
              initialValue: setting.delayMs == 0 ? '' : '${setting.delayMs}',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
              style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
              decoration: InputDecoration(isDense: true, hintText: tr('หน่วง ms'), hintStyle: const TextStyle(fontSize: 10.5)),
              onChanged: (v) => onChanged(setting.copyWith(delayMs: int.tryParse(v) ?? 0)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({super.key, required this.entry, required this.onAdd});
  final MockLogEntry entry;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.borderSoft))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_clock(e.time), style: TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: C.muted)),
              const SizedBox(width: 8),
              SizedBox(
                width: 52,
                child: Text(e.method, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.text)),
              ),
              Expanded(
                child: Text(e.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontFamily: 'monospace', color: C.text)),
              ),
              if (e.scenario != MockScenario.normal)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(mockScenarioLabel(e.scenario), style: TextStyle(fontSize: 11, color: C.warnText)),
                ),
              Text('${e.durationMs} ms', style: TextStyle(fontSize: 11.5, color: C.muted)),
              const SizedBox(width: 8),
              Text('${e.status}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _statusColor(e.status))),
            ],
          ),
          for (final i in e.issues)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 60),
              child: Text(i.message, style: TextStyle(fontSize: 12, color: i.fatal ? C.dangerText : C.warnText)),
            ),
          if (e.unknown)
            Padding(
              padding: const EdgeInsets.only(left: 52),
              child: Row(
                children: [
                  Flexible(child: Text(tr('ไม่มี endpoint นี้ใน API'), style: TextStyle(fontSize: 12, color: C.warnText))),
                  TextButton(key: const ValueKey('mock-add-endpoint'), onPressed: onAdd, child: Text(tr('เพิ่มเข้า API'))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
