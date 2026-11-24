import 'dart:convert';
import 'dart:math';

import '../export/openapi_export.dart' show httpStatusText;
import '../export/seed_data.dart' show seedNormalized;
import '../l10n/l10n.dart';
import '../models/api_model.dart';
import '../models/column_model.dart';
import '../models/enums.dart';
import '../models/table_model.dart';
import '../models/workspace.dart';
import 'mock_settings.dart';

/// คำขอที่เซิร์ฟเวอร์จำลองรับ (ไม่ผูกกับ dart:io เพื่อให้เทสต์ได้โดยไม่ต้องเปิดพอร์ต)
class MockRequest {
  MockRequest({required String method, required this.path, this.query = const {}, Map<String, String>? headers, this.body = ''})
      : method = method.toUpperCase(),
        headers = {for (final e in (headers ?? const <String, String>{}).entries) e.key.toLowerCase(): e.value};

  final String method;

  /// path ไม่รวม query
  final String path;
  final Map<String, String> query;

  /// ชื่อ header เป็นตัวพิมพ์เล็ก
  final Map<String, String> headers;
  final String body;
}

class MockReply {
  const MockReply(this.status, {this.body = '', this.headers = const {}, this.delay = Duration.zero});
  final int status;

  /// ข้อความ JSON (ว่าง = ไม่มี body)
  final String body;
  final Map<String, String> headers;

  /// หน่วงก่อนส่ง (ตามที่ตั้งต่อ endpoint)
  final Duration delay;
}

/// ปัญหาที่พบเมื่อตรวจ request กับสัญญา API
class MockIssue {
  const MockIssue(this.code, this.field, [this.expected = '', this.actual = '']);

  /// `invalid_json` · `not_object` · `required` · `type` · `unknown_field`
  final String code;
  final String field;
  final String expected;
  final String actual;

  /// ข้อความสำหรับผู้ใช้ (ตามภาษาของโปรแกรม)
  String get message => switch (code) {
        'invalid_json' => tr('body ไม่ใช่ JSON ที่ถูกต้อง'),
        'not_object' => tr('body ต้องเป็น JSON object'),
        'required' => tr('ขาดฟิลด์บังคับ {0}', [field]),
        'type' => tr('ฟิลด์ {0} ต้องเป็น {1} แต่ได้ {2}', [field, expected, actual]),
        'unknown_field' => tr('ฟิลด์ {0} ไม่มีในสัญญา API', [field]),
        _ => code,
      };

  /// ฟิลด์ที่ไม่มีในสัญญาเป็นแค่คำเตือน (ไม่ปฏิเสธคำขอ)
  bool get fatal => code != 'unknown_field';

  Map<String, dynamic> toJson() => {
        'code': code,
        if (field.isNotEmpty) 'field': field,
        if (expected.isNotEmpty) 'expected': expected,
        if (actual.isNotEmpty) 'actual': actual,
      };
}

/// ความยาวสูงสุดของ body ที่เก็บในบันทึกคำขอ (เกินแล้วตัดและต่อท้าย …)
const int kMockBodyClip = 4000;

/// บันทึกคำขอหนึ่งครั้ง
class MockLogEntry {
  MockLogEntry({
    required this.time,
    required this.method,
    required this.path,
    required this.status,
    this.endpointId,
    this.endpointTitle,
    this.scenario = MockScenario.normal,
    this.issues = const [],
    this.unknown = false,
    this.durationMs = 0,
  });

  final DateTime time;
  final String method;

  /// path พร้อม query
  final String path;
  final int status;
  final String? endpointId;
  final String? endpointTitle;

  /// สถานการณ์ที่ใช้จริง (กรณี random = ผลที่สุ่มได้)
  final MockScenario scenario;
  final List<MockIssue> issues;

  /// path/method นี้ไม่มีใน API (เสนอให้เพิ่ม endpoint)
  final bool unknown;

  /// เวลาตอบรวมการหน่วง (เซิร์ฟเวอร์เป็นคนใส่)
  int durationMs;

