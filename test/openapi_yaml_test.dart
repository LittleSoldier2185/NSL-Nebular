import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/cli/nebular_api.dart';
import 'package:nsl_nebular/core/export/openapi_export.dart';
import 'package:nsl_nebular/core/export/yaml_writer.dart';
import 'package:nsl_nebular/core/models/api_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:yaml/yaml.dart';

/// Phase 35: OpenAPI YAML — อ่านกลับด้วย `package:yaml` แล้วต้องเท่ากับข้อมูลเดิมทุกค่าและทุกชนิด
void main() {
  /// YamlMap/YamlList → Map/List ธรรมดา (คงลำดับคีย์)
  Object? plain(Object? v) => switch (v) {
        Map m => {for (final e in m.entries) e.key: plain(e.value)},
        List l => [for (final x in l) plain(x)],
        _ => v,
      };

  void roundTrip(Object? value) {
    final text = writeYaml(value);
    final back = plain(loadYaml(text));
    // เทียบผ่าน JSON เพื่อจับทั้งชนิดข้อมูลและลำดับคีย์
    expect(jsonEncode(back), jsonEncode(value), reason: text);
  }

  const tricky = [
    '', ' ', 'a ', ' a', 'true', 'False', 'NULL', 'yes', 'No', 'on', 'off', 'y', 'N', '~', 'null',
    '1', '-1', '1.5', '1e3', '0x1F', '0o17', '012', '+5', '.5', '.inf', '.nan', '2026-11-26', '12:30', '1_000',
    'a: b', 'a:b', 'a :', ': a', 'a #b', '#a', '- a', '-', '? a', '[a]', '{a}', 'a, b', '&a', '*a', '!a', '|', '>', '%a', '@a', '`a',
    '"quoted"', "it's", r'back\slash', '/orders/{id}', '/a: b', 'Bad Request', 'get', '200', 'a\tb',
    'ภาษาไทย', 'สั่งซื้อ: ด่วน #1', '"', "'", '---', '...', 'a\u0000b', 'a\u007Fb', 'a\u0085b', 'a b', '﻿a', '😀',
    'บรรทัดหนึ่ง\nบรรทัดสอง', 'a\nb\n', 'a\nb\n\n', '\na', ' a\nb', 'a \nb', 'a\n\nb', 'a\n  เยื้อง\nb', 'a\n#ไม่ใช่คอมเมนต์\n- ไม่ใช่รายการ\nk: v',
    'a\r\nb', 'a\tx\nb', '\n', 'x\n---\ny',
  ];

  test('ข้อความที่อ่านผิดชนิดได้ง่าย: เป็นค่า เป็นคีย์ และเป็นสมาชิกรายการ', () {
    for (final s in tricky) {
      roundTrip({'v': s, 'list': [s, {'k': s}, [s]], 'after': 1});
      roundTrip({s: s, 'after': 1});
    }
    roundTrip({for (final s in tricky) s: [for (final t in tricky) t]});
  });

  test('ชนิดอื่น: ตัวเลข จริงเท็จ null ว่าง ซ้อนหลายชั้น และค่าเดี่ยวที่ชั้นบนสุด', () {
    roundTrip({'i': -5, 'd': 1.5, 'big': 1e300, 'tiny': 1e-7, 'whole': 3.0, 't': true, 'f': false, 'n': null, 'em': <String, Object?>{}, 'el': <Object?>[]});
    roundTrip([
      [
        [1, 2],
        <Object?>[],
      ],
      {'a': {'b': {'c': [null, {}]}}},
    ]);
    for (final v in [null, true, 7, 'x', 'ก: ข', <Object?>[], <String, Object?>{}]) {
      roundTrip(v);
    }
  });

  test('สุ่มข้อความจากอักขระพิเศษ 1,000 รอบ (seed คงที่)', () {
    const chars = ['a', 'Z', '0', '9', ' ', ' ', '\n', '\n', ':', '#', '-', '?', '"', "'", r'\', '{', '}', '[', ']', ',', '|', '>', '&', '*', '!', '%', '@', '.', '/', '_', '~', '+', 'e', '\t', '\r', 'ก', 'ิ', '\u0085', ' '];
    final r = Random(35);
    String next() => [for (var i = r.nextInt(12); i > 0; i--) chars[r.nextInt(chars.length)]].join();
    for (var i = 0; i < 1000; i++) {
      final key = next();
      roundTrip({key: next(), 'list': [next(), {next(): next()}]});
    }
  });

  test('OpenAPI ของตัวอย่างโรงแรม (ชื่อไทย): YAML อ่านกลับแล้วเท่ากับ JSON', () async {
    final w = await loadProject('samples/hotel_booking.nsln');
    final apis = w.documentsOf(DocType.api);
    expect(apis, isNotEmpty);
    for (final d in apis) {
      final yaml = exportOpenApiYaml(d.api!, w: w, fallbackTitle: d.name);
      final json = jsonDecode(exportOpenApiJson(d.api!, w: w, fallbackTitle: d.name));
      expect(jsonEncode(plain(loadYaml(yaml))), jsonEncode(json));
      expect(yaml, startsWith('openapi: "3.1.0"\ninfo:\n  title: '));
    }
  });

  test('ตัวอย่าง response เป็น JSON ซ้อน / ข้อความหลายบรรทัด / คำอธิบายที่มี : และ #', () {
    final api = ApiDocument(title: 'ร้าน: ค้า #1', endpoints: [
      ApiEndpoint(id: 'a', path: '/x/{id}', summary: 'บรรทัดแรก\nบรรทัดสอง', auth: true, responses: [
        ApiResponse(status: 200, example: '{"code": "007", "ok": "true", "items": [{"price": 1.5, "note": null}]}'),
        ApiResponse(status: 404, description: 'no', example: 'ไม่ใช่ JSON\n  มีหลายบรรทัด'),
      ]),
    ]);
    expect(jsonEncode(plain(loadYaml(exportOpenApiYaml(api)))), jsonEncode(jsonDecode(exportOpenApiJson(api))));
  });
}
