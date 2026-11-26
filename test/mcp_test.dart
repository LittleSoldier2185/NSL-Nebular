import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/cli/mcp_server.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';

import 'cli_test.dart' show writeProject;

/// MCP server ของ Nebular: โปรโตคอล + เครื่องมือ + stdio + โปรเซสจริง
void main() {
  late Directory tmp;
  late String project;
  late NebularMcp mcp;
  var nextId = 1;

  setUp(() async {
    currentLang = Lang.th;
    tmp = await Directory.systemTemp.createTemp('nebular_mcp_');
    project = await writeProject(tmp);
    mcp = NebularMcp();
    nextId = 1;
  });
  tearDown(() async {
    currentLang = Lang.th;
    await tmp.delete(recursive: true);
  });

  Future<Map> rpc(String method, [Map<String, Object?>? params]) async {
    final r = await mcp.handleMessage({'jsonrpc': '2.0', 'id': nextId++, 'method': method, 'params': ?params});
    return r as Map;
  }

  /// เรียกเครื่องมือ — คืน (isError, ข้อความ)
  Future<(bool, String)> call(String tool, Map<String, Object?> args) async {
    final r = await rpc('tools/call', {'name': tool, 'arguments': args});
    expect(r['error'], isNull, reason: '$tool ต้องตอบเป็นผลลัพธ์ ไม่ใช่ข้อผิดพลาดของโปรโตคอล: ${r['error']}');
    final res = r['result'] as Map;
    final text = ((res['content'] as List).single as Map)['text'] as String;
    return (res['isError'] as bool, text);
  }

  group('โปรโตคอล', () {
    test('initialize: ตอบรุ่นโปรโตคอลที่รองรับ (ไม่รู้จัก = รุ่นแรกที่เรารองรับ) + ความสามารถ tools + ข้อมูลเซิร์ฟเวอร์', () async {
      final r = (await rpc('initialize', {'protocolVersion': '2024-11-05', 'capabilities': {}}))['result'] as Map;
      expect(r['protocolVersion'], '2024-11-05');
      expect((r['capabilities'] as Map).keys, contains('tools'));
      expect((r['serverInfo'] as Map)['name'], 'nebular');
      expect(r['instructions'], isA<String>());
      expect(((await rpc('initialize', {'protocolVersion': '1999-01-01'}))['result'] as Map)['protocolVersion'], NebularMcp.supportedVersions.first);
      expect(((await rpc('initialize'))['result'] as Map)['protocolVersion'], NebularMcp.supportedVersions.first);
    });

    test('notification ไม่ตอบ ; ping ตอบว่าง ; method ที่ไม่มี = -32601 ; ข้อความผิดรูป = -32600 ; id ถูกส่งกลับตรงกัน', () async {
      expect(await mcp.handleMessage({'jsonrpc': '2.0', 'method': 'notifications/initialized'}), isNull);
      expect(await mcp.handleMessage({'jsonrpc': '2.0', 'method': 'notifications/cancelled', 'params': {}}), isNull);
      expect(await mcp.handleMessage({'jsonrpc': '2.0', 'method': 'unknown/notify'}), isNull, reason: 'notification ที่ไม่รู้จักก็ไม่ตอบ');
      final ping = await mcp.handleMessage({'jsonrpc': '2.0', 'id': 'abc', 'method': 'ping'}) as Map;
      expect(ping['id'], 'abc');
      expect(ping['result'], isEmpty);
      final bad = await rpc('bogus');
      expect((bad['error'] as Map)['code'], -32601);
      expect(((await mcp.handleMessage('hello')) as Map)['error']['code'], -32600);
      expect(((await mcp.handleMessage({'jsonrpc': '2.0', 'id': 7})) as Map)['error']['code'], -32600);
    });

    test('batch: ตอบเฉพาะที่ต้องตอบตามลำดับ', () async {
      final r = await mcp.handleMessage([
        {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'},
        {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
      ]) as List;
      expect([for (final x in r) (x as Map)['id']], [1, 2]);
      expect(await mcp.handleMessage([{'jsonrpc': '2.0', 'method': 'notifications/initialized'}]), isNull);
    });

    test('tools/list: ทุกเครื่องมือมีชื่อ คำอธิบาย schema ที่ถูกต้อง ; เฉพาะ 2 ตัวที่เขียนไฟล์ที่ไม่ใช่ read-only', () async {
      final tools = ((await rpc('tools/list'))['result'] as Map)['tools'] as List;
      expect(tools.length, 9);
      final names = <String>{};
      for (final t in tools.cast<Map>()) {
        expect(names.add(t['name'] as String), isTrue, reason: 'ชื่อซ้ำ');
        expect(t['name'], matches(RegExp(r'^nebular_[a-z_]+$')));
        expect((t['description'] as String).length, greaterThan(20));
        final schema = t['inputSchema'] as Map;
        expect(schema['type'], 'object');
        final props = (schema['properties'] as Map).keys.toSet();
        expect((schema['required'] as List).every(props.contains), isTrue, reason: '${t['name']}: required ต้องอยู่ใน properties');
        expect(props, contains('path'));
      }
      final writers = [for (final t in tools.cast<Map>()) if ((t['annotations'] as Map)['readOnlyHint'] == false) t['name']];
      expect(writers, unorderedEquals(['nebular_export_to_file', 'nebular_codegen_write']));
    });
  });

  group('เครื่องมือ', () {
    test('info / list_documents / read_document / validate', () async {
      final (e1, info) = await call('nebular_project_info', {'path': project});
      expect(e1, isFalse);
      expect((jsonDecode(info) as Map)['tables'], 2);

      final (_, docs) = await call('nebular_list_documents', {'path': project});
      expect(jsonDecode(docs), hasLength(3));

      final (_, doc) = await call('nebular_read_document', {'path': project, 'document': 'Shop API'});
      expect((jsonDecode(doc) as Map)['type'], 'api');

      final (_, val) = await call('nebular_validate', {'path': project, 'language': 'en', 'min_severity': 'warning'});
      final v = jsonDecode(val) as Map;
      expect(v['errors'], 0);
      expect((v['issues'] as List).every((i) => (i as Map)['severity'] != 'info'), isTrue);
      expect(RegExp(r'[฀-๿]').hasMatch(((v['issues'] as List).first as Map)['message'] as String), isFalse);
    });

    test('export: ข้อความถูกตัดที่ max_chars พร้อมบอก ; export_to_file เขียนไฟล์ (สร้างโฟลเดอร์)', () async {
      final (_, full) = await call('nebular_export', {'path': project, 'format': 'markdown'});
      expect(full, contains('orders'));
      final (_, cut) = await call('nebular_export', {'path': project, 'format': 'markdown', 'max_chars': 1000});
      expect(cut.length, lessThan(full.length));
      expect(cut, contains('ตัดที่ 1000'));
      final (_, api) = await call('nebular_export', {'path': project, 'format': 'openapi'});
      expect(jsonDecode(api), isA<Map>());

      final out = '${tmp.path}/a/b/api.json';
      final (err, msg) = await call('nebular_export_to_file', {'path': project, 'format': 'openapi', 'out_file': out});
      expect(err, isFalse);
      expect(msg, contains('เขียนแล้ว'));
      expect(File(out).existsSync(), isTrue);
    });

    test('codegen: targets / preview (ไม่เขียน) / write (ไม่ทับที่แก้ด้วยมือ) / overwrite_edited', () async {
      final (_, targets) = await call('nebular_list_codegen_targets', {'path': project});
      expect(jsonDecode(targets), hasLength(13));
      final out = '${tmp.path}/gen';
      final (_, prev) = await call('nebular_codegen_preview', {'path': project, 'targets': ['sqlDdl']});
      expect(((jsonDecode(prev) as Map)['files'] as List).single['path'], 'database/schema.sql');
      expect(Directory(out).existsSync(), isFalse);

      final (_, w1) = await call('nebular_codegen_write', {'path': project, 'targets': ['sqlDdl', 'typescript'], 'out_dir': out});
      expect((jsonDecode(w1) as Map)['written'], 2);
      File('$out/database/schema.sql').writeAsStringSync('hand');
      final (_, w2) = await call('nebular_codegen_write', {'path': project, 'targets': ['sqlDdl'], 'out_dir': out});
      expect((jsonDecode(w2) as Map)['skippedEditedByHand'], ['database/schema.sql']);
      expect(File('$out/database/schema.sql').readAsStringSync(), 'hand');
      await call('nebular_codegen_write', {'path': project, 'targets': ['sqlDdl'], 'out_dir': out, 'overwrite_edited': true});
      expect(File('$out/database/schema.sql').readAsStringSync(), contains('CREATE TABLE'));
      final (_, all) = await call('nebular_codegen_preview', {'path': project, 'targets': 'sqlDdl,csharp'});
      expect(((jsonDecode(all) as Map)['files'] as List).length, 2, reason: 'ส่งเป็นข้อความคั่น , ก็ได้');
    });

    test('ข้อผิดพลาดของการใช้งานคืนเป็นผลลัพธ์ isError (โมเดลอ่านแล้วแก้เองได้) ไม่ใช่ข้อผิดพลาดโปรโตคอล', () async {
      final (e1, m1) = await call('nebular_read_document', {'path': project, 'document': 'nope'});
      expect(e1, isTrue);
      expect(m1, allOf(contains('ไม่พบเอกสาร'), contains('api1')));
      expect((await call('nebular_project_info', {'path': '${tmp.path}/missing.nsln'})).$1, isTrue);
      await File('${tmp.path}/notes.txt').writeAsString('secret');
      final (e3, m3) = await call('nebular_project_info', {'path': '${tmp.path}/notes.txt'});
      expect(e3, isTrue, reason: 'ไม่ให้ใช้เครื่องมืออ่านไฟล์ที่ไม่ใช่โปรเจกต์');
      expect(m3, isNot(contains('secret')));
      expect((await call('nebular_export', {'path': project, 'format': 'pdf'})).$1, isTrue);
      expect((await call('nebular_codegen_preview', {'path': project, 'targets': ['nope']})).$1, isTrue);
    });

    test('อาร์กิวเมนต์ผิดรูป = -32602 ; เครื่องมือที่ไม่มี = -32602', () async {
      expect(((await rpc('tools/call', {'name': 'nebular_project_info', 'arguments': {}}))['error'] as Map)['code'], -32602);
      expect(((await rpc('tools/call', {'name': 'nebular_codegen_preview', 'arguments': {'path': project, 'targets': 5}}))['error'] as Map)['code'], -32602);
      expect(((await rpc('tools/call', {'name': 'nebular_nope', 'arguments': {}}))['error'] as Map)['code'], -32602);
      expect(((await rpc('tools/call', {'arguments': {}}))['error'] as Map)['code'], -32602);
    });

    test('เครื่องมืออ่านอย่างเดียวไม่แตะไฟล์โปรเจกต์', () async {
      final before = File(project).readAsBytesSync();
      for (final (t, a) in <(String, Map<String, Object?>)>[
        ('nebular_project_info', {}),
        ('nebular_list_documents', {}),
        ('nebular_read_document', {'document': 'api1'}),
        ('nebular_validate', {}),
        ('nebular_export', {'format': 'html'}),
        ('nebular_list_codegen_targets', {}),
        ('nebular_codegen_preview', {'targets': ['all']}),
        ('nebular_codegen_write', {'targets': ['all'], 'out_dir': '${tmp.path}/g'}),
      ]) {
        await call(t, {'path': project, ...a});
      }
      expect(File(project).readAsBytesSync(), before);
    });
  });

  group('stdio', () {
    test('อ่านทีละบรรทัด ตอบทีละบรรทัดตามลำดับ ; บรรทัดว่างข้าม ; JSON เสีย = -32700 แล้วทำงานต่อ ; จบเมื่อ input ปิด', () async {
      final input = StreamController<List<int>>();
      final lines = <String>[];
      final done = runMcpStdio(input.stream, lines.add);
      void send(String s) => input.add(utf8.encode('$s\n'));
      send('{"jsonrpc":"2.0","id":1,"method":"ping"}');
      send('');
      send('{ไม่ใช่ json');
      send('{"jsonrpc":"2.0","method":"notifications/initialized"}');
      send(jsonEncode({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call', 'params': {'name': 'nebular_project_info', 'arguments': {'path': project}}}));
      await input.close();
      await done;
      final replies = [for (final l in lines) jsonDecode(l) as Map];
      expect(replies.length, 3);
      expect(replies[0]['id'], 1);
      expect((replies[1]['error'] as Map)['code'], -32700);
      expect(replies[2]['id'], 2);
      expect(lines.every((l) => !l.contains('\n')), isTrue, reason: 'หนึ่งข้อความต่อหนึ่งบรรทัด');
    });

    test('ข้อความที่มีภาษาไทยและตัวอักษรหลายไบต์ไม่เพี้ยนผ่านการแบ่ง chunk กลางตัวอักษร', () async {
      final input = StreamController<List<int>>();
      final lines = <String>[];
      final done = runMcpStdio(input.stream, lines.add);
      final bytes = utf8.encode('${jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call', 'params': {'name': 'nebular_read_document', 'arguments': {'path': project, 'document': 'ไม่มีเอกสารนี้ 🙂'}}})}\n');
      for (var i = 0; i < bytes.length; i += 7) {
        input.add(bytes.sublist(i, i + 7 > bytes.length ? bytes.length : i + 7));
      }
      await input.close();
      await done;
      final text = (((jsonDecode(lines.single) as Map)['result'] as Map)['content'] as List).single['text'] as String;
      expect(text, contains('ไม่มีเอกสารนี้ 🙂'));
    });
  });

  group('โปรเซสจริง (dart run bin/nebular_mcp.dart ผ่าน stdio)', () {
    test('เริ่มโปรเซส → initialize → tools/list → tools/call → ปิด stdin แล้วโปรเซสจบเอง ; stdout มีแต่ JSON ทีละบรรทัด', () async {
      final ProcessResult probe;
      try {
        probe = await Process.run('dart', ['--version'], runInShell: true);
      } on ProcessException {
        markTestSkipped('ไม่พบคำสั่ง dart ใน PATH');
        return;
      }
      if (probe.exitCode != 0) {
        markTestSkipped('dart ใช้ไม่ได้');
        return;
      }
      final proc = await Process.start('dart', ['run', 'bin/nebular_mcp.dart'], workingDirectory: Directory.current.path, runInShell: true);
      addTearDown(proc.kill);
      final out = proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).toList();
      final err = proc.stderr.transform(utf8.decoder).join();
      void send(Object m) => proc.stdin.writeln(jsonEncode(m));
      send({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2025-06-18', 'capabilities': {}, 'clientInfo': {'name': 't', 'version': '1'}}});
      send({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
      send({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'});
      send({'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call', 'params': {'name': 'nebular_validate', 'arguments': {'path': project, 'language': 'en'}}});
      send({'jsonrpc': '2.0', 'id': 4, 'method': 'tools/call', 'params': {'name': 'nebular_read_document', 'arguments': {'path': project, 'document': 'ไม่มีเอกสารนี้ 🙂'}}});
      await proc.stdin.close();
      final code = await proc.exitCode.timeout(const Duration(seconds: 90));
      final lines = await out;
      await err;
      expect(code, 0);
      final replies = [for (final l in lines) jsonDecode(l) as Map]; // ทุกบรรทัดต้องเป็น JSON (ไม่มีข้อความอื่นปน stdout)
      expect(replies.map((r) => r['id']), [1, 2, 3, 4]);
      expect(((replies[0]['result'] as Map)['serverInfo'] as Map)['name'], 'nebular');
      expect(((replies[1]['result'] as Map)['tools'] as List).length, 9);
      final text = ((((replies[2]['result'] as Map)['content']) as List).single as Map)['text'] as String;
      expect((jsonDecode(text) as Map)['errors'], 0);
      // ภาษาไทยและอีโมจิออกทาง stdout เป็น UTF-8 ที่อ่านกลับได้ครบ
      final thai = ((((replies[3]['result'] as Map)['content']) as List).single as Map)['text'] as String;
      expect(thai, contains('ไม่พบเอกสาร "ไม่มีเอกสารนี้ 🙂"'));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