  /// body ของคำขอ/คำตอบ (ข้อความ ; ตัดที่ [kMockBodyClip] ตัวอักษร ; ว่าง = ไม่มี) — ใช้แสดงรายละเอียดในหน้า Mock Server
  String requestBody = '', responseBody = '';

  bool get hasIssue => issues.any((i) => i.fatal);
}

class MockResult {
  const MockResult(this.reply, this.entry);
  final MockReply reply;
  final MockLogEntry entry;
}

/// ตัวตอบคำขอของ Mock Server — ล้วน ๆ ไม่แตะเครือข่าย
///
/// endpoint ที่ผูกตาราง ER ทำงานแบบมีสถานะ: ข้อมูลเริ่มจาก seed ของตาราง, POST เพิ่มแถว, PUT/PATCH แก้, DELETE ลบ
/// (จำอยู่ในหน่วยความจำจนกว่าจะ [reset]) ; endpoint ที่ไม่ผูกตาราง ตอบตามตัวอย่างใน response ที่ประกาศไว้
class MockEngine {
  MockEngine({required this.api, required this.workspace, required this.settings, Random? random, DateTime Function()? clock})
      : _rnd = random ?? Random(),
        _now = clock ?? DateTime.now;

  /// อ่านสด ๆ ทุกคำขอ — แก้ API หรือสถานการณ์ระหว่างรันแล้วมีผลทันที
  final ApiDocument? Function() api;
  final Workspace Function() workspace;
  final MockSettings Function() settings;
  final Random _rnd;
  final DateTime Function() _now;

  /// "docId/tableId" -> แถว
  final Map<String, List<Map<String, Object?>>> _rows = {};

  /// ตัวนับ AUTO INCREMENT ต่อตาราง
  final Map<String, int> _counters = {};

  /// จำนวนครั้งที่ข้อมูลที่จำไว้ถูกเปลี่ยน (POST เพิ่ม · PUT/PATCH แก้ · DELETE ลบ สำเร็จ) นับตั้งแต่เริ่ม/รีเซ็ตครั้งล่าสุด
  int changes = 0;

  /// ล้างข้อมูลที่จำไว้ (กลับไปเริ่มจาก seed)
  void reset() {
    _rows.clear();
    _counters.clear();
    changes = 0;
  }

  /// แถวที่จำอยู่ของตารางที่ endpoint นี้ผูก (null = ไม่ผูก/ไม่มีตาราง)
  List<Map<String, Object?>>? rowsOf(ApiEndpoint e) {
    final t = _tableOf(e);
    return t == null ? null : _store(e.table!, t);
  }

  /// ตอบคำขอ และเก็บ body ของคำขอ/คำตอบลงบันทึก (ตัดตาม [kMockBodyClip])
  MockResult handle(MockRequest req) {
    final r = _handle(req);
    r.entry
      ..requestBody = _clip(req.body)
      ..responseBody = _clip(r.reply.body);
    return r;
  }

  static String _clip(String s) => s.length <= kMockBodyClip ? s : '${s.substring(0, kMockBodyClip)}…';

