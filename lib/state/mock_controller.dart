import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/l10n/l10n.dart';
import '../core/mock/mock_engine.dart';
import '../core/mock/mock_server.dart';
import '../core/models/api_model.dart';
import 'workspace_controller.dart';

/// ถือ Mock Server ที่รันอยู่ในเครื่อง + บันทึกคำขอ — สถานะรันไม่ถูกบันทึกในไฟล์ (ค่าตั้งอยู่ใน `meta.mock` ผ่าน [WorkspaceController])
///
/// หยุดเองเมื่อเอกสาร API ที่ใช้ถูกลบ/เปิดโปรเจกต์อื่น ; ปิดแอป = [dispose] หยุดเซิร์ฟเวอร์และปล่อยพอร์ต
class MockController extends ChangeNotifier {
  MockController(this._w) {
    _w.addListener(_onWorkspace);
  }

  final WorkspaceController _w;
  MockServer? _server;
  MockEngine? _engine;
  bool _busy = false;
  bool _disposed = false;
  String? _error;
  String? _runningDocId;

  /// ปริมาณบันทึกสูงสุดที่เก็บ (เก่าสุดถูกทิ้ง)
  static const maxLog = 300;
  final List<MockLogEntry> _log = [];

  /// บันทึกคำขอ เรียงจากเก่าไปใหม่
  List<MockLogEntry> get log => List.unmodifiable(_log);

  // ตัวนับต่อ endpoint (แยกจากบันทึก จึงไม่ลดเมื่อบันทึกเกิน [maxLog]) ; ล้างพร้อม [clearLog]
  final Map<String, int> _hits = {};
  final Map<String, int> _lastStatus = {};

  /// จำนวนคำขอที่ตรงกับ endpoint [id] นับตั้งแต่ล้างบันทึกครั้งล่าสุด
  int hitsOf(String id) => _hits[id] ?? 0;

  /// สถานะที่ตอบล่าสุดของ endpoint [id] (null = ยังไม่เคยถูกเรียก)
  int? lastStatusOf(String id) => _lastStatus[id];

  bool get running => _server?.running ?? false;
  bool get busy => _busy;

  /// พอร์ตที่ฟังอยู่จริง (null = ไม่ได้รัน)
  int? get port => _server?.port;

  /// ที่อยู่ที่ใช้เรียก (null = ไม่ได้รัน)
  String? get url => port == null ? null : 'http://127.0.0.1:$port';

  /// ข้อความผิดพลาดล่าสุดตอนเริ่ม (เช่น พอร์ตถูกใช้อยู่) — หายเมื่อเริ่มสำเร็จ/เริ่มใหม่
  String? get error => _error;

  ApiDocument? get api => _w.mockApiDocument?.api;

  /// เริ่มฟังตามพอร์ตในค่าตั้ง ; คืน true เมื่อรันอยู่
  Future<bool> start() async {
    if (running) return true;
    if (_busy) return false;
    final doc = _w.mockApiDocument;
    if (doc == null) {
      _error = tr('ยังไม่มีเอกสาร API ในโปรเจกต์');
      notifyListeners();
      return false;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    final docId = doc.id;
    final engine = MockEngine(
      api: () => _w.workspace.documentById(docId)?.api,
      workspace: () => _w.workspace,
      settings: () => _w.mockSettings,
    );
    final server = MockServer(engine, onEntry: _add);
    try {
      await server.start(_w.mockSettings.port);
      _engine = engine;
      _server = server;
      _runningDocId = docId;
      if (_disposed) await stop();
      return running;
    } on SocketException catch (e) {
      _error = tr('เปิดพอร์ต {0} ไม่ได้ — {1}', [_w.mockSettings.port, e.osError?.message ?? e.message]);
      return false;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// หยุดและปล่อยพอร์ต
  Future<void> stop() async {
    final s = _server;
    _server = null;
    _engine = null;
    _runningDocId = null;
    await s?.stop();
    if (!_disposed) notifyListeners();
  }

  /// จำนวนครั้งที่ข้อมูลที่จำไว้เปลี่ยนไปจาก seed (0 = ยังเป็นค่าเริ่มต้น หรือไม่ได้รัน)
  int get changes => _engine?.changes ?? 0;

  /// ล้างข้อมูลที่จำไว้ (POST/PUT/DELETE) กลับไปเริ่มจาก seed ; คืนจำนวนครั้งที่เปลี่ยนที่ถูกล้าง
  int resetData() {
    final n = changes;
    _engine?.reset();
    notifyListeners();
    return n;
  }

  void clearLog() {
    _log.clear();
    _hits.clear();
    _lastStatus.clear();
    notifyListeners();
  }

  /// เพิ่ม endpoint ที่คำขอ [e] เรียกแต่ยังไม่มีใน API (เฉพาะรายการที่ `unknown`) — คืน endpoint ใหม่ ; ไม่ได้ = null
  ApiEndpoint? addEndpointFromLog(MockLogEntry e) {
    final doc = _w.mockApiDocument;
    if (doc == null || !e.unknown) return null;
    final c = _w.apiController(doc.id);
    final method = ApiMethod.values.asNameMap()[e.method.toLowerCase()];
    if (c == null || method == null) return null;
    final q = e.path.indexOf('?');
    final made = c.addEndpoint(method: method, path: q < 0 ? e.path : e.path.substring(0, q));
    notifyListeners();
    return made;
  }

  void _add(MockLogEntry e) {
    _log.add(e);
    final id = e.endpointId;
    if (id != null) {
      _hits[id] = (_hits[id] ?? 0) + 1;
      _lastStatus[id] = e.status;
    }
    if (_log.length > maxLog) _log.removeRange(0, _log.length - maxLog);
    if (!_disposed) notifyListeners();
  }

  void _onWorkspace() {
    if (!running) return;
    final doc = _w.workspace.documentById(_runningDocId ?? '');
    if (doc?.api == null) unawaited(stop());
  }

  @override
  void dispose() {
    _disposed = true;
    _w.removeListener(_onWorkspace);
    final s = _server;
    _server = null;
    if (s != null) unawaited(s.stop());
    super.dispose();
  }
}
