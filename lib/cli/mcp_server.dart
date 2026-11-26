import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/app_info.dart';
import 'nebular_api.dart';

/// MCP server ของ Nebular (JSON-RPC 2.0 ผ่าน stdio, ข้อความละบรรทัด) — ให้ Claude Code อ่าน/ตรวจ/ส่งออก/สร้างโค้ดจากไฟล์โปรเจกต์ได้
///
/// ออฟไลน์ล้วน: Claude Code เปิดโปรแกรมนี้เป็นโปรเจกต์ลูกในเครื่อง ไม่เปิดพอร์ต ไม่ต้องมี host/บัญชี
/// **ไม่เขียนไฟล์โปรเจกต์** ; เขียนได้เฉพาะ `nebular_export_to_file` และ `nebular_codegen_write` ตามปลายทางที่ระบุ
class NebularMcp {
  NebularMcp({this.log});

  /// ที่เขียนบันทึก (stderr เท่านั้น — stdout ใช้กับโปรโตคอล)
  final void Function(String message)? log;

  static const supportedVersions = ['2025-06-18', '2025-03-26', '2024-11-05'];

  /// ขนาดข้อความสูงสุดที่ส่งกลับต่อครั้ง (ตัดแล้วบอกไว้ท้ายข้อความ)
  static const defaultMaxChars = 60000;

  /// รับข้อความ 1 ข้อความ (หรืออาร์เรย์ของข้อความ) — คืนคำตอบ (null = เป็น notification ไม่ต้องตอบ)
  Future<Object?> handleMessage(Object? msg) async {
    if (msg is List) {
      final out = <Object>[];
      for (final m in msg) {
        final r = await _one(m);
        if (r != null) out.add(r);
      }
      return out.isEmpty ? null : out;
    }
    return _one(msg);
  }

  Future<Map<String, Object?>?> _one(Object? msg) async {
    if (msg is! Map) return _error(null, -32600, 'Invalid Request');
    final id = msg['id'];
    final method = msg['method'];
    final hasId = msg.containsKey('id');
    if (method is! String) return hasId ? _error(id, -32600, 'Invalid Request') : null;
    final params = msg['params'] is Map ? Map<String, Object?>.from(msg['params'] as Map) : <String, Object?>{};
    try {
      switch (method) {
        case 'initialize':
          final want = params['protocolVersion'];
          return _result(id, {
            'protocolVersion': supportedVersions.contains(want) ? want : supportedVersions.first,
            'capabilities': {'tools': {'listChanged': false}},
            'serverInfo': {'name': 'nebular', 'title': kAppName, 'version': kAppVersion},
            'instructions': 'อ่าน/ตรวจ/ส่งออก/สร้างโค้ดจากไฟล์โปรเจกต์ NSL Nebular (.nsln) — ระบุ path ของไฟล์ในทุกเครื่องมือ (path สัมพัทธ์อิงโฟลเดอร์ที่เปิดเซิร์ฟเวอร์) '
                'เครื่องมือไม่แก้ไฟล์โปรเจกต์ ; แก้ผ่านโปรแกรม Nebular',
          });
        case 'ping':
          return _result(id, {});
        case 'tools/list':
          return _result(id, {'tools': tools});
        case 'tools/call':
          return _result(id, await _call(params['name'], params['arguments']));
        default:
          if (method.startsWith('notifications/')) return null;
          return hasId ? _error(id, -32601, 'Method not found: $method') : null;
      }
    } on _RpcError catch (e) {
      return hasId ? _error(id, e.code, e.message) : null;
    } catch (e, st) {
      log?.call('ข้อผิดพลาดภายใน: $e\n$st');
      return hasId ? _error(id, -32603, 'Internal error: $e') : null;
    }
  }