  MockResult _handle(MockRequest req) {
    final doc = api();
    final fullPath = req.query.isEmpty ? req.path : '${req.path}?${Uri(queryParameters: req.query).query}';
    MockLogEntry entry0({int status = 0, ApiEndpoint? e, MockScenario s = MockScenario.normal, List<MockIssue> issues = const [], bool unknown = false}) =>
        MockLogEntry(
          time: _now(),
          method: req.method,
          path: fullPath,
          status: status,
          endpointId: e?.id,
          endpointTitle: e?.title,
          scenario: s,
          issues: issues,
          unknown: unknown,
        );

    if (doc == null) {
      return MockResult(_json(503, {'error': 'api_missing', 'message': 'The API document of this mock no longer exists'}), entry0(status: 503));
    }

    final path = _stripBase(_normalize(req.path), doc.baseUrl);
    final matches = <(ApiEndpoint, Map<String, String>)>[];
    for (final e in doc.endpoints) {
      final p = _match(e.path, path);
      if (p != null) matches.add((e, p));
    }
    if (matches.isEmpty) {
      return MockResult(
        _json(404, {'error': 'not_found', 'message': 'No endpoint ${req.method} ${req.path} in the API design'}),
        entry0(status: 404, unknown: true),
      );
    }
    final hit = matches.where((m) => m.$1.method.label == req.method).toList()..sort((a, b) => _literals(b.$1.path).compareTo(_literals(a.$1.path)));
    if (hit.isEmpty) {
      final allow = {for (final m in matches) m.$1.method.label}.toList()..sort();
      return MockResult(
        _json(405, {'error': 'method_not_allowed', 'allowed': allow}, headers: {'allow': allow.join(', ')}),
        entry0(status: 405, unknown: true),
      );
    }
    final (e, params) = hit.first;

    final cfg = settings().of(e.id);
    final delay = Duration(milliseconds: cfg.delayMs.clamp(0, kMockMaxDelayMs));
    var scenario = cfg.scenario;
    if (scenario == MockScenario.random) {
      final r = _rnd.nextDouble();
      scenario = r < 0.7 ? MockScenario.normal : (r < 0.9 ? MockScenario.serverError : MockScenario.conflict);
    }

    MockResult done(MockReply r, {List<MockIssue> issues = const []}) => MockResult(
          MockReply(r.status, body: r.body, headers: r.headers, delay: delay),
          entry0(status: r.status, e: e, s: scenario, issues: issues),
        );

    final forced = scenario.status;
    if (forced != null) return done(_declared(e, forced));

    if (e.auth && !_hasBearer(req)) return done(_declared(e, 401));

    // ตรวจ request กับสัญญา
    final issues = <MockIssue>[];
    Map<String, Object?>? body;
    if (e.method.hasBody) {
      final r = _readBody(e, req.body, issues);
      body = r;
      if (issues.any((i) => i.fatal)) {
        final has422 = e.responses.any((r) => r.status == 422);
        return done(_json(has422 ? 422 : 400, {'error': 'validation_failed', 'problems': [for (final i in issues.where((i) => i.fatal)) i.toJson()]}), issues: issues);
      }
    }
    return done(_serve(e, params, req, body), issues: issues);
  }

  // ---------- เส้นทาง ----------

  static String _normalize(String p) {
    var s = p.isEmpty ? '/' : p;
    if (!s.startsWith('/')) s = '/$s';
    while (s.length > 1 && s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// ตัว prefix จาก baseUrl (เช่น `https://x.com/v1` → `/v1`) ออกถ้าคำขอมีมาด้วย — ไม่มีก็ใช้ path ตรง ๆ
  static String _stripBase(String path, String baseUrl) {
    final b = baseUrl.trim();
    if (b.isEmpty) return path;
    final prefix = _normalize(Uri.tryParse(b)?.path ?? '');
    if (prefix == '/') return path;
    if (path == prefix) return '/';
    if (path.startsWith('$prefix/')) return path.substring(prefix.length);
    return path;
  }

  static int _literals(String p) => p.split('/').where((s) => s.isNotEmpty && !_isParam(s)).length;
  static bool _isParam(String seg) => seg.length > 2 && seg.startsWith('{') && seg.endsWith('}');

  /// path template ตรงกับ [actual] ไหม — คืนค่าพารามิเตอร์ (ชื่อ -> ค่า) ; ไม่ตรง = null
  static Map<String, String>? _match(String template, String actual) {
    final t = _normalize(template).split('/').where((s) => s.isNotEmpty).toList();
    final a = actual.split('/').where((s) => s.isNotEmpty).toList();
    if (t.length != a.length) return null;
    final params = <String, String>{};
    for (var i = 0; i < t.length; i++) {
      if (_isParam(t[i])) {
        params[t[i].substring(1, t[i].length - 1)] = Uri.decodeComponent(a[i]);
      } else if (t[i] != a[i]) {
        return null;
      }
    }
    return params;
  }

  static bool _hasBearer(MockRequest r) {
    final h = r.headers['authorization']?.trim() ?? '';
    return h.length > 7 && h.substring(0, 7).toLowerCase() == 'bearer ';
  }

  // ---------- ตรวจ request ----------

  Map<String, Object?>? _readBody(ApiEndpoint e, String raw, List<MockIssue> issues) {
    final fields = [for (final f in e.fields) if (f.name.trim().isNotEmpty) f];
    final text = raw.trim();
    Object? decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        if (fields.isNotEmpty) issues.add(const MockIssue('invalid_json', ''));
        return null;
      }
    }
    if (fields.isEmpty) return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    if (decoded != null && decoded is! Map) {
      issues.add(const MockIssue('not_object', ''));
      return null;
    }
    final map = decoded == null ? <String, Object?>{} : Map<String, Object?>.from(decoded as Map);
    final partial = e.method == ApiMethod.patch; // PATCH ส่งเฉพาะที่แก้ ไม่บังคับฟิลด์
    for (final f in fields) {
      final name = f.name.trim();
      final v = map[name];
      if (v == null) {
        if (f.required && !partial) issues.add(MockIssue('required', name));
        continue;
      }
      if (!_typeOk(f.type, v)) issues.add(MockIssue('type', name, f.type.name, _typeName(v)));
    }
    final known = {for (final f in fields) f.name.trim()};
    for (final k in map.keys) {
      if (!known.contains(k)) issues.add(MockIssue('unknown_field', k));
    }
    // ฟิลด์ที่ไม่อยู่ในสัญญาไม่ถูกนำไปใช้ (แค่เตือน)
    return {for (final e in map.entries) if (known.contains(e.key)) e.key: e.value};
  }

