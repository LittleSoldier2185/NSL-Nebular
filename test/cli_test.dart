import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/cli/nebular_api.dart';
import 'package:nsl_nebular/cli/nebular_cli.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/api_model.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/enums.dart';
import 'package:nsl_nebular/core/models/project.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/core/storage/project_file.dart';
import 'package:nsl_nebular/core/validate/issue.dart';

/// โปรเจกต์ตัวอย่าง: ER (orders มี seed, logs ไม่มี PK) + API + Wireframe
Workspace sampleWorkspace({bool broken = false}) {
  final p = Project(name: 'Shop');
  p.tables.addAll([
    TableModel(id: 'o', name: 'orders', columns: [
      ColumnModel(id: 'o1', name: 'id', isPrimaryKey: true, autoIncrement: true),
      ColumnModel(id: 'o2', name: 'customer', type: DataType.varchar, length: 50, notNull: true),
    ], seedRows: [
      {'o2': 'ann'},
    ]),
    TableModel(id: 'l', name: 'logs', columns: [ColumnModel(id: 'l1', name: 'msg', type: DataType.text)]),
    if (broken) TableModel(id: 'o_dup', name: 'orders', columns: [ColumnModel(id: 'd1', name: 'id', isPrimaryKey: true)]),
  ]);
  final w = Workspace.single(p);
  w.documents.add(ProjectDocument.api(
    id: 'api1',
    name: 'Shop API',
    content: ApiDocument(title: 'Shop', endpoints: [
      ApiEndpoint(id: 'e1', path: '/orders', table: ApiTableRef(docId: w.documents.first.id, tableId: 'o'), responses: [ApiResponse(status: 200)]),
    ]),
  ));
  w.documents.add(ProjectDocument.wireframe(
    id: 'wf1',
    name: 'Home',
    content: WireframeDiagram(components: [WfComponent(id: 'b', kind: WfKind.button, text: 'OK', x: 10, y: 10)]),
  ));
  return w;
}

Future<String> writeProject(Directory dir, {bool broken = false, String name = 'shop.nsln'}) async {
  final path = '${dir.path}/$name';
  await File(path).writeAsString(ProjectFile.encode(sampleWorkspace(broken: broken)));
  return path;
}

