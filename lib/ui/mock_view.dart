import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/export/mock_requests_export.dart';
import '../core/l10n/l10n.dart';
import '../core/mock/mock_engine.dart';
import '../core/mock/mock_settings.dart';
import '../core/models/api_model.dart';
import '../core/models/workspace.dart' show ProjectDocument;
import '../state/mock_controller.dart';
import '../state/workspace_controller.dart';
import 'api/api_view.dart' show ApiMethodChip;
import 'file_actions.dart';
import 'theme.dart';
import 'widgets.dart' show Dropdown;

String mockScenarioLabel(MockScenario s) => switch (s) {
      MockScenario.normal => tr('ปกติ'),
      MockScenario.conflict => tr('409 ซ้ำ'),
      MockScenario.unauthorized => tr('401 ไม่ได้ล็อกอิน'),
      MockScenario.serverError => tr('500 ผิดพลาด'),
      MockScenario.random => tr('สุ่ม'),
    };

/// ป้ายสั้นของปุ่มกลุ่มสถานการณ์ (ชื่อเต็มอยู่ใน tooltip)
String _chipLabel(MockScenario s) => switch (s) {
      MockScenario.normal => tr('ปกติ'),
      MockScenario.conflict => '409',
      MockScenario.unauthorized => '401',
      MockScenario.serverError => '500',
      MockScenario.random => tr('สุ่ม'),
    };

Color _statusColor(int s) => s >= 500 ? C.danger : (s >= 400 ? C.warnText : C.primaryDark);

String _clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

/// body สำหรับแสดง : JSON ที่อ่านได้ = จัดย่อหน้า ; ไม่ใช่ = ตามเดิม ; ว่าง = "(ไม่มี body)"
String mockBodyText(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return tr('(ไม่มี body)');
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(t));
  } catch (_) {
    return raw; // ไม่ใช่ JSON (หรือถูกตัดกลางคัน)
  }
}

/// ความกว้างขั้นต่ำของตาราง endpoint (แคบกว่านี้เลื่อนแนวนอน)
const double _kTableMinWidth = 1012;

/// หน้า Mock Server (แบบ B ของ `design/mock-server`): แถบเซิร์ฟเวอร์ · ตาราง endpoint (สถานการณ์/หน่วง/เรียกแล้ว/ล่าสุด) ·
/// ลิ้นชักบันทึกคำขอ + รายละเอียด request/response ; แสดงแทนแคนวาสขณะ [WorkspaceController.page] == [WorkspacePage.mock]
class MockView extends StatefulWidget {
  const MockView({super.key});

  @override
  State<MockView> createState() => _MockViewState();
}

class _MockViewState extends State<MockView> {
  late final TextEditingController _port;
  bool _drawer = true;
  MockLogEntry? _selected;

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

  /// ข้อความใหม่แทนที่ข้อความเดิมทันที (ไม่ซ้อนคิวรอข้อความเก่าหาย)
  void _toast(String m) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  /// พอร์ตที่พิมพ์ (ผิดรูป = ค่าเดิมในไฟล์)
  int _typedPort(WorkspaceController w) {
    final n = int.tryParse(_port.text.trim());
    return n != null && n >= 0 && n <= 65535 ? n : w.mockSettings.port;
  }

