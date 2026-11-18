import 'dart:convert';

import '../models/api_model.dart';
import '../models/workspace.dart';

/// ค่าตัวอย่างจากข้อความ: JSON ที่ถูกต้อง = ค่าที่อ่านได้ ; ไม่ใช่ JSON = ข้อความเดิม
Object? _example(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return s;
  }
}

/// คำอธิบายมาตรฐานของรหัสสถานะ (ใช้เมื่อ response ไม่มีคำอธิบาย — OpenAPI บังคับให้มี description)
String httpStatusText(int s) => switch (s) {
      200 => 'OK',
      201 => 'Created',
      204 => 'No Content',
      400 => 'Bad Request',
      401 => 'Unauthorized',
      403 => 'Forbidden',
      404 => 'Not Found',
      409 => 'Conflict',
      422 => 'Unprocessable Entity',
      500 => 'Internal Server Error',
      _ => 'Response $s',
    };

/// operationId ที่ไม่ซ้ำ: method + path ในรูป camelCase (`GET /orders/{id}` → `getOrdersById`)
String _operationId(ApiEndpoint e, Set<String> used) {
  final words = <String>[e.method.name];
  for (final seg in e.path.split('/').where((s) => s.isNotEmpty)) {
    final m = RegExp(r'^\{(.+)\}$').firstMatch(seg);
    final w = m == null ? seg : 'by_${m.group(1)}';
    words.addAll(w.split(RegExp(r'[^A-Za-z0-9]+')).where((x) => x.isNotEmpty));
  }
  var id = [for (final (i, w) in words.indexed) i == 0 ? w.toLowerCase() : '${w[0].toUpperCase()}${w.substring(1)}'].join();
  var n = 2;
  final base = id;
  while (!used.add(id)) {
    id = '$base${n++}';
  }
  return id;
}

/// เอกสาร OpenAPI 3.1 (โครง JSON) ของ [api] ; [w] = ใช้คำอธิบายคอลัมน์ ER เติมให้ฟิลด์ที่ไม่มีคำอธิบาย
Map<String, dynamic> openApiDocument(ApiDocument api, {Workspace? w, String fallbackTitle = 'API'}) {
  final paths = <String, Map<String, dynamic>>{};
  final ops = <String>{};
  var anyAuth = false;
  for (final e in api.endpoints) {
    anyAuth |= e.auth;
    final op = <String, dynamic>{
      'operationId': _operationId(e, ops),
      if (e.summary.isNotEmpty) 'summary': e.summary,
      if (e.effectiveGroup.isNotEmpty) 'tags': [e.effectiveGroup],
      if (e.auth) 'security': [
        {'bearerAuth': <String>[]},
      ],
      if (e.pathParams.isNotEmpty)
        'parameters': [
          for (final p in e.pathParams)
            {
              'name': p,
              'in': 'path',
              'required': true,
              'schema': {'type': 'string'},
            },
        ],
    };
    final named = [for (final f in e.fields) if (f.name.trim().isNotEmpty) f];
    if (named.isNotEmpty) {
      op['requestBody'] = {
        'required': true,
        'content': {
          'application/json': {
            'schema': {
              'type': 'object',
              'properties': {
                for (final f in named)
                  f.name.trim(): {
                    'type': f.type.name,
                    if (f.type == ApiType.array) 'items': <String, dynamic>{},
                    if (_description(w, f) case final d? when d.isNotEmpty) 'description': d,
                  },
              },
              if (named.any((f) => f.required)) 'required': [for (final f in named) if (f.required) f.name.trim()],
            },
          },
        },
      };
    }
    op['responses'] = {
      if (e.responses.isEmpty) 'default': {'description': 'Response'},
      for (final r in e.responses)
        '${r.status}': {
          'description': r.description.isEmpty ? httpStatusText(r.status) : r.description,
          if (r.example.trim().isNotEmpty)
            'content': {
              'application/json': {'example': _example(r.example.trim())},
            },
        },
    };
    paths.putIfAbsent(e.path, () => {})[e.method.name] = op;
  }
  return {
    'openapi': '3.1.0',
    'info': {'title': api.title.trim().isEmpty ? fallbackTitle : api.title.trim(), 'version': api.version.trim().isEmpty ? '1.0.0' : api.version.trim()},
    if (api.baseUrl.trim().isNotEmpty)
      'servers': [
        {'url': api.baseUrl.trim()},
      ],
    'paths': paths,
    if (anyAuth)
      'components': {
        'securitySchemes': {
          'bearerAuth': {'type': 'http', 'scheme': 'bearer'},
        },
      },
  };
}

String? _description(Workspace? w, ApiField f) {
  if (f.description.trim().isNotEmpty) return f.description.trim();
  final r = f.column;
  if (w == null || r == null) return null;
  return w.documentById(r.docId)?.er?.tableById(r.tableId)?.columnById(r.columnId ?? '')?.comment.trim();
}

/// ข้อความ OpenAPI 3.1 แบบ JSON จัดย่อหน้า
String exportOpenApiJson(ApiDocument api, {Workspace? w, String fallbackTitle = 'API'}) =>
    const JsonEncoder.withIndent('  ').convert(openApiDocument(api, w: w, fallbackTitle: fallbackTitle));