void main() {
  late Directory tmp;
  late String project;

  setUp(() async {
    currentLang = Lang.th;
    tmp = await Directory.systemTemp.createTemp('nebular_cli_');
    project = await writeProject(tmp);
  });
  tearDown(() async {
    currentLang = Lang.th;
    await tmp.delete(recursive: true);
  });

  Future<({int code, String out, String err})> run(List<String> args) async {
    final o = StringBuffer(), e = StringBuffer();
    final code = await runCli(args, out: o, err: e);
    return (code: code, out: o.toString(), err: e.toString());
  }

  group('แกน: โหลดและอ่าน', () {
    test('โหลดไฟล์ได้ ; ปฏิเสธสกุลที่ไม่ใช่โปรเจกต์ ไฟล์ที่ไม่มี และ JSON เสีย ; สกุลเก่า (.nsld) ยังเปิดได้', () async {
      final w = await loadProject(project);
      expect(w.documents.length, 3);

      await File('${tmp.path}/secret.txt').writeAsString('x');
      await expectLater(loadProject('${tmp.path}/secret.txt'), throwsA(isA<NebularError>().having((e) => e.message, 'message', contains('ไม่ใช่ไฟล์โปรเจกต์'))));
      await expectLater(loadProject('${tmp.path}/missing.nsln'), throwsA(isA<NebularError>().having((e) => e.message, 'message', contains('ไม่พบไฟล์'))));
      await File('${tmp.path}/bad.nsln').writeAsString('{ไม่ใช่ json');
      await expectLater(loadProject('${tmp.path}/bad.nsln'), throwsA(isA<NebularError>().having((e) => e.message, 'message', contains('อ่านไฟล์โปรเจกต์ไม่ได้'))));
      await File('${tmp.path}/notproject.nsln').writeAsString('[1,2]');
      await expectLater(loadProject('${tmp.path}/notproject.nsln'), throwsA(isA<NebularError>()));

      final legacy = await loadProject('test/fixtures/v2_er_dfd.nsld');
      expect(legacy.documents, isNotEmpty);
    });

    test('info: จำนวนเอกสาร/ตาราง/endpoint/ปัญหา', () async {
      final i = projectInfo(await loadProject(project), path: project);
      expect(i['name'], 'Shop');
      expect(i['documents'], 3);
      expect(i['documentsByType'], {'er': 1, 'api': 1, 'wireframe': 1});
      expect(i['tables'], 2);
      expect(i['endpoints'], 1);
      expect(i['wireframeComponents'], 1);
      expect((i['issues'] as Map)['warnings'], greaterThanOrEqualTo(1));
    });

    test('รายการเอกสาร ; หาเอกสารจาก id / ชื่อ (ไม่สนตัวพิมพ์) ; ไม่เจอ = บอกเอกสารที่มี ; ชื่อซ้ำ = ให้ใช้ id', () async {
      final w = await loadProject(project);
      expect([for (final d in listDocuments(w)) d['id']], [w.documents.first.id, 'api1', 'wf1']);
      expect(findDocument(w, 'wf1').name, 'Home');
      expect(findDocument(w, 'shop api').id, 'api1');
      expect(() => findDocument(w, 'nope'), throwsA(isA<NebularError>().having((e) => e.message, 'm', allOf(contains('ไม่พบเอกสาร'), contains('api1')))));
      w.documents.add(ProjectDocument.wireframe(id: 'wf2', name: 'home', content: WireframeDiagram()));
      expect(() => findDocument(w, 'HOME'), throwsA(isA<NebularError>().having((e) => e.message, 'm', contains('ซ้ำ'))));
      expect(findDocument(w, 'wf2').id, 'wf2', reason: 'id ตรง ๆ ใช้ได้เสมอ');
    });

    test('อ่านเนื้อหาเอกสารเป็น JSON ตรงกับในไฟล์', () async {
      final w = await loadProject(project);
      final r = readDocument(w, 'api1');
      expect(r['type'], 'api');
      expect(((r['content'] as Map)['endpoints'] as List).single['path'], '/orders');
      final er = readDocument(w, w.documents.first.id);
      expect(((er['content'] as Map)['tables'] as List).length, 2);
    });
  });

  group('แกน: ตรวจ ส่งออก สร้างโค้ด', () {
    test('validate: นับตามระดับ ; กรองตาม min severity ; พบ error เมื่อมีตารางชื่อซ้ำ', () async {
      final ok = validateReport(await loadProject(project));
      expect(ok['errors'], 0);
      expect(ok['warnings'], greaterThanOrEqualTo(1));
      final only = validateReport(await loadProject(project), minSeverity: Severity.warning);
      expect((only['issues'] as List).every((i) => (i as Map)['severity'] != 'info'), isTrue);

      final bad = await writeProject(tmp, broken: true, name: 'bad.nsln');
      final r = validateReport(await loadProject(bad));
      expect(r['errors'], greaterThanOrEqualTo(1));
      expect((r['issues'] as List).first, containsPair('document', isA<String>()));
      expect(() => parseSeverity('fatal'), throwsA(isA<NebularError>()));
    });

    test('ส่งออก 4 รูปแบบ ; รูปแบบไม่รู้จัก/ไม่มีเอกสารที่ต้องใช้ = ข้อผิดพลาดที่อ่านเข้าใจ', () async {
      final w = await loadProject(project);
      expect(exportProject(w, 'markdown'), contains('orders'));
      expect(exportProject(w, 'html'), contains('<html'));
      expect(exportProject(w, 'sql'), contains('CREATE TABLE'));
      final api = jsonDecode(exportProject(w, 'openapi')) as Map;
      expect((api['paths'] as Map).keys, contains('/orders'));
      expect(jsonDecode(exportProject(w, 'openapi', document: 'Shop API')), isA<Map>());
      expect(() => exportProject(w, 'openapi', document: 'Home'), throwsA(isA<NebularError>().having((e) => e.message, 'm', contains('ไม่ใช่เอกสาร API'))));
      expect(() => exportProject(w, 'pdf'), throwsA(isA<NebularError>().having((e) => e.message, 'm', contains('markdown'))));

      final onlyWf = Workspace.single(Project(name: 'x'))..documents.clear();
      onlyWf.documents.add(ProjectDocument.wireframe(id: 'w', name: 'W', content: WireframeDiagram()));
      expect(() => exportProject(onlyWf, 'sql'), throwsA(isA<NebularError>()));
      expect(() => exportProject(onlyWf, 'openapi'), throwsA(isA<NebularError>()));
    });

    test('เป้าหมายสร้างโค้ด: all = เฉพาะที่สร้างได้ ; ชื่อผิด/ว่าง = ข้อผิดพลาด', () async {
      final w = await loadProject(project);
      expect(listTargets(w).length, 12);
      expect(parseTargets(w, ['all']).length, 12);
      expect(parseTargets(w, ['sqlDdl', ' typescript ', '']).map((t) => t.name), ['sqlDdl', 'typescript']);
      expect(() => parseTargets(w, ['nope']), throwsA(isA<NebularError>().having((e) => e.message, 'm', contains('sqlDdl'))));
      expect(() => parseTargets(w, []), throwsA(isA<NebularError>()));
      final empty = Workspace.single(Project(name: 'p'));
      expect(() => parseTargets(empty, ['all']), throwsA(isA<NebularError>().having((e) => e.message, 'm', contains('ยังไม่มีอะไรให้สร้างโค้ด'))));
      final onlyEr = Workspace.single(Project(name: 'p')..tables.add(TableModel(id: 't', name: 't', columns: [ColumnModel(id: 'c', name: 'id', isPrimaryKey: true)])));
      expect(parseTargets(onlyEr, ['all']).every((t) => t.from == DocType.er), isTrue);
    });

    test('สร้างโค้ด: ดูก่อนไม่เขียน ; เขียนแล้วสร้างซ้ำ = ไม่เปลี่ยน ; ไฟล์ที่แก้ด้วยมือไม่ถูกทับ ; overwrite_edited ทับได้', () async {
      final w = await loadProject(project);
      final out = '${tmp.path}/out';
      final targets = parseTargets(w, ['sqlDdl', 'typescript']);

      final preview = codegenPreview(w, targets);
      expect((preview['files'] as List).map((f) => (f as Map)['path']), containsAll(['database/schema.sql', 'types/models.ts']));
      expect(Directory(out).existsSync(), isFalse, reason: 'ดูอย่างเดียวไม่เขียน');

      final first = await codegenWrite(w, targets, out);
      expect(first['written'], 2);
      expect(first['created'], hasLength(2));
      final sql = File('$out/database/schema.sql');
      expect(sql.readAsStringSync(), contains('CREATE TABLE'));

      final again = await codegenWrite(w, targets, out);
      expect(again['written'], 0);
      expect(again['unchanged'], hasLength(2));

      sql.writeAsStringSync('-- แก้ด้วยมือ\n');
      final guarded = await codegenWrite(w, targets, out);
      expect(guarded['skippedEditedByHand'], ['database/schema.sql']);
      expect(sql.readAsStringSync(), '-- แก้ด้วยมือ\n', reason: 'ไม่ถูกทับ');

      final forced = await codegenWrite(w, targets, out, overwriteEdited: true);
      expect(forced['skippedEditedByHand'], isEmpty);
      expect(sql.readAsStringSync(), contains('CREATE TABLE'));
    });
  });

  group('CLI', () {
    test('ไม่ใส่คำสั่ง = วิธีใช้ (รหัส 2) ; help/version = 0', () async {
      final none = await run([]);
      expect(none.code, 2);
      expect(none.out, contains('nebular <คำสั่ง>'));
      expect((await run(['help'])).code, 0);
      final v = await run(['version']);
      expect(v.code, 0);
      expect(v.out, contains('NSL Nebular'));
    });

    test('คำสั่ง/ตัวเลือกที่ไม่รู้จัก, ขาดไฟล์, ขาดค่า = ข้อความผิดพลาดที่ stderr รหัส 2', () async {
      expect((await run(['bogus', project])).err, contains('ไม่รู้จักคำสั่ง'));
      expect((await run(['info'])).err, contains('ต้องระบุไฟล์'));
      expect((await run(['info', project, '--nope'])).err, contains('ไม่รู้จักตัวเลือก'));
      expect((await run(['export', project])).err, contains('--format'));
      expect((await run(['export', project, '--format'])).err, contains('ต้องมีค่า'));
      expect((await run(['show', project])).err, contains('ต้องระบุเอกสาร'));
      expect((await run(['codegen', project, '--targets', 'sqlDdl'])).err, contains('--out'));
      for (final c in [
        ['bogus', project],
        ['info'],
        ['info', '${tmp.path}/missing.nsln']
      ]) {
        expect((await run(c)).code, 2);
      }
    });

    test('info / docs / show ทั้งแบบข้อความและ --json', () async {
      final info = await run(['info', project]);
      expect(info.code, 0);
      expect(info.out, contains('Shop'));
      expect(info.out, contains('ตาราง 2'));
      expect((jsonDecode((await run(['info', project, '--json'])).out) as Map)['tables'], 2);
      expect((await run(['docs', project])).out, contains('api1\tapi\tShop API'));
      expect(jsonDecode((await run(['docs', project, '--json'])).out), hasLength(3));
      final show = await run(['show', project, 'Home']);
      expect((jsonDecode(show.out) as Map)['type'], 'wireframe');
    });

    test('validate: ไม่มี error = 0 ; มี error = 1 ; --json ; --min-severity ; --lang en เป็นภาษาอังกฤษ', () async {
      final ok = await run(['validate', project]);
      expect(ok.code, 0);
      expect(ok.out, contains('สรุป: error 0'));
      final en = jsonDecode((await run(['validate', project, '--lang=en', '--json'])).out) as Map;
      final msg = ((en['issues'] as List).first as Map)['message'] as String;
      expect(RegExp(r'[฀-๿]').hasMatch(msg), isFalse, reason: msg);

      final bad = await writeProject(tmp, broken: true, name: 'bad.nsln');
      final r = await run(['validate', bad]);
      expect(r.code, 1);
      expect(r.out, contains('[error]'));
      expect((await run(['validate', bad, '--min-severity', 'error', '--json'])).code, 1);
      final onlyErr = jsonDecode((await run(['validate', bad, '--min-severity', 'error', '--json'])).out) as Map;
      expect((onlyErr['issues'] as List).every((i) => (i as Map)['severity'] == 'error'), isTrue);
      expect((await run(['validate', project, '--min-severity', 'fatal'])).code, 2);
    });

    test('export: พิมพ์ออกหน้าจอ หรือเขียนลงไฟล์ด้วย --out (สร้างโฟลเดอร์ให้)', () async {
      final sql = await run(['export', project, '--format', 'sql']);
      expect(sql.code, 0);
      expect(sql.out, contains('CREATE TABLE'));
      final to = '${tmp.path}/deep/dir/api.json';
      final w = await run(['export', project, '--format=openapi', '--out', to]);
      expect(w.code, 0);
      expect(w.out, contains('เขียนแล้ว'));
      expect(jsonDecode(File(to).readAsStringSync()), isA<Map>());
      expect((await run(['export', project, '--format', 'pdf'])).code, 2);
    });

    test('targets / codegen: --dry-run ไม่เขียน ; เขียนจริง ; แก้ด้วยมือถูกข้ามและรายงาน ; --overwrite-edited', () async {
      expect((await run(['targets'])).out, contains('laravelMigration'));
      expect((await run(['targets', project])).out, contains('✓ sqlDdl'));
      expect(jsonDecode((await run(['targets', project, '--json'])).out), hasLength(12));

      final out = '${tmp.path}/gen';
      final dry = await run(['codegen', project, '--targets', 'sqlDdl,openApi', '--out', out, '--dry-run']);
      expect(dry.code, 0);
      expect(dry.out, contains('ยังไม่ได้เขียน'));
      expect(Directory(out).existsSync(), isFalse);

      final real = await run(['codegen', project, '--targets', 'all', '--out', out]);
      expect(real.code, 0);
      expect(real.out, contains('+ database/schema.sql'));
      expect(File('$out/database/schema.sql').existsSync(), isTrue);

      File('$out/database/schema.sql').writeAsStringSync('hand');
      final skip = await run(['codegen', project, '--targets', 'all', '--out', out]);
      expect(skip.out, contains('ข้าม (ถูกแก้ด้วยมือ) database/schema.sql'));
      expect(File('$out/database/schema.sql').readAsStringSync(), 'hand');
      await run(['codegen', project, '--targets', 'all', '--out', out, '--overwrite-edited']);
      expect(File('$out/database/schema.sql').readAsStringSync(), contains('CREATE TABLE'));
    });

    test('ทุกคำสั่งไม่แตะไฟล์โปรเจกต์ (อ่านอย่างเดียว) — เนื้อหาและเวลาแก้ไขเดิมทุกไบต์', () async {
      final before = File(project).readAsBytesSync();
      final mtime = File(project).lastModifiedSync();
      for (final c in [
        ['info', project],
        ['docs', project],
        ['show', project, 'api1'],
        ['validate', project],
        ['export', project, '--format', 'html'],
        ['codegen', project, '--targets', 'all', '--out', '${tmp.path}/x'],
        ['targets', project],
      ]) {
        await run(c);
      }
      expect(File(project).readAsBytesSync(), before);
      expect(File(project).lastModifiedSync(), mtime);
      expect(File('$project.tmp').existsSync(), isFalse);
    });
  });
}