  /// ส่งออกชุดคำขอ (Postman / curl) ของ API ที่ Mock ใช้ ; URL ฐาน = ที่อยู่ของ Mock (พอร์ตตามค่าตั้ง)
  Future<void> _exportRequests(WorkspaceController w, MockController m, ApiDocument api, String kind) async {
    final base = m.url ?? 'http://127.0.0.1:${_typedPort(w)}';
    final title = tr('ส่งออกชุดคำขอ');
    if (kind == 'postman') {
      await FileActions.saveText(context, exportPostmanCollection(api, baseUrl: base), 'mock-requests.postman_collection.json', title);
    } else {
      await FileActions.saveText(context, exportCurlScript(api, baseUrl: base), 'mock-requests.sh', title);
    }
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

    final entries = m.log.reversed.toList();
    // รายการที่เลือกหายไป (ล้างบันทึก/เกินจำนวน) หรือยังไม่เลือก = ใหม่สุด
    final selected = entries.contains(_selected) ? _selected : (entries.isEmpty ? null : entries.first);

    return Container(
      key: const ValueKey('mock-view'),
      color: C.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _serverBar(context, w, m, doc!, api),
          Expanded(child: _endpointTable(w, m, api, settings)),
          _logDrawer(context, w, m, entries, selected),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- แถบเซิร์ฟเวอร์

  Widget _serverBar(BuildContext context, WorkspaceController w, MockController m, ProjectDocument doc, ApiDocument api) {
    final settings = w.mockSettings;
    final apiDocs = [for (final d in w.workspace.documents) if (d.api != null) d];
    final on = m.running;
    return Material(
      color: C.surface,
      shape: Border(bottom: BorderSide(color: C.border)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              key: const ValueKey('mock-status'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: on ? C.primaryTint : C.surfaceHi,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: on ? C.primary : C.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: on ? C.primary : C.muted, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(on ? tr('กำลังทำงาน') : tr('หยุดอยู่'),
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? C.primaryDark : C.muted)),
              ]),
            ),
            if (on) ...[
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
            SizedBox(
              width: 110,
              child: TextField(
                key: const ValueKey('mock-port'),
                controller: _port,
                enabled: !on,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                decoration: InputDecoration(isDense: true, labelText: tr('พอร์ต')),
              ),
            ),
            if (apiDocs.length > 1)
              DropdownButton<String>(
                key: const ValueKey('mock-api-doc'),
                value: doc.id,
                isDense: true,
                onChanged: on ? null : (v) => w.setMockSettings(settings.copyWith(apiDocId: v)),
                items: [for (final d in apiDocs) DropdownMenuItem(value: d.id, child: Text(d.name, style: const TextStyle(fontSize: 13)))],
              )
            else
              Text(tr('จาก API — {0} · {1} endpoint', [doc.name, api.endpoints.length]), key: const ValueKey('mock-source'), style: TextStyle(fontSize: 12.5, color: C.muted)),
            if (m.error != null) Text(m.error!, key: const ValueKey('mock-error'), style: TextStyle(fontSize: 12.5, color: C.dangerText)),
            // จำนวนครั้งที่ข้อมูลเปลี่ยนจาก seed (เห็นว่ารีเซ็ตแล้วมีอะไรเปลี่ยน)
            if (on && m.changes > 0)
              Container(
                key: const ValueKey('mock-changes'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: C.warnBg, borderRadius: BorderRadius.circular(999)),
                child: Text(tr('ข้อมูลเปลี่ยนจาก seed {0} ครั้ง', [m.changes]), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.warnText)),
              ),
            Tooltip(
              message: tr('ตารางที่ไม่มีข้อมูลตั้งต้น (seed) ให้สร้างแถวตัวอย่างให้ — ไม่งั้น GET ได้รายการว่าง ; มีผลกับตารางที่ยังไม่ถูกเรียกหลังเริ่ม/รีเซ็ตข้อมูล'),
              child: InkWell(
                key: const ValueKey('mock-autosample'),
                borderRadius: BorderRadius.circular(6),
                onTap: () => w.setMockSettings(settings.copyWith(autoSample: !settings.autoSample)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(settings.autoSample ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 18, color: settings.autoSample ? C.primary : C.muted),
                    const SizedBox(width: 4),
                    Text(tr('สร้างข้อมูลตัวอย่างให้ตารางที่ไม่มี seed'), style: const TextStyle(fontSize: 12.5)),
                  ]),
                ),
              ),
            ),
            PopupMenuButton<String>(
              key: const ValueKey('mock-export'),
              tooltip: tr('ส่งออกชุดคำขอของ API นี้ (ไว้ยิงทดสอบ)'),
              onSelected: (v) => _exportRequests(w, m, api, v),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'postman', key: const ValueKey('mock-export-postman'), child: Text(tr('Postman Collection (.json)'))),
                PopupMenuItem(value: 'curl', key: const ValueKey('mock-export-curl'), child: Text(tr('สคริปต์ curl (.sh)'))),
              ],
              child: IgnorePointer(
                child: OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.ios_share_rounded, size: 16), label: Text(tr('ส่งออกคำขอ'))),
              ),
            ),
            Tooltip(
              message: on
                  ? tr('ล้างข้อมูลที่ POST/PUT/PATCH/DELETE เข้ามา แล้วเริ่มจาก seed ของตาราง ER ใหม่ (ใช้กับ endpoint ที่ผูกตาราง)')
                  : tr('เริ่มเซิร์ฟเวอร์ก่อน (ข้อมูลที่จำไว้จะล้างเองเมื่อหยุด)'),
              child: OutlinedButton(
                key: const ValueKey('mock-reset'),
                onPressed: on
                    ? () {
                        final n = m.resetData();
                        _toast(n > 0 ? tr('รีเซ็ตข้อมูลแล้ว — ล้างการเปลี่ยน {0} ครั้ง กลับไปเริ่มจาก seed ของ ER', [n]) : tr('ข้อมูลยังเป็นค่าเริ่มต้นจาก seed ของ ER อยู่แล้ว — ไม่มีอะไรให้รีเซ็ต'));
                      }
                    : null,
                child: Text(tr('รีเซ็ตข้อมูล')),
              ),
            ),
            FilledButton.icon(
              key: const ValueKey('mock-toggle'),
              style: on ? FilledButton.styleFrom(backgroundColor: C.danger) : null,
              onPressed: m.busy ? null : () => _toggle(w, m),
              icon: Icon(on ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
              label: Text(on ? tr('หยุด') : tr('เริ่ม')),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- ตาราง endpoint

  Widget _endpointTable(WorkspaceController w, MockController m, ApiDocument api, MockSettings settings) {
    final head = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: C.muted);
    Widget cell(double? width, Widget child, {int flex = 0}) => width != null
        ? SizedBox(width: width, child: child)
        : Expanded(flex: flex == 0 ? 1 : flex, child: child);
    Widget rowOf(List<Widget> children) => Row(children: children);

    return Container(
      color: C.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              Text(tr('Endpoint · {0}', [api.endpoints.length]), style: TextStyle(fontWeight: FontWeight.w700, color: C.text)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tr('สุ่ม = ปกติ 70% · 500 20% · 409 10% ; หน่วงใช้ได้ทุกสถานการณ์'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: C.muted),
                ),
              ),
            ]),
          ),
          Expanded(
            child: api.endpoints.isEmpty
                ? Center(child: Text(tr('API นี้ยังไม่มี endpoint'), style: TextStyle(color: C.muted)))
                : LayoutBuilder(builder: (context, box) {
                    final width = box.maxWidth < _kTableMinWidth ? _kTableMinWidth : box.maxWidth;
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: width,
                        height: box.maxHeight,
                        child: Column(children: [
                          Container(
                            color: C.surfaceHi,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                            child: rowOf([
                              cell(64, Text('', style: head)),
                              cell(null, Text('Endpoint', style: head), flex: 3),
                              cell(372, Text(tr('สถานการณ์ที่ตอบ'), style: head)),
                              cell(112, Text(tr('ลำดับ'), style: head)),
                              cell(92, Text(tr('หน่วง (ms)'), style: head)),
                              cell(76, Text(tr('เรียกแล้ว'), style: head)),
                              cell(60, Text(tr('ล่าสุด'), style: head)),
                            ]),
                          ),
                          Expanded(
                            child: ListView(children: [
                              for (final e in api.endpoints)
                                _EndpointRow(
                                  key: ValueKey('mock-ep-${e.id}'),
                                  endpoint: e,
                                  setting: settings.of(e.id),
                                  hits: m.hitsOf(e.id),
                                  last: m.lastStatusOf(e.id),
                                  seqNext: m.sequenceNextOf(e.id),
                                  running: m.running,
                                  onChanged: (s) => w.setMockSettings(settings.withEndpoint(e.id, s)),
                                  onDelay: (s) => w.setMockSettings(settings.withEndpoint(e.id, s), coalesce: 'delay-${e.id}'),
                                ),
                            ]),
                          ),
                        ]),
                      ),
                    );
                  }),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- ลิ้นชักบันทึกคำขอ

  Widget _logDrawer(BuildContext context, WorkspaceController w, MockController m, List<MockLogEntry> entries, MockLogEntry? selected) {
    final list = entries.isEmpty
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
              selected: identical(entries[i], selected),
              onSelect: () => setState(() => _selected = entries[i]),
              onAdd: () {
                final made = m.addEndpointFromLog(entries[i]);
                if (made != null) _toast(tr('เพิ่ม endpoint {0} แล้ว', [made.title]));
              },
            ),
          );
    return Container(
      decoration: BoxDecoration(color: C.bg, border: Border(top: BorderSide(color: C.border))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Material(
          color: C.surfaceHi,
          child: InkWell(
            key: const ValueKey('mock-drawer-toggle'),
            onTap: () => setState(() => _drawer = !_drawer),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(children: [
                Expanded(
                  child: Text(tr('บันทึกคำขอ · {0}', [entries.length]), key: const ValueKey('mock-log-count'), style: TextStyle(fontWeight: FontWeight.w700, color: C.text)),
                ),
                TextButton(key: const ValueKey('mock-clear-log'), onPressed: entries.isEmpty ? null : m.clearLog, child: Text(tr('ล้างบันทึก'))),
                Icon(_drawer ? Icons.expand_more_rounded : Icons.expand_less_rounded, size: 20, color: C.muted),
              ]),
            ),
          ),
        ),
        if (_drawer)
          SizedBox(
            height: 280,
            child: LayoutBuilder(builder: (context, box) {
              final detail = selected == null ? const SizedBox.shrink() : _LogDetail(key: const ValueKey('mock-detail'), entry: selected);
              if (box.maxWidth < 800) return list;
              return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: list),
                Container(width: 1, color: C.border),
                Expanded(child: detail),
              ]);
            }),
          ),
      ]),
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({
    super.key,
    required this.endpoint,
    required this.setting,
    required this.hits,
    required this.last,
    required this.seqNext,
    required this.running,
    required this.onChanged,
    required this.onDelay,
  });
  final ApiEndpoint endpoint;
  final MockEndpointSetting setting;
  final int hits;
  final int? last;

  /// ขั้นถัดไปของลำดับ (เมื่อรันอยู่และตั้งลำดับ)
  final int? seqNext;
  final bool running;
  final ValueChanged<MockEndpointSetting> onChanged;

  /// พิมพ์ค่าหน่วง : ทุกตัวอักษรเรียกครั้งหนึ่ง จึงให้ประวัติรวมเป็นขั้นเดียว
  final ValueChanged<MockEndpointSetting> onDelay;

  Future<void> _editSequence(BuildContext context) async {
    final res = await showDialog<List<MockScenario>>(
      context: context,
      builder: (_) => _SequenceDialog(endpoint: endpoint, initial: setting.sequence, fallback: setting.scenario),
    );
    if (res != null) onChanged(setting.copyWith(sequence: res));
  }

  @override
  Widget build(BuildContext context) {
    final e = endpoint;
    final seq = setting.sequence.isNotEmpty;
    final warn = setting.scenario != MockScenario.normal || seq;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: C.borderSoft))),
      child: Row(children: [
        SizedBox(width: 64, child: Align(alignment: Alignment.centerLeft, child: ApiMethodChip(e.method))),
        Expanded(
          flex: 3,
          child: Text(e.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontFamily: 'monospace', color: C.text)),
        ),
        SizedBox(
          width: 372,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              key: ValueKey('mock-scenario-${e.id}'),
              decoration: BoxDecoration(border: Border.all(color: C.inputBorder), borderRadius: BorderRadius.circular(7)),
              clipBehavior: Clip.antiAlias,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final (i, s) in MockScenario.values.indexed)
                  Tooltip(
                    message: mockScenarioLabel(s),
                    child: InkWell(
                      key: ValueKey('mock-scenario-${e.id}-${s.name}'),
                      onTap: () => onChanged(setting.copyWith(scenario: s, sequence: const [])),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: !seq && setting.scenario == s ? (s == MockScenario.normal ? C.primaryTint : (s == MockScenario.serverError ? C.dangerBg : C.warnBg)) : null,
                          border: Border(left: BorderSide(color: i == 0 ? Colors.transparent : C.inputBorder)),
                        ),
                        child: Text(
                          _chipLabel(s),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: !seq && setting.scenario == s ? FontWeight.w700 : FontWeight.w400,
                            color: !seq && setting.scenario == s
                                ? (s == MockScenario.normal ? C.primaryDark : (s == MockScenario.serverError ? C.dangerText : C.warnText))
                                : C.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        SizedBox(
          width: 112,
          child: Align(
            alignment: Alignment.centerLeft,
            child: seq
                ? InkWell(
                    key: ValueKey('mock-seq-${e.id}'),
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _editSequence(context),
                    child: Tooltip(
                      message: setting.sequence.map(mockScenarioLabel).join(' → '),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: C.warnBg, borderRadius: BorderRadius.circular(999)),
                        child: Text(
                          seqNext == null ? tr('ลำดับ {0} ขั้น', [setting.sequence.length]) : tr('ลำดับ {0}/{1}', [seqNext, setting.sequence.length]),
                          key: ValueKey('mock-seq-label-${e.id}'),
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: C.warnText),
                        ),
                      ),
                    ),
                  )
                : TextButton(
                    key: ValueKey('mock-seq-${e.id}'),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                    onPressed: () => _editSequence(context),
                    child: Text(tr('ลำดับ…'), style: TextStyle(fontSize: 12, color: C.muted)),
                  ),
          ),
        ),
        SizedBox(
          width: 92,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 72,
              child: TextFormField(
                key: ValueKey('mock-delay-${e.id}'),
                initialValue: setting.delayMs == 0 ? '' : '${setting.delayMs}',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                style: TextStyle(fontSize: 12.5, fontFamily: 'monospace', color: warn || setting.delayMs > 0 ? C.warnText : C.text),
                decoration: const InputDecoration(isDense: true, hintText: '0'),
                onChanged: (v) => onDelay(setting.copyWith(delayMs: int.tryParse(v) ?? 0)),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 76,
          child: Text(hits == 0 ? '—' : '$hits', key: ValueKey('mock-hits-${e.id}'), style: TextStyle(fontSize: 12.5, fontFamily: 'monospace', color: C.muted)),
        ),
        SizedBox(
          width: 60,
          child: last == null
              ? Text('—', key: ValueKey('mock-last-${e.id}'), style: TextStyle(color: C.muted))
              : Text('$last', key: ValueKey('mock-last-${e.id}'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, fontFamily: 'monospace', color: _statusColor(last!))),
        ),
      ]),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({super.key, required this.entry, required this.selected, required this.onSelect, required this.onAdd});
  final MockLogEntry entry;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return InkWell(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? C.primaryTint : null,
          border: Border(bottom: BorderSide(color: C.borderSoft)),
        ),
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
      ),
    );
  }
}

