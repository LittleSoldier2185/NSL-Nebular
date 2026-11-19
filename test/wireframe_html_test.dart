import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/codegen/wireframe_code.dart';
import 'package:nsl_nebular/core/models/api_model.dart';
import 'package:nsl_nebular/core/models/api_ref.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/enums.dart';
import 'package:nsl_nebular/core/models/project.dart';
import 'package:nsl_nebular/core/models/relation_model.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';

/// HTML จาก Wireframe ต้องตรงกับแบบ: วางตามตำแหน่งจริง ซ้อนในภาชนะ ซ่อน/หมุนตามแบบ สีตามรูปแบบ และใช้ข้อมูลตั้งต้นของ ER
void main() {
  ColumnModel col(String t, String n, {bool pk = false, String comment = ''}) =>
      ColumnModel(id: '${t}_$n', name: n, type: pk ? DataType.integer : DataType.varchar, isPrimaryKey: pk, comment: comment);

  Workspace ws() {
    final er = Project(name: 'Lib', dialect: Dialect.postgres)
      ..tables.addAll([
        TableModel(id: 'categories', name: 'categories', comment: 'หมวดหนังสือ', columns: [
          col('categories', 'id', pk: true),
          col('categories', 'name'),
        ], seedRows: [
          {'categories_id': '1', 'categories_name': 'นิยาย'},
          {'categories_id': '2', 'categories_name': 'วิทยาศาสตร์'},
        ]),
        TableModel(id: 'books', name: 'books', columns: [
          col('books', 'id', pk: true),
          col('books', 'isbn'),
          col('books', 'title', comment: 'ชื่อเรื่อง'),
          col('books', 'category_id'),
        ], seedRows: [
          {'books_id': '1', 'books_isbn': '111', 'books_title': 'สี่แผ่นดิน', 'books_category_id': '1'},
          {'books_id': '2', 'books_isbn': '222', 'books_title': 'จักรวาล', 'books_category_id': '2'},
        ]),
      ])
      ..relations.add(RelationModel(
          id: 'fk1', fromTableId: 'books', fromColumnId: 'books_category_id', toTableId: 'categories', toColumnId: 'categories_id'));
    final api = ApiDocument(endpoints: [ApiEndpoint(id: 'e_loan', method: ApiMethod.post, path: '/loans', summary: 'ยืม')]);
    return Workspace(name: 'Lib')
      ..documents.addAll([
        ProjectDocument.er(id: 'er', name: 'ER', content: er),
        ProjectDocument.api(id: 'api', name: 'API', content: api),
      ]);
  }

  WfDataRef ref(String t, [String? c]) => WfDataRef(docId: 'er', tableId: t, columnId: c == null ? null : '${t}_$c');

  WireframeDiagram page({WfStyle style = WfStyle.clean}) => WireframeDiagram(device: WfDevice.desktop, style: style, components: [
        WfComponent(id: 'nav', kind: WfKind.navbar, text: 'ห้องสมุด', x: 0, y: 0, w: 1440, h: 64),
        WfComponent(id: 'link', kind: WfKind.link, text: 'หนังสือ', x: 300, y: 20, w: 90, h: 24),
        WfComponent(id: 'cat', kind: WfKind.select, text: 'ทุกหมวด', x: 620, y: 170, w: 220, h: 44, ref: ref('categories', 'name')),
        WfComponent(id: 'tbl', kind: WfKind.table, x: 80, y: 280, w: 1000, h: 200, columns: ['ISBN', 'ชื่อเรื่อง', 'หมวด'], rows: 3, ref: ref('books')),
        WfComponent(id: 'btn', kind: WfKind.button, text: 'ยืม', x: 940, y: 500, w: 140, h: 44)..api = const ApiRef(docId: 'api', endpointId: 'e_loan'),
        WfComponent(id: 'badge', kind: WfKind.badge, text: 'ใหม่', x: 1120, y: 100, w: 120, h: 36, rotation: -6),
        WfComponent(id: 'card', kind: WfKind.card, text: 'สถิติ', x: 1120, y: 280, w: 260, h: 200),
        WfComponent(id: 'skel', kind: WfKind.skeleton, x: 1140, y: 410, w: 220, h: 50, hidden: true),
      ]);

  test('ชิ้นในภาชนะซ้อนอยู่ข้างใน และใช้พิกัดสัมพัทธ์กับภาชนะ ; ชิ้นนอกภาชนะใช้พิกัดหน้าจอ', () {
    final html = htmlTailwindScreen('Books', page(), workspace: ws());
    final header = html.indexOf('<header'), headerEnd = html.indexOf('</header>');
    final link = html.indexOf('data-wf="link"');
    expect(link, greaterThan(header));
    expect(link, lessThan(headerEnd), reason: 'ลิงก์อยู่ใน navbar');
    expect(html, contains('style="left:300px;top:20px;width:90px;height:24px;'));
    // skeleton อยู่ใน card → พิกัดสัมพัทธ์ (1140-1120, 410-280)
    expect(html, contains('style="left:20px;top:130px;width:220px;height:50px;'));
    expect(html, contains('style="left:620px;top:170px;width:220px;height:44px;'));
    expect(html, contains('width:1440px;height:900px'));
  });

  test('ซ่อน = hidden ; หมุน = transform ; endpoint/ผูกข้อมูลอยู่ใน data-api / data-bind', () {
    final html = htmlTailwindScreen('Books', page(), workspace: ws());
    expect(RegExp(r'data-wf="skel"[^>]* hidden').hasMatch(html), isTrue);
    expect(html, contains('transform:rotate(354deg)'));
    expect(html, contains('data-api="POST /loans"'));
    expect(html, contains('data-bind="categories.name"'));
    expect(html, contains('data-bind="books"'));
  });

  test('ข้อมูลตั้งต้นของ ER: ตัวเลือกใน select และแถวในตาราง (จับหัวคอลัมน์ด้วยชื่อ/คำอธิบาย/FK)', () {
    final html = htmlTailwindScreen('Books', page(), workspace: ws());
    expect(html, contains('<option>ทุกหมวด</option><option>นิยาย</option><option>วิทยาศาสตร์</option>'));
    expect(html, contains('<td>111</td><td>สี่แผ่นดิน</td><td>นิยาย</td>'), reason: 'หมวด = ชื่อหมวดผ่าน FK');
    expect(html, contains('<td>222</td><td>จักรวาล</td><td>วิทยาศาสตร์</td>'));
    // แถวที่ 3 ไม่มีข้อมูล = แถบเทาแบบบนแคนวาส
    expect('wf-bar'.allMatches(html).length, greaterThan(2));
  });

  test('ไม่มี workspace: ยังสร้างได้ (ไม่มีข้อมูลตั้งต้น) ; รูปแบบร่างใช้ฟอนต์ลายมือและสีเทา', () {
    final clean = htmlTailwindScreen('Books', page());
    expect(clean, contains('<option>ทุกหมวด</option></select>'));
    expect(clean, contains('Noto+Sans+Thai'));
    final sk = htmlTailwindScreen('Books', page(style: WfStyle.sketch));
    expect(sk, contains('family=Itim'));
    expect(sk, contains('class="wf-sketch"'));
    expect(sk, contains('--wf-accent: #4A4A4A'));
  });

  test('ข้อความพิเศษถูก escape ; วงเล็บแท็กสมดุลทุกชนิด', () {
    for (final k in WfKind.values) {
      final d = WireframeDiagram(components: [WfComponent(id: 'x', kind: k, text: '<b>"a" & b</b>', x: 10, y: 10, w: 200, h: 120)]);
      final html = htmlTailwindScreen('T', d);
      expect(html.contains('<b>"a"'), isFalse, reason: k.name);
      expect('<div'.allMatches(html).length, '</div>'.allMatches(html).length, reason: '${k.name} div');
      expect('<span'.allMatches(html).length, '</span>'.allMatches(html).length, reason: '${k.name} span');
    }
  });
}