  static Map<String, Object?> _result(Object? id, Object? result) => {'jsonrpc': '2.0', 'id': id, 'result': result};
  static Map<String, Object?> _error(Object? id, int code, String message) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };

  // ---------- เครื่องมือ ----------

  static Map<String, Object?> _tool(String name, String title, String description, Map<String, Object?> properties, List<String> required,
          {bool readOnly = true}) =>
      {
        'name': name,
        'title': title,
        'description': description,
        'inputSchema': {'type': 'object', 'properties': properties, 'required': required, 'additionalProperties': false},
        'annotations': {'title': title, 'readOnlyHint': readOnly, 'destructiveHint': false, 'idempotentHint': true, 'openWorldHint': false},
      };

  static const _path = {'type': 'string', 'description': 'path ของไฟล์โปรเจกต์ .nsln (หรือ .nsld/.nslm/.erd เดิม)'};
  static const _lang = {'type': 'string', 'enum': ['th', 'en'], 'description': 'ภาษาของข้อความจากตัวตรวจ (ค่าเริ่มต้น th)'};
  static const _max = {'type': 'integer', 'minimum': 1000, 'description': 'ตัดผลลัพธ์ที่ยาวเกินจำนวนตัวอักษรนี้ (ค่าเริ่มต้น 60000)'};
  static const _targets = {
    'type': 'array',
    'items': {'type': 'string'},
    'description': 'ชื่อเป้าหมาย (ดูจาก nebular_list_codegen_targets) หรือ ["all"] = ทุกตัวที่โปรเจกต์นี้สร้างได้',
  };

  static final List<Map<String, Object?>> tools = [
    _tool('nebular_project_info', 'ภาพรวมโปรเจกต์', 'ชื่อ จำนวนเอกสารแยกชนิด ตาราง endpoint ความต้องการ และจำนวนปัญหา', {'path': _path}, ['path']),
    _tool('nebular_list_documents', 'รายการเอกสาร', 'รายการเอกสารทั้งหมดในโปรเจกต์ (id ชนิด ชื่อ) — ใช้ id หรือชื่อไปอ่านต่อ', {'path': _path}, ['path']),
    _tool('nebular_read_document', 'อ่านเนื้อหาเอกสาร',
        'เนื้อหาของเอกสารหนึ่งชิ้นเป็น JSON (ER: ตาราง/คอลัมน์/FK/seed · API: endpoint · Wireframe: ชิ้นส่วน · DFD/Flowchart/Screen Flow: โหนดและเส้น)',
        {'path': _path, 'document': {'type': 'string', 'description': 'id หรือชื่อของเอกสาร'}, 'max_chars': _max}, ['path', 'document']),
    _tool('nebular_validate', 'ตรวจปัญหาทั้งโปรเจกต์', 'ตรวจทุกเอกสารและความสัมพันธ์ข้ามเอกสาร คืนรายการปัญหา (error/warning/info) พร้อมรหัสและเอกสารที่เกี่ยวข้อง',
        {'path': _path, 'min_severity': {'type': 'string', 'enum': ['error', 'warning', 'info']}, 'language': _lang}, ['path']),
    _tool('nebular_export', 'ส่งออกเป็นข้อความ', 'ส่งออกทั้งโปรเจกต์เป็นข้อความ: markdown (พจนานุกรม+เอกสาร) / html / sql (ทุก ER) / openapi, openapi-yaml (เอกสาร API แบบ JSON หรือ YAML)',
        {'path': _path, 'format': {'type': 'string', 'enum': kExportFormats}, 'document': {'type': 'string', 'description': 'openapi / openapi-yaml: เอกสาร API ที่ใช้ (ไม่ระบุ = ตัวแรก)'}, 'language': _lang, 'max_chars': _max},
        ['path', 'format']),
    _tool('nebular_export_to_file', 'ส่งออกลงไฟล์', 'เหมือน nebular_export แต่เขียนลงไฟล์ out_file (สร้างโฟลเดอร์ให้ ทับไฟล์เดิมถ้ามี) — ไม่แก้ไฟล์โปรเจกต์',
        {'path': _path, 'format': {'type': 'string', 'enum': kExportFormats}, 'out_file': {'type': 'string'}, 'document': {'type': 'string'}, 'language': _lang},
        ['path', 'format', 'out_file'],
        readOnly: false),
    _tool('nebular_list_codegen_targets', 'เป้าหมายสร้างโค้ด', 'รายการเป้าหมายการสร้างโค้ด (sqlDdl, laravelMigration, prisma, typescript, dart, openApi, flutterScreen, …) บอกว่าโปรเจกต์นี้สร้างตัวไหนได้',
        {'path': _path}, ['path']),
    _tool('nebular_codegen_preview', 'ดูไฟล์ที่จะสร้าง', 'แสดงไฟล์ (path ขนาด เอกสารต้นทาง) และคำเตือนที่จะได้จากการสร้างโค้ด โดยยังไม่เขียนอะไร',
        {'path': _path, 'targets': _targets}, ['path', 'targets']),
    _tool('nebular_codegen_write', 'สร้างโค้ดลงโฟลเดอร์',
        'สร้างโค้ดลง out_dir — **ไม่ทับไฟล์ที่ถูกแก้ด้วยมือ** (ข้ามและรายงานใน skippedEditedByHand) เว้นแต่ overwrite_edited=true ; ผลคงที่ (สร้างซ้ำได้ไฟล์เดิม)',
        {'path': _path, 'targets': _targets, 'out_dir': {'type': 'string'}, 'overwrite_edited': {'type': 'boolean', 'description': 'เขียนทับไฟล์ที่ถูกแก้ด้วยมือด้วย (ค่าเริ่มต้น false)'}},
        ['path', 'targets', 'out_dir'],
        readOnly: false),
  ];

  static String _str(Map args, String key, {bool required = true}) {
    final v = args[key];
    if (v is String && v.trim().isNotEmpty) return v;
    if (!required && v == null) return '';
    throw _RpcError(-32602, 'ต้องระบุ "$key" เป็นข้อความ');
  }

  static List<String> _strList(Map args, String key) {
    final v = args[key];
    if (v is List && v.every((e) => e is String)) return v.cast<String>();
    if (v is String) return v.split(',');
    throw _RpcError(-32602, 'ต้องระบุ "$key" เป็นรายการข้อความ');
  }

  static String _cap(String s, Map args) {
    final raw = args['max_chars'];
    final max = raw is int && raw >= 1000 ? raw : defaultMaxChars;
    if (s.length <= max) return s;
    return '${s.substring(0, max)}\n… [ตัดที่ $max จาก ${s.length} ตัวอักษร — เพิ่ม max_chars หรือใช้ nebular_export_to_file]';
  }

  static String _json(Object? o) => const JsonEncoder.withIndent('  ').convert(o);

  Future<Map<String, Object?>> _call(Object? name, Object? rawArgs) async {
    if (name is! String || !tools.any((t) => t['name'] == name)) throw _RpcError(-32602, 'ไม่รู้จักเครื่องมือ: $name');
    final args = rawArgs is Map ? rawArgs : <String, Object?>{};
    try {
      setCliLanguage(args['language'] as String?);
      final w = await loadProject(_str(args, 'path'));
      final String text;
      switch (name) {
        case 'nebular_project_info':
          text = _json(projectInfo(w, path: args['path'] as String));
        case 'nebular_list_documents':
          text = _json(listDocuments(w));
        case 'nebular_read_document':
          text = _cap(_json(readDocument(w, _str(args, 'document'))), args);
        case 'nebular_validate':
          text = _json(validateReport(w, minSeverity: parseSeverity(args['min_severity'] as String?)));
        case 'nebular_export':
          text = _cap(exportProject(w, _str(args, 'format'), document: args['document'] as String?), args);
        case 'nebular_export_to_file':
          final body = exportProject(w, _str(args, 'format'), document: args['document'] as String?);
          final f = File(_str(args, 'out_file'));
          await f.parent.create(recursive: true);
          await f.writeAsString(body);
          text = 'เขียนแล้ว: ${f.absolute.path} (${utf8.encode(body).length} ไบต์)';
        case 'nebular_list_codegen_targets':
          text = _json(listTargets(w));
        case 'nebular_codegen_preview':
          text = _json(codegenPreview(w, parseTargets(w, _strList(args, 'targets'))));
        case 'nebular_codegen_write':
          text = _json(await codegenWrite(w, parseTargets(w, _strList(args, 'targets')), _str(args, 'out_dir'), overwriteEdited: args['overwrite_edited'] == true));
        default:
          throw _RpcError(-32602, 'ไม่รู้จักเครื่องมือ: $name');
      }
      return {'content': [{'type': 'text', 'text': text}], 'isError': false};
    } on NebularError catch (e) {
      // ข้อผิดพลาดของการใช้งาน (ไฟล์ไม่พบ ชื่อเอกสารผิด ฯลฯ) = ผลลัพธ์ที่โมเดลเห็นและแก้เองได้ ไม่ใช่ข้อผิดพลาดของโปรโตคอล
      return {'content': [{'type': 'text', 'text': e.message}], 'isError': true};
    }
  }
}

class _RpcError implements Exception {
  _RpcError(this.code, this.message);
  final int code;
  final String message;
}

/// วนอ่านข้อความจาก [input] ทีละบรรทัดแล้วตอบทีละบรรทัดผ่าน [writeLine] จนกว่า input จะปิด
Future<void> runMcpStdio(Stream<List<int>> input, void Function(String line) writeLine, {void Function(String)? log}) async {
  final server = NebularMcp(log: log);
  final lines = input.transform(utf8.decoder).transform(const LineSplitter());
  // ประมวลผลทีละข้อความตามลำดับ (คำสั่งเขียนไฟล์ไม่ซ้อนกัน)
  await for (final line in lines) {
    if (line.trim().isEmpty) continue;
    Object? reply;
    try {
      reply = await server.handleMessage(jsonDecode(line));
    } on FormatException {
      reply = {'jsonrpc': '2.0', 'id': null, 'error': {'code': -32700, 'message': 'Parse error'}};
    }
    if (reply != null) writeLine(jsonEncode(reply));
  }
}