/// รายละเอียดคำขอที่เลือก : สถานะ เวลา สถานการณ์ ข้อผิดพลาดของสัญญา และ body ของคำขอ/คำตอบ
class _LogDetail extends StatelessWidget {
  const _LogDetail({super.key, required this.entry});
  final MockLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    Widget block(String label, String body, {Key? key}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.muted, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: C.surfaceHi, borderRadius: BorderRadius.circular(8), border: Border.all(color: C.borderSoft)),
            child: SelectableText(body, key: key, style: TextStyle(fontSize: 12, fontFamily: 'monospace', height: 1.5, color: C.text)),
          ),
        ]);
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(children: [
          Text(tr('รายละเอียดคำขอ'), style: TextStyle(fontWeight: FontWeight.w700, color: C.text)),
          const Spacer(),
          Text('${e.method} · ${e.durationMs} ms · ', style: TextStyle(fontSize: 12, color: C.muted)),
          Text('${e.status}', key: const ValueKey('mock-detail-status'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _statusColor(e.status))),
        ]),
        if (e.seqStep != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(tr('ลำดับที่ {0}/{1}', [e.seqStep, e.seqTotal]), key: const ValueKey('mock-detail-seq'), style: TextStyle(fontSize: 12, color: C.warnText)),
          ),
        if (e.scenario != MockScenario.normal)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(tr('สถานการณ์ {0}'
, [mockScenarioLabel(e.scenario)]), style: TextStyle(fontSize: 12, color: C.warnText)),
          ),
        const SizedBox(height: 10),
        block('REQUEST', mockBodyText(e.requestBody), key: const ValueKey('mock-detail-request')),
        const SizedBox(height: 10),
        block('RESPONSE', mockBodyText(e.responseBody), key: const ValueKey('mock-detail-response')),
      ],
    );
  }
}