  static bool _typeOk(ApiType t, Object v) => switch (t) {
        ApiType.string => v is String,
        ApiType.integer => v is int || (v is double && v == v.truncateToDouble()),
        ApiType.number => v is num,
        ApiType.boolean => v is bool,
        ApiType.array => v is List,
        ApiType.object => v is Map,
      };

  static String _typeName(Object v) => switch (v) {
        String _ => 'string',
        int _ => 'integer',
        num _ => 'number',
        bool _ => 'boolean',
        List _ => 'array',
        Map _ => 'object',
        _ => 'unknown',
      };

  // ---------- ตอบ ----------

  static MockReply _json(int status, Object? body, {Map<String, String> headers = const {}}) =>
      MockReply(status, body: status == 204 ? '' : jsonEncode(body), headers: headers);

  /// ตอบด้วยตัวอย่างที่ประกาศไว้สำหรับ [status] ; ไม่มี = ข้อความมาตรฐาน
  MockReply _declared(ApiEndpoint e, int status) {
    for (final r in e.responses) {
      if (r.status == status && r.example.trim().isNotEmpty) {
        try {
          return MockReply(status, body: jsonEncode(jsonDecode(r.example.trim())));
        } catch (_) {
          return _json(status, r.example.trim());
        }
      }
    }
    return _json(status, {'error': httpStatusText(status).toLowerCase().replaceAll(' ', '_'), 'message': httpStatusText(status)});
  }

  /// รหัสสำเร็จของ endpoint: 2xx ตัวแรกที่ประกาศ ไม่มี = ค่ามาตรฐานของ method
  static int _successStatus(ApiEndpoint e) {
    for (final r in e.responses) {
      if (r.status >= 200 && r.status < 300) return r.status;
    }
    return switch (e.method) {
      ApiMethod.post => 201,
      ApiMethod.delete => 204,
      _ => 200,
    };
  }

