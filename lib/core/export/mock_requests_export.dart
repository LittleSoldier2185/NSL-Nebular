import 'dart:convert';

import '../models/api_model.dart';

/// ส่งออก "ชุดคำขอ" ของ API ไว้ยิงทดสอบ Mock Server (หรือเซิร์ฟเวอร์จริง) : Postman Collection v2.1 และสคริปต์ curl
///
/// - URL ฐานเป็นตัวแปร `{{baseUrl}}` (Postman) / `$BASE_URL` (curl) ค่าเริ่มต้น = ที่อยู่ของ Mock ([kMockRequestsBase])
/// - body ตัวอย่างสร้างจากฟิลด์ของ endpoint (ดู [exampleBodyOf]) ; ตัวแปรใน path (`{id}`) ใส่ค่า 1
/// - endpoint ที่ต้องล็อกอิน ใส่ header `Authorization: Bearer {{token}}` (curl : `$TOKEN`)
/// - จัดโฟลเดอร์ตามกลุ่มของ endpoint (ไม่ได้ระบุกลุ่ม = ใช้ path ส่วนแรก เหมือนหน้า API)

/// ที่อยู่เริ่มต้นของ Mock Server
const kMockRequestsBase = 'http://127.0.0.1:8787';

/// ค่าตัวอย่างของฟิลด์ (ใช้ชื่อฟิลด์เดาค่าที่อ่านง่ายสำหรับข้อความ)
Object? exampleValueOf(ApiField f) {
  switch (f.type) {
    case ApiType.integer:
      return 1;
    case ApiType.number:
      return 1.5;
    case ApiType.boolean:
      return true;
    case ApiType.array:
      return <Object?>[];
    case ApiType.object:
      return <String, Object?>{};
    case ApiType.string:
      final n = f.name.toLowerCase();
      if (n.contains('email')) return 'user@example.com';
      if (n.contains('password')) return 'P@ssw0rd!';
      if (n.contains('phone') || n.contains('tel')) return '0812345678';
      if (n.contains('date')) return '2026-01-31';
      if (n.contains('name')) return 'Example';
      return 'string';
  }
}

/// body ตัวอย่างของ endpoint (ฟิลด์ที่ชื่อว่างข้าม) ; endpoint ที่ไม่มี body (GET/DELETE) หรือไม่มีฟิลด์ = null
Map<String, Object?>? exampleBodyOf(ApiEndpoint e) {
  if (!e.method.hasBody) return null;
  final fields = e.fields.where((f) => f.name.trim().isNotEmpty).toList();
  if (fields.isEmpty) return null;
  return {for (final f in fields) f.name.trim(): exampleValueOf(f)};
}

String _prettyJson(Object? v) => const JsonEncoder.withIndent('  ').convert(v);

/// กลุ่มของ endpoint ตามลำดับที่เจอครั้งแรก : (ชื่อกลุ่ม ว่าง = ไม่อยู่ในโฟลเดอร์, endpoint)
List<(String, List<ApiEndpoint>)> _grouped(ApiDocument api) {
  final order = <String>[];
  final map = <String, List<ApiEndpoint>>{};
  for (final e in api.endpoints) {
    final g = e.effectiveGroup;
    if (!map.containsKey(g)) order.add(g);
    (map[g] ??= []).add(e);
  }
  return [for (final g in order) (g, map[g]!)];
}

String _requestName(ApiEndpoint e) => e.summary.trim().isNotEmpty ? '${e.method.label} ${e.path} — ${e.summary.trim()}' : e.title;

/// Postman Collection v2.1 (JSON) ของ API ; ตัวแปรของ collection : `baseUrl`, `token`
String exportPostmanCollection(ApiDocument api, {String baseUrl = kMockRequestsBase, String token = 'token'}) {
  Map<String, Object?> item(ApiEndpoint e) {
    final segs = [for (final s in e.path.split('/')) if (s.isNotEmpty) s];
    // {id} -> :id (ตัวแปรของ path ใน Postman) พร้อมค่าตัวอย่าง
    final path = [for (final s in segs) s.replaceAllMapped(RegExp(r'^\{([^}]+)\}$'), (m) => ':${m.group(1)}')];
    final params = e.pathParams;
    final body = exampleBodyOf(e);
    return {
      'name': _requestName(e),
      'request': {
        'method': e.method.label,
        'header': [
          if (body != null) {'key': 'Content-Type', 'value': 'application/json'},
          if (e.auth) {'key': 'Authorization', 'value': 'Bearer {{token}}'},
        ],
        if (body != null) 'body': {'mode': 'raw', 'raw': _prettyJson(body), 'options': {'raw': {'language': 'json'}}},
        'url': {
          'raw': '{{baseUrl}}/${path.join('/')}',
          'host': ['{{baseUrl}}'],
          'path': path,
          if (params.isNotEmpty) 'variable': [for (final p in params) {'key': p, 'value': '1'}],
        },
        if (e.summary.trim().isNotEmpty) 'description': e.summary.trim(),
      },
    };
  }

  final items = <Object?>[];
  for (final (g, list) in _grouped(api)) {
    if (g.isEmpty) {
      items.addAll(list.map(item));
    } else {
      items.add({'name': g, 'item': list.map(item).toList()});
    }
  }
  final title = api.title.trim().isEmpty ? 'API' : api.title.trim();
  return _prettyJson({
    'info': {
      'name': title,
      'description': api.version.isEmpty ? '' : 'version ${api.version}',
      'schema': 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
    },
    'item': items,
    'variable': [
      {'key': 'baseUrl', 'value': baseUrl},
      {'key': 'token', 'value': token},
    ],
  });
}

/// ข้อความที่จะใส่ในบรรทัดคอมเมนต์ของสคริปต์ : ยุบบรรทัดใหม่/ช่องว่างซ้ำ (ไม่งั้นข้อความหลายบรรทัดจะกลายเป็นคำสั่ง)
String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), " ").trim();

String _shellQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// สคริปต์ bash (`.sh`) ที่ยิงทุก endpoint ด้วย curl ; ตั้ง `BASE_URL` / `TOKEN` ทางสภาพแวดล้อมได้
String exportCurlScript(ApiDocument api, {String baseUrl = kMockRequestsBase, String token = 'token'}) {
  final b = StringBuffer()
    ..writeln('#!/usr/bin/env bash')
    ..writeln('# ${api.title.trim().isEmpty ? 'API' : _oneLine(api.title)} — ${api.endpoints.length} requests')
    ..writeln(r'# usage: BASE_URL=http://127.0.0.1:8787 TOKEN=xxx ./requests.sh')
    ..writeln('BASE_URL="\${BASE_URL:-$baseUrl}"')
    ..writeln('TOKEN="\${TOKEN:-$token}"');
  for (final (g, list) in _grouped(api)) {
    b
      ..writeln()
      ..writeln('# ===== ${g.isEmpty ? '(no group)' : _oneLine(g)} =====');
    for (final e in list) {
      final url = e.path.replaceAllMapped(RegExp(r'\{[^}/]+\}'), (_) => '1');
      final body = exampleBodyOf(e);
      b
        ..writeln()
        ..writeln('# ${_oneLine(_requestName(e))}')
        ..write('curl -sS -i -X ${e.method.label} "\$BASE_URL${url.startsWith('/') ? url : '/$url'}"');
      if (body != null) b.write(" -H 'Content-Type: application/json'");
      if (e.auth) b.write(r' -H "Authorization: Bearer $TOKEN"');
      if (body != null) b.write(' -d ${_shellQuote(jsonEncode(body))}');
      b.writeln();
    }
  }
  return b.toString();
}