/// ตัวจัดลำดับการตอบของ endpoint หนึ่ง (เพิ่ม/ลบ/ลากเรียง สูงสุด [kMockMaxSequence] ขั้น) ; ปิดด้วยรายการใหม่ ([] = เลิกใช้ลำดับ) หรือ null = ยกเลิก
class _SequenceDialog extends StatefulWidget {
  const _SequenceDialog({required this.endpoint, required this.initial, required this.fallback});
  final ApiEndpoint endpoint;
  final List<MockScenario> initial;

  /// ขั้นที่เพิ่มใหม่ครั้งแรก ถ้ายังไม่มีลำดับ (= สถานการณ์เดิมของ endpoint)
  final MockScenario fallback;

  @override
  State<_SequenceDialog> createState() => _SequenceDialogState();
}

class _SequenceDialogState extends State<_SequenceDialog> {
  late final List<MockScenario> _steps = [...widget.initial];

  /// ชุดสำเร็จรูป : ลองกลไก retry ได้ทันที
  static const _presets = <(String, List<MockScenario>)>[
    ('200 → 500 → 200', [MockScenario.normal, MockScenario.serverError, MockScenario.normal]),
    ('500 → 500 → 200', [MockScenario.serverError, MockScenario.serverError, MockScenario.normal]),
    ('200 → 409', [MockScenario.normal, MockScenario.conflict]),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('ตอบเป็นลำดับ — {0}', [widget.endpoint.title])),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            tr('คำขอที่ 1 ใช้ขั้นแรก คำขอที่ 2 ใช้ขั้นสอง … ครบแล้ววนกลับ ; รีเซ็ตข้อมูลหรือหยุดเซิร์ฟเวอร์ = เริ่มขั้นแรกใหม่'),
            style: TextStyle(fontSize: 12.5, color: C.muted, height: 1.4),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final (i, p) in _presets.indexed)
              ActionChip(
                key: ValueKey('mock-seq-preset-$i'),
                label: Text(p.$1, style: const TextStyle(fontSize: 12)),
                onPressed: () => setState(() => _steps..clear()..addAll(p.$2)),
              ),
          ]),
          const SizedBox(height: 8),
          Flexible(
            child: ReorderableListView(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) => setState(() => _steps.insert(to, _steps.removeAt(from))),
              children: [
                for (final (i, s) in _steps.indexed)
                  Row(key: ValueKey('mock-seq-step-$i-${s.name}'), children: [
                    ReorderableDragStartListener(index: i, child: Icon(Icons.drag_indicator_rounded, size: 18, color: C.muted)),
                    SizedBox(width: 26, child: Text('${i + 1}', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: C.muted))),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Dropdown<MockScenario>(
                          key: ValueKey('mock-seq-pick-$i'),
                          value: s,
                          items: MockScenario.values,
                          labelOf: mockScenarioLabel,
                          onChanged: (v) => setState(() => _steps[i] = v),
                        ),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('mock-seq-del-$i'),
                      tooltip: tr('ลบขั้นนี้'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _steps.removeAt(i)),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ]),
              ],
            ),
          ),
          TextButton.icon(
            key: const ValueKey('mock-seq-add'),
            onPressed: _steps.length >= kMockMaxSequence ? null : () => setState(() => _steps.add(_steps.isEmpty ? widget.fallback : _steps.last)),
            icon: const Icon(Icons.add, size: 16),
            label: Text(tr('เพิ่มขั้น ({0}/{1})', [_steps.length, kMockMaxSequence])),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
        if (widget.initial.isNotEmpty)
          TextButton(key: const ValueKey('mock-seq-clear'), onPressed: () => Navigator.pop(context, const <MockScenario>[]), child: Text(tr('เลิกใช้ลำดับ'))),
        FilledButton(key: const ValueKey('mock-seq-ok'), onPressed: () => Navigator.pop(context, [..._steps]), child: Text(tr('บันทึก'))),
      ],
    );
  }
}