  MockReply _serve(ApiEndpoint e, Map<String, String> params, MockRequest req, Map<String, Object?>? body) {
    final table = _tableOf(e);
    if (table == null || table.columns.isEmpty) return _static(e, body);
    final rows = _store(e.table!, table);
    final item = e.pathParams.isNotEmpty && RegExp(r'\{[^}/]+\}/?$').hasMatch(e.path);
    final ok = _successStatus(e);
    final pk = _pkColumn(table);

    Map<String, Object?>? find() {
      if (!item || pk == null) return null;
      final id = params[e.pathParams.last];
      for (final r in rows) {
        if ('${r[pk.name]}' == id) return r;
      }
      return null;
    }

    MockReply notFound() => _json(404, {'error': 'not_found', 'message': '${table.name} not found'});

    switch (e.method) {
      case ApiMethod.get:
        if (item) {
          final r = find();
          return r == null ? notFound() : _json(ok, r);
        }
        final filters = {for (final c in table.columns) if (req.query.containsKey(c.name)) c.name: req.query[c.name]!};
        return _json(ok, [for (final r in rows) if (filters.entries.every((f) => '${r[f.key]}' == f.value)) r]);
      case ApiMethod.post:
        if (item) {
          final r = find();
          return r == null ? notFound() : _json(ok == 201 ? 200 : ok, r);
        }
        final created = _create(e, table, rows, body ?? const {}, ok);
        if (created.status < 300) changes++;
        return created;
      case ApiMethod.put:
      case ApiMethod.patch:
        if (!item) return _static(e, body);
        final bad = _allowedViolation(table, body ?? const {});
        if (bad != null) return _json(422, {'error': 'validation', 'message': bad});
        final r = find();
        if (r == null) return notFound();
        for (final c in table.columns) {
          if (c.isPrimaryKey) continue;
          if (body != null && body.containsKey(c.name)) r[c.name] = body[c.name];
        }
        changes++;
        return _json(ok, r);
      case ApiMethod.delete:
        if (!item) return _static(e, body);
        final r = find();
        if (r == null) return notFound();
        rows.remove(r);
        changes++;
        return ok == 204 ? const MockReply(204) : _json(ok, r);
    }
  }

  /// ค่าในคำขอที่ผิดกติกา "ค่าที่อนุญาต" ของคอลัมน์ (เหมือนฐานข้อมูลที่ปฏิเสธ ENUM/CHECK) — คืนข้อความ ไม่มีปัญหา = null
  String? _allowedViolation(TableModel t, Map<String, Object?> body) {
    for (final c in t.columns) {
      if (!c.hasAllowedValues || !body.containsKey(c.name)) continue;
      final v = body[c.name];
      if (v == null) continue; // NULL ตรวจโดย NOT NULL (ไม่ใช่ที่นี่)
      if (!c.allowedValues.contains('$v')) {
        return '${c.name} must be one of: ${c.allowedValues.join(', ')} (got "$v")';
      }
    }
    return null;
  }

  MockReply _create(ApiEndpoint e, TableModel t, List<Map<String, Object?>> rows, Map<String, Object?> body, int status) {
    final bad = _allowedViolation(t, body);
    if (bad != null) return _json(422, {'error': 'validation', 'message': bad});
    final row = <String, Object?>{};
    for (final c in t.columns) {
      if (body.containsKey(c.name) && body[c.name] != null) {
        row[c.name] = body[c.name];
      } else if (c.autoIncrement && _isIntType(c)) {
        row[c.name] = null; // ใส่ทีหลังหลังตรวจซ้ำ
      } else if (c.isPrimaryKey && c.type == DataType.uuid) {
        row[c.name] = _uuid();
      } else {
        row[c.name] = _defaultOf(c);
      }
    }
    // PK / UNIQUE ซ้ำกับแถวที่มีอยู่ = 409 (เหมือนฐานข้อมูลจริง)
    for (final c in t.columns) {
      if (!(c.isPrimaryKey || c.unique)) continue;
      final v = row[c.name];
      if (v == null) continue;
      if (rows.any((r) => '${r[c.name]}' == '$v')) {
        return _json(409, {'error': 'conflict', 'message': '${c.name} "$v" already exists in ${t.name}'});
      }
    }
    for (final c in t.columns) {
      if (row[c.name] == null && c.autoIncrement && _isIntType(c)) row[c.name] = _nextId(e.table!, t, c);
    }
    rows.add(row);
    return _json(status, row);
  }

  MockReply _static(ApiEndpoint e, Map<String, Object?>? body) {
    final status = _successStatus(e);
    if (status == 204) return const MockReply(204);
    for (final r in e.responses) {
      if (r.status == status && r.example.trim().isNotEmpty) return _declared(e, status);
    }
    if (e.method.hasBody && body != null) return _json(status, body);
    return _json(status, e.method == ApiMethod.get ? <String, Object?>{} : {'ok': true});
  }

  // ---------- ข้อมูลตาราง ----------

