import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/ddl/ddl_generator.dart';
import 'package:nsl_nebular/core/models/check_model.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/enums.dart';
import 'package:nsl_nebular/core/models/project.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/parser/sql_importer.dart';

import 'migration_fixtures.dart';

/// Phase 19 ชั้นที่ 1–3: ตัวแบบ/ไฟล์ · DDL 4 dialect · นำเข้า .sql (ค่าที่อนุญาต + CHECK)
void main() {
  Project bookings([Dialect d = Dialect.mysql]) => Project(name: 'hotel', dialect: d, tables: [
        TableModel(id: 'tb', name: 'bookings', columns: [
          col('b1', 'id', pk: true, ai: true, type: DataType.bigint),
          col('b2', 'check_in', type: DataType.date, nn: true),
          col('b3', 'check_out', type: DataType.date, nn: true),
          ColumnModel(
            id: 'b4',
            name: 'status',
            type: DataType.varchar,
            length: 20,
            notNull: true,
            defaultValue: 'pending',
            allowedValues: ['pending', 'confirmed', 'cancelled'],
          ),
          col('b5', 'total', type: DataType.decimal, len: 10, scale: 2),
        ], checks: [
          CheckModel(id: 'k1', name: 'chk_bookings_dates', expr: 'check_out > check_in'),
          CheckModel(id: 'k2', name: 'chk_bookings_total', expr: 'total >= 0'),
        ]),
      ]);

  String ddl(Project p) => DdlGenerator.forDialect(p.dialect).generate(p);

  group('ตัวแบบ / ไฟล์', () {
    test('ไม่ตั้งค่า = ไม่เขียนลงไฟล์ (ไฟล์เก่าเหมือนเดิมทุกตัวอักษร)', () {
      final p = base();
      final j = jsonEncode(p.toJson());
      expect(j.contains('allowed'), isFalse);
      expect(j.contains('checks'), isFalse);
    });

    test('เขียน-อ่านครบ ทั้งค่าที่อนุญาตและ CHECK', () {
      final p = Project.fromJson(jsonDecode(jsonEncode(bookings().toJson())) as Map<String, dynamic>);
      final t = p.tables.single;
      expect(t.columnById('b4')!.allowedValues, ['pending', 'confirmed', 'cancelled']);
      expect(t.checks.map((k) => (k.name, k.expr)), [('chk_bookings_dates', 'check_out > check_in'), ('chk_bookings_total', 'total >= 0')]);
    });

    test('ข้อมูลเสียถูกข้าม ไม่พังทั้งไฟล์', () {
      final j = bookings().tables.single.toJson();
      (j['columns'] as List)[3]['allowed'] = ['ok', 7, null, 'fine'];
      j['checks'] = ['junk', {'id': 1}, {'id': 'x', 'name': 'n', 'expr': 'a > 0'}, 5];
      final t = TableModel.fromJson(j);
      expect(t.columnById('b4')!.allowedValues, ['ok', 'fine']);
      expect(t.checks.single.expr, 'a > 0');
      final j2 = bookings().tables.single.toJson()..['checks'] = 'not a list';
      expect(TableModel.fromJson(j2).checks, isEmpty);
    });

    test('copy / ทำสำเนาผ่าน JSON คงค่าไว้', () {
      final c = bookings().tables.single.columnById('b4')!.copy();
      expect(c.allowedValues, ['pending', 'confirmed', 'cancelled']);
      c.allowedValues.add('x');
      expect(bookings().tables.single.columnById('b4')!.allowedValues.length, 3, reason: 'สำเนาไม่แชร์ลิสต์');
    });

    test('รองรับเฉพาะ varchar/text ; ชนิดอื่นที่มีค่าอยู่ = ไม่นับ (hasAllowedValues เท็จ)', () {
      expect(ColumnModel.supportsAllowedValues(DataType.varchar), isTrue);
      expect(ColumnModel.supportsAllowedValues(DataType.text), isTrue);
      expect(ColumnModel.supportsAllowedValues(DataType.integer), isFalse);
      final c = ColumnModel(id: 'x', name: 'n', type: DataType.integer, allowedValues: ['1']);
      expect(c.hasAllowedValues, isFalse);
    });
  });

  group('DDL 4 dialect', () {
    test('MySQL/MariaDB: ชนิด ENUM(...) ; CHECK ระดับตารางมีชื่อ', () {
      final s = ddl(bookings());
      expect(s, contains("`status` ENUM('pending', 'confirmed', 'cancelled') NOT NULL DEFAULT 'pending'"));
      expect(s, contains('CONSTRAINT `chk_bookings_dates` CHECK (check_out > check_in)'));
      expect(s, contains('CONSTRAINT `chk_bookings_total` CHECK (total >= 0)'));
      expect(s, isNot(contains('VARCHAR(20) NOT NULL DEFAULT')), reason: 'ENUM แทนชนิด varchar');
      expect(s, isNot(contains('chk_bookings_status')), reason: 'MySQL ไม่ใช้ CHECK IN');
    });

    test('PostgreSQL / SQLite / SQL Server: varchar + CONSTRAINT ชื่อ CHECK (col IN (...)) ต่อท้ายคอลัมน์', () {
      final pg = ddl(bookings(Dialect.postgres));
      expect(pg, contains('"status" VARCHAR(20) NOT NULL DEFAULT \'pending\' CONSTRAINT "chk_bookings_status" CHECK ("status" IN (\'pending\', \'confirmed\', \'cancelled\'))'));
      expect(pg, contains('CONSTRAINT "chk_bookings_dates" CHECK (check_out > check_in)'));
      final lite = ddl(bookings(Dialect.sqlite));
      expect(lite, contains('CONSTRAINT "chk_bookings_status" CHECK ("status" IN'));
      final ms = ddl(bookings(Dialect.mssql));
      expect(ms, contains('[status]'));
      expect(ms, contains('CONSTRAINT [chk_bookings_status] CHECK ([status] IN (\'pending\', \'confirmed\', \'cancelled\'))'));
      expect(ms, contains('CONSTRAINT [chk_bookings_dates] CHECK (check_out > check_in)'));
    });

    test('ค่าที่มี \' นำหน้า/ภายใน ถูก escape ตาม dialect ; MySQL escape \\ ด้วย', () {
      final p = bookings();
      p.tables.single.columnById('b4')!.allowedValues = ["O'Brien", r'a\b'];
      p.tables.single.columnById('b4')!.defaultValue = null;
      expect(ddl(p), contains(r"ENUM('O''Brien', 'a\\b')"));
      final pg = bookings(Dialect.postgres);
      pg.tables.single.columnById('b4')!.allowedValues = ["O'Brien"];
      expect(ddl(pg), contains("IN ('O''Brien')"));
    });

    test('ชนิดที่ไม่รองรับ / รายการว่าง = ไม่สร้าง ENUM/CHECK ; นิพจน์ว่าง = ข้าม ; ชื่อว่าง = สร้างชื่อให้ ; หลายบรรทัด = บรรทัดเดียว', () {
      final p = bookings();
      final t = p.tables.single;
      t.columnById('b4')!.type = DataType.integer;
      t.columnById('b4')!.defaultValue = null;
      t.checks
        ..clear()
        ..addAll([
          CheckModel(id: 'a', name: '  ', expr: 'total   >=\n 0'),
          CheckModel(id: 'b', name: 'ignored', expr: '   '),
        ]);
      final s = ddl(p);
      expect(s, isNot(contains('ENUM')));
      expect(s, contains('CONSTRAINT `chk_bookings_1` CHECK (total >= 0)'));
      expect(s, isNot(contains('ignored')));
      final pg = bookings(Dialect.postgres)..tables.single.columnById('b4')!.type = DataType.integer;
      expect(ddl(pg), isNot(contains('chk_bookings_status')));
    });

    test('ไม่มีค่า/CHECK = ผลเหมือนเดิมทุกตัวอักษร (ไม่กระทบตารางเดิม)', () {
      final p = base();
      expect(ddl(p).contains('CHECK'), isFalse);
      expect(ddl(p).contains('ENUM'), isFalse);
    });

    test('วงกลับ: สร้าง SQL แล้วนำเข้า ได้ค่าที่อนุญาตและ CHECK เท่าเดิม (ทุก dialect)', () {
      for (final d in Dialect.values) {
        final src = bookings(d);
        final r = importSql(ddl(src), dialect: d);
        final t = r.project.tables.single;
        final st = t.columns.firstWhere((c) => c.name == 'status');
        expect(st.allowedValues, ['pending', 'confirmed', 'cancelled'], reason: d.name);
        // SQLite ไม่มี varchar : ชนิดวนกลับเป็น text (ยังรองรับค่าที่อนุญาต)
        expect(st.type, d == Dialect.sqlite ? DataType.text : DataType.varchar, reason: d.name);
        expect(t.checks.map((k) => k.expr).toSet(), {'check_out > check_in', 'total >= 0'}, reason: d.name);
        expect(t.checks.map((k) => k.name).toSet(), {'chk_bookings_dates', 'chk_bookings_total'}, reason: d.name);
        // ไม่มี CHECK ซ้ำของค่าที่อนุญาต (กลายเป็นค่าที่อนุญาตแล้ว ไม่ใช่ CHECK ระดับตาราง)
        expect(t.checks.length, 2, reason: d.name);
      }
    });
  });

  group('นำเข้า .sql', () {
    test('MySQL ENUM: ค่าที่อนุญาต + ชนิด varchar (ยาวพอ) ; ค่าซ้ำถูกตัด ; ไม่มีบันทึกเตือนชนิดไม่รู้จัก', () {
      final r = importSql("CREATE TABLE t (id INT PRIMARY KEY, s ENUM('a','bb','a','long value here') NOT NULL DEFAULT 'a');", dialect: Dialect.mysql);
      final c = r.project.tables.single.columns.firstWhere((x) => x.name == 's');
      expect(c.allowedValues, ['a', 'bb', 'long value here']);
      expect((c.type, c.length, c.notNull, c.defaultValue), (DataType.varchar, 20, true, 'a'));
      expect(r.notes.where((n) => n.message.contains('ไม่รู้จักชนิด')), isEmpty);
    });

    test('ENUM ค่ายาว = ความยาวขยายเป็น 50/255', () {
      final long = 'x' * 40, longer = 'y' * 100;
      final r = importSql("CREATE TABLE t (a ENUM('$long'), b ENUM('$longer'));", dialect: Dialect.mysql);
      final t = r.project.tables.single;
      expect(t.columns[0].length, 50);
      expect(t.columns[1].length, 255);
    });

    test('CHECK ในคอลัมน์ (มีและไม่มีชื่อ) รูป IN = ค่าที่อนุญาต ; รูปอื่นเก็บเป็น CHECK ตารางตามที่เขียน', () {
      final r = importSql('''
CREATE TABLE t (
  a VARCHAR(10) CHECK (a IN ('x', 'y')),
  b VARCHAR(10) CONSTRAINT chk_b CHECK (b IN ('p', 'q')),
  n INT CONSTRAINT chk_n_pos CHECK (n > 0 AND n < 100)
);''', dialect: Dialect.postgres);
      final t = r.project.tables.single;
      expect(t.columns[0].allowedValues, ['x', 'y']);
      expect(t.columns[1].allowedValues, ['p', 'q']);
      expect(t.columns[2].allowedValues, isEmpty);
      expect(t.checks.single.name, 'chk_n_pos');
      expect(t.checks.single.expr, 'n > 0 AND n < 100');
    });

    test('CHECK ระดับตาราง: ชื่อคงเดิม ; วงเล็บซ้อน/quote ของ SQL Server ถอดออก ; เปรียบเทียบสองคอลัมน์', () {
      final r = importSql('''
CREATE TABLE [dbo].[bk] ([in] DATE, [out] DATE, [st] NVARCHAR(10));
ALTER TABLE [dbo].[bk] ADD CONSTRAINT [chk_dates] CHECK (([out]>[in]));
ALTER TABLE [dbo].[bk] WITH CHECK ADD CONSTRAINT [chk_st] CHECK ([st] IN (N'a', N'b'));
''', dialect: Dialect.mssql);
      final t = r.project.tables.single;
      expect(t.checks.single.name, 'chk_dates');
      expect(t.checks.single.expr, 'out > in');
      expect(t.columns.firstWhere((c) => c.name == 'st').allowedValues, ['a', 'b']);
    });

    test('นิพจน์ซับซ้อนเก็บเป็นนิพจน์ได้ ฟังก์ชันไม่เว้นวรรคก่อนวงเล็บ ; สตริงใส่ quote กลับ', () {
      final r = importSql("CREATE TABLE t (name VARCHAR(50), CONSTRAINT c1 CHECK (LENGTH(name) >= 2 AND name <> 'it''s'));", dialect: Dialect.mysql);
      expect(r.project.tables.single.checks.single.expr, "LENGTH(name) >= 2 AND name <> 'it''s'");
    });

    test('CHECK ที่อ้างคอลัมน์ชนิดจำนวนเต็มด้วย IN = เก็บเป็น CHECK (ไม่ใช่ค่าที่อนุญาต)', () {
      final r = importSql("CREATE TABLE t (n INT, CONSTRAINT c CHECK (n IN ('1','2')));", dialect: Dialect.mysql);
      final t = r.project.tables.single;
      expect(t.columns.single.allowedValues, isEmpty);
      expect(t.checks.single.expr, "n IN ('1', '2')");
    });

    test('นำเข้าซ้ำสองครั้งไม่ทำ CHECK ซ้ำ', () {
      final sql = 'CREATE TABLE t (a INT, b INT, CONSTRAINT c CHECK (a < b), CONSTRAINT c2 CHECK (a < b));';
      expect(importSql(sql, dialect: Dialect.postgres).project.tables.single.checks.length, 1);
    });
  });
}