  TableModel? _tableOf(ApiEndpoint e) {
    final r = e.table;
    if (r == null) return null;
    return workspace().documentById(r.docId)?.er?.tableById(r.tableId);
  }

  List<Map<String, Object?>> _store(ApiTableRef ref, TableModel t) {
    final key = '${ref.docId}/${ref.tableId}';
    return _rows.putIfAbsent(key, () {
      final out = <Map<String, Object?>>[];
      for (final s in t.seedRows) {
        out.add({for (final c in t.columns) c.name: s.containsKey(c.id) ? _typed(c, s[c.id]) : _defaultOf(c)});
      }
      // เติม AUTO INCREMENT ที่ seed ไม่ได้ใส่ ต่อจากเลขสูงสุดที่มี
      for (final c in t.columns) {
        if (!(c.autoIncrement && _isIntType(c))) continue;
        var max = 0;
        for (final r in out) {
          final v = r[c.name];
          if (v is int && v > max) max = v;
        }
        _counters['$key/${c.id}'] = max;
        for (final r in out) {
          if (r[c.name] == null) r[c.name] = _nextId(ref, t, c);
        }
      }
      return out;
    });
  }

  int _nextId(ApiTableRef ref, TableModel t, ColumnModel c) {
    final k = '${ref.docId}/${ref.tableId}/${c.id}';
    var n = _counters[k] ?? 0;
    if (!_counters.containsKey(k)) {
      for (final r in _rows['${ref.docId}/${ref.tableId}'] ?? const <Map<String, Object?>>[]) {
        final v = r[c.name];
        if (v is int && v > n) n = v;
      }
    }
    _counters[k] = n + 1;
    return n + 1;
  }

  static ColumnModel? _pkColumn(TableModel t) {
    for (final c in t.columns) {
      if (c.isPrimaryKey) return c;
    }
    for (final c in t.columns) {
      if (c.name.toLowerCase() == 'id') return c;
    }
    return t.columns.firstOrNull;
  }

  static bool _isIntType(ColumnModel c) => c.type == DataType.integer || c.type == DataType.bigint || c.type == DataType.smallint;

  /// ค่าเริ่มต้นของคอลัมน์ (DEFAULT ใน ER) เป็นค่า JSON: `'guest'` -> guest (ถอดเครื่องหมายคำพูดของ SQL) ; `CURRENT_TIMESTAMP`/`NOW()` -> เวลาปัจจุบัน ;
  /// `CURRENT_DATE` -> วันนี้ ; `NULL`/ไม่มี -> null
  Object? _defaultOf(ColumnModel c) {
    final raw = c.defaultValue?.trim();
    if (raw == null || raw.isEmpty) return null;
    final up = raw.toUpperCase();
    if (up == 'NULL') return null;
    final now = _now();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${now.year.toString().padLeft(4, '0')}-${two(now.month)}-${two(now.day)}';
    if (up == 'CURRENT_DATE' || up == 'CURDATE()') return date;
    if (up.startsWith('CURRENT_TIMESTAMP') || up == 'NOW()' || up == 'GETDATE()' || up.startsWith('DATETIME(')) {
      return c.type == DataType.date ? date : '$date ${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    }
    final quoted = raw.length >= 2 && raw.startsWith("'") && raw.endsWith("'");
    return _typed(c, quoted ? raw.substring(1, raw.length - 1).replaceAll("''", "'") : raw);
  }

  /// ค่าในช่องของ seed/default -> ค่า JSON ตามชนิดคอลัมน์ (null = NULL)
  static Object? _typed(ColumnModel c, String? raw) {
    final s = seedNormalized(c, raw);
    if (s == null) return null;
    switch (c.type) {
      case DataType.integer:
      case DataType.bigint:
      case DataType.smallint:
        return int.tryParse(s);
      case DataType.decimal:
      case DataType.float:
        return num.tryParse(s);
      case DataType.boolean:
        return s == 'true';
      case DataType.json:
        try {
          return jsonDecode(s);
        } catch (_) {
          return s;
        }
      default:
        return s;
    }
  }

  String _uuid() {
    String hex(int n) => List.generate(n, (_) => _rnd.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-${(8 + _rnd.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
  }
}
