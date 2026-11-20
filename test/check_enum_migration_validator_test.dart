import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/diff/merge3.dart';
import 'package:nsl_nebular/core/diff/migration.dart';
import 'package:nsl_nebular/core/diff/schema_diff.dart';
import 'package:nsl_nebular/core/export/seed_data.dart';
import 'package:nsl_nebular/core/models/check_model.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/enums.dart';
import 'package:nsl_nebular/core/models/project.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/validate/validator.dart';

import 'migration_fixtures.dart';

/// Phase 19 ชั้นที่ 4–5: เทียบ/Migration · ตัวตรวจ ER · ตรวจข้อมูลตั้งต้น
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
        ]),
      ]);

  /// โปรเจกต์เดิม (clone) + แก้ด้วย [edit]
  (Project, Project) pair(Dialect d, void Function(TableModel t) edit) {
    final old = bookings(d);
    final neu = clone(bookings(d));
    edit(neu.tables.single);
    return (old, neu);
  }

  String mig(Dialect d, void Function(TableModel t) edit) {
    final (o, n) = pair(d, edit);
    return generateMigration(o, n);
  }

  ColumnModel st(TableModel t) => t.columnById('b4')!;

  group('เทียบ (SchemaDiff)', () {
    test('ไม่เปลี่ยน = ไม่มีความต่าง', () {
      final (o, n) = pair(Dialect.mysql, (_) {});
      expect(diffProjects(o, n).isEmpty, isTrue);
    });

    test('ค่าที่อนุญาตเปลี่ยน (เพิ่ม/ลบ/เรียงใหม่) = คอลัมน์เปลี่ยน และบรรทัดสรุปบอกค่าเดิม-ใหม่', () {
      for (final edit in <void Function(TableModel)>[
        (t) => st(t).allowedValues.add('completed'),
        (t) => st(t).allowedValues.remove('cancelled'),
        (t) => st(t).allowedValues = ['confirmed', 'pending', 'cancelled'],
      ]) {
        final (o, n) = pair(Dialect.mysql, edit);
        final d = diffProjects(o, n);
        expect(d.modified.single.changedColumns.single.allowedChanged, isTrue);
        expect(d.summary(o, n).map((l) => l.text).join('\n'), contains('ค่าที่อนุญาต'));
      }
    });

    test('เอาค่าออก / เริ่มจำกัดค่า = ติดธงอันตราย ; เพิ่มค่า = ไม่ติด', () {
      var (o, n) = pair(Dialect.mysql, (t) => st(t).allowedValues.remove('cancelled'));
      expect(diffProjects(o, n).summary(o, n).any((l) => l.destructive), isTrue);
      (o, n) = pair(Dialect.mysql, (t) => st(t).allowedValues.add('x'));
      expect(diffProjects(o, n).summary(o, n).any((l) => l.destructive), isFalse);
      (o, n) = (clone(bookings())..tables.single.columnById('b4')!.allowedValues = [], bookings());
      expect(diffProjects(o, n).summary(o, n).any((l) => l.destructive), isTrue);
    });

    test('ชนิดที่ไม่รองรับค่าที่อนุญาต: ค่าที่ค้างอยู่ไม่นับเป็นความต่าง', () {
      final (o, n) = pair(Dialect.mysql, (t) {
        st(t).type = DataType.integer;
        st(t).allowedValues = ['1'];
        st(t).defaultValue = null;
      });
      final d = diffProjects(o, n);
      // ชนิดเปลี่ยนจริง (varchar->integer) แต่ allowedChanged เป็นเพราะค่าเดิมหายไป ไม่ใช่เพราะค่าใหม่
      expect(d.modified.single.changedColumns.single.typeChanged, isTrue);
    });

    test('CHECK ระดับตาราง: เพิ่ม / ลบ / แก้นิพจน์ (= ลบ+เพิ่ม) ; ช่องว่างซ้ำและตัวพิมพ์ชื่อไม่นับ ; นิพจน์ว่างไม่นับ', () {
      var (o, n) = pair(Dialect.mysql, (t) => t.checks.add(CheckModel(id: 'k2', name: 'chk_total', expr: 'total >= 0')));
      var d = diffProjects(o, n).modified.single;
      expect(d.addedChecks.map((k) => k.name), ['chk_total']);
      expect(d.droppedChecks, isEmpty);
      (o, n) = pair(Dialect.mysql, (t) => t.checks.clear());
      d = diffProjects(o, n).modified.single;
      expect(d.droppedChecks.map((k) => k.name), ['chk_bookings_dates']);
      (o, n) = pair(Dialect.mysql, (t) => t.checks.single.expr = 'check_out >= check_in');
      d = diffProjects(o, n).modified.single;
      expect((d.droppedChecks.length, d.addedChecks.length), (1, 1));
      (o, n) = pair(Dialect.mysql, (t) {
        t.checks.single
          ..name = 'CHK_Bookings_Dates'
          ..expr = 'check_out   >\n check_in';
      });
      expect(diffProjects(o, n).isEmpty, isTrue);
      (o, n) = pair(Dialect.mysql, (t) => t.checks.add(CheckModel(id: 'e', name: 'empty', expr: '  ')));
      expect(diffProjects(o, n).isEmpty, isTrue);
    });
  });

  group('Migration', () {
    test('MySQL: เปลี่ยนค่า ENUM = MODIFY COLUMN พร้อมนิยามเต็ม + เตือนเมื่อเอาค่าออก', () {
      final s = mig(Dialect.mysql, (t) => st(t).allowedValues = ['pending', 'confirmed']);
      expect(s, contains("ALTER TABLE `bookings` MODIFY COLUMN `status` ENUM('pending', 'confirmed') NOT NULL DEFAULT 'pending'"));
      expect(s, contains('ค่าที่อนุญาตของ'));
    });

    test('MySQL: เพิ่มค่าอย่างเดียวก็เตือนข้อความเดียวกัน (ไม่ใช่เฉพาะตอนเอาออก — ลำดับ ENUM มีผล)', () {
      final s = mig(Dialect.mysql, (t) => st(t).allowedValues.add('completed'));
      expect(s, contains("ENUM('pending', 'confirmed', 'cancelled', 'completed')"));
    });

    test('PostgreSQL: เริ่มจำกัดค่าในคอลัมน์ที่ไม่เคยจำกัด = ADD CONSTRAINT ชื่อ ; เตือนข้อมูลเดิม', () {
      final old = bookings(Dialect.postgres)..tables.single.columnById('b4')!.allowedValues = [];
      final s = generateMigration(old, bookings(Dialect.postgres));
      expect(s, contains('ALTER TABLE "bookings" ADD CONSTRAINT "chk_bookings_status" CHECK ("status" IN (\'pending\', \'confirmed\', \'cancelled\'));'));
      expect(s, isNot(contains('DROP CONSTRAINT "chk_bookings_status"')));
      expect(s, contains('แถวเดิมที่ไม่ผ่าน CHECK'));
    });

    test('PostgreSQL: เปลี่ยนค่า = DROP แล้ว ADD ตามลำดับ ; เอาข้อจำกัดออก = DROP อย่างเดียว', () {
      var s = mig(Dialect.postgres, (t) => st(t).allowedValues.add('completed'));
      final drop = s.indexOf('DROP CONSTRAINT "chk_bookings_status"');
      final add = s.indexOf('ADD CONSTRAINT "chk_bookings_status"');
      expect(drop, greaterThan(-1));
      expect(add, greaterThan(drop));
      s = mig(Dialect.postgres, (t) {
        st(t).allowedValues = [];
        st(t).defaultValue = 'pending';
      });
      expect(s, contains('DROP CONSTRAINT "chk_bookings_status"'));
      expect(s, isNot(contains('ADD CONSTRAINT "chk_bookings_status"')));
    });

    test('PostgreSQL / SQL Server: เปลี่ยนชื่อคอลัมน์ที่มีค่าที่อนุญาต = ย้ายชื่อ constraint ตาม (ลบชื่อเก่า เพิ่มชื่อใหม่)', () {
      for (final d in [Dialect.postgres, Dialect.mssql]) {
        final s = mig(d, (t) => st(t).name = 'state');
        final q = d == Dialect.mssql ? ('[', ']') : ('"', '"');
        expect(s, contains('DROP CONSTRAINT ${q.$1}chk_bookings_status${q.$2}'), reason: d.name);
        expect(s, contains('ADD CONSTRAINT ${q.$1}chk_bookings_state${q.$2}'), reason: d.name);
      }
    });

    test('SQL Server: ลบคอลัมน์ที่มีค่าที่อนุญาต = DROP CONSTRAINT ก่อน DROP COLUMN', () {
      final s = mig(Dialect.mssql, (t) {
        t.columns.removeWhere((c) => c.id == 'b4');
      });
      final dc = s.indexOf('DROP CONSTRAINT [chk_bookings_status]');
      final col = s.indexOf('DROP COLUMN [status]');
      expect(dc, greaterThan(-1));
      expect(col, greaterThan(dc));
    });

    test('PostgreSQL: ลบคอลัมน์ = ไม่ต้อง DROP CONSTRAINT แยก (ฐานข้อมูลลบให้)', () {
      final s = mig(Dialect.postgres, (t) => t.columns.removeWhere((c) => c.id == 'b4'));
      expect(s, isNot(contains('DROP CONSTRAINT "chk_bookings_status"')));
    });

    test('CHECK ระดับตาราง: เพิ่ม/ลบ/แก้ ต่อ dialect (MySQL ใช้ DROP CHECK ที่อื่น DROP CONSTRAINT)', () {
      var s = mig(Dialect.mysql, (t) => t.checks.add(CheckModel(id: 'k2', name: 'chk_total', expr: 'total >= 0')));
      expect(s, contains('ALTER TABLE `bookings` ADD CONSTRAINT `chk_total` CHECK (total >= 0);'));
      s = mig(Dialect.mysql, (t) => t.checks.clear());
      expect(s, contains('ALTER TABLE `bookings` DROP CHECK `chk_bookings_dates`;'));
      s = mig(Dialect.postgres, (t) => t.checks.single.expr = 'check_out >= check_in');
      expect(s, contains('DROP CONSTRAINT "chk_bookings_dates"'));
      expect(s, contains('ADD CONSTRAINT "chk_bookings_dates" CHECK (check_out >= check_in)'));
      s = mig(Dialect.mssql, (t) => t.checks.clear());
      expect(s, contains('DROP CONSTRAINT [chk_bookings_dates]'));
    });

    test('CHECK ที่ชื่อว่าง ใช้ชื่ออัตโนมัติ chk_<ตาราง>_<ลำดับ> ทั้งตอนสร้างและตอนลบ', () {
      final old = bookings(Dialect.postgres)..tables.single.checks.single.name = '';
      final neu = clone(old)..tables.single.checks.clear();
      expect(generateMigration(old, neu), contains('DROP CONSTRAINT "chk_bookings_1"'));
    });

    test('SQLite: ต้องสร้างตารางใหม่ — CREATE TABLE ใหม่มี CHECK/ค่าที่อนุญาต + เตือน', () {
      var s = mig(Dialect.sqlite, (t) => st(t).allowedValues.add('completed'));
      expect(s, contains('"bookings__new"'));
      expect(s, contains('CONSTRAINT "chk_bookings_status" CHECK ("status" IN (\'pending\', \'confirmed\', \'cancelled\', \'completed\'))'));
      expect(s, contains('CONSTRAINT "chk_bookings_dates" CHECK (check_out > check_in)'));
      expect(s, contains('เงื่อนไข CHECK/ค่าที่อนุญาตใหม่'));
      s = mig(Dialect.sqlite, (t) => t.checks.clear());
      expect(s, contains('"bookings__new"'));
      expect(s, isNot(contains('chk_bookings_dates')), reason: 'ตารางใหม่ไม่มี CHECK แล้ว');
    });

    test('ตารางใหม่ที่มี CHECK/ค่าที่อนุญาต = อยู่ใน CREATE TABLE ครบ', () {
      final old = Project(name: 'x', dialect: Dialect.postgres);
      final s = generateMigration(old, bookings(Dialect.postgres));
      expect(s, contains('chk_bookings_status'));
      expect(s, contains('chk_bookings_dates'));
    });

    test('ไม่เปลี่ยน = ไม่ต้อง migrate', () {
      final (o, n) = pair(Dialect.postgres, (_) {});
      expect(generateMigration(o, n), contains('ไม่มีความแตกต่าง'));
    });
  });

  group('รวม 3 ทาง (merge3)', () {
    test('คนละฝั่งแก้ค่าที่อนุญาตของคนละคอลัมน์ = รวมได้ ; แก้คอลัมน์เดียวกันคนละค่า = ขัดแย้ง', () {
      final base0 = bookings();
      final mine = clone(base0)..tables.single.columnById('b4')!.allowedValues.add('completed');
      final theirs = clone(base0)..tables.single.checks.add(CheckModel(id: 'k9', name: 'chk_total', expr: 'total >= 0'));
      final r = mergeProjects(base: base0, mine: mine, theirs: theirs);
      expect(r.conflicts, isEmpty);
      final t = r.merged.tables.single;
      expect(t.columnById('b4')!.allowedValues, contains('completed'));
      expect(t.checks.map((k) => k.name), containsAll(['chk_bookings_dates', 'chk_total']));

      final a = clone(base0)..tables.single.columnById('b4')!.allowedValues = ['pending', 'x'];
      final b = clone(base0)..tables.single.columnById('b4')!.allowedValues = ['pending', 'y'];
      expect(mergeProjects(base: base0, mine: a, theirs: b).conflicts, isNotEmpty);
    });
  });

  group('ตัวตรวจ ER', () {
    List<String> codes(Project p) => [for (final i in validateProject(p)) i.code];

    test('ตัวอย่างปกติ = ไม่มีปัญหาของค่าที่อนุญาต/CHECK', () {
      final c = codes(bookings());
      for (final k in ['allowed_type', 'allowed_empty', 'allowed_dup', 'default_not_allowed', 'check_empty', 'check_dup_name', 'check_unknown_column']) {
        expect(c, isNot(contains(k)), reason: k);
      }
    });

    test('ค่าที่อนุญาต: ชนิดไม่รองรับ / ค่าว่าง / ซ้ำ / ค่าเริ่มต้นนอกรายการ', () {
      var p = bookings();
      st(p.tables.single).type = DataType.integer;
      expect(codes(p), contains('allowed_type'));
      p = bookings();
      st(p.tables.single).allowedValues = ['a', '  '];
      st(p.tables.single).defaultValue = null;
      expect(codes(p), contains('allowed_empty'));
      p = bookings();
      st(p.tables.single).allowedValues = ['a', 'a'];
      st(p.tables.single).defaultValue = null;
      expect(codes(p), contains('allowed_dup'));
      p = bookings();
      st(p.tables.single).defaultValue = 'refunded';
      expect(codes(p), contains('default_not_allowed'));
      st(p.tables.single).defaultValue = "'pending'"; // มี quote ในค่าเริ่มต้น = ถอดก่อนเทียบ
      expect(codes(p), isNot(contains('default_not_allowed')));
      st(p.tables.single).defaultValue = 'NULL';
      expect(codes(p), isNot(contains('default_not_allowed')));
    });

    test('ค่าที่อนุญาตยาวกว่า VARCHAR(n): แนะนำเฉพาะ MySQL (ที่ใช้ ENUM ไม่กระทบ) ', () {
      final p = bookings();
      st(p.tables.single).length = 5;
      expect(codes(p), contains('allowed_longer_than_length'));
      expect(codes(bookings(Dialect.postgres)..tables.single.columnById('b4')!.length = 5), isNot(contains('allowed_longer_than_length')));
    });

    test('CHECK: นิพจน์ว่าง / ชื่อซ้ำทั้งโปรเจกต์ / อ้างคอลัมน์ที่ไม่มี (ไม่นับสตริง ฟังก์ชัน คำ SQL ตัวเลข)', () {
      var p = bookings();
      p.tables.single.checks.add(CheckModel(id: 'e', name: 'c2', expr: '   '));
      expect(codes(p), contains('check_empty'));
      p = bookings();
      p.tables.add(TableModel(id: 'tx', name: 'other', columns: [col('x1', 'v', pk: true)], checks: [CheckModel(id: 'k5', name: 'CHK_BOOKINGS_DATES', expr: 'v > 0')]));
      expect(codes(p), contains('check_dup_name'));
      p = bookings();
      p.tables.single.checks.add(CheckModel(id: 'u', name: 'c3', expr: "LENGTH(status) > 2 AND status <> 'ghost_col' AND total BETWEEN 0 AND 99 AND missing_col > 0"));
      final unknown = [for (final i in validateProject(p)) if (i.code == 'check_unknown_column') i.message];
      expect(unknown.length, 1);
      expect(unknown.single, contains('missing_col'));
      expect(unknown.single, isNot(contains('ghost_col')));
    });

    test('checkIdentifiers: ข้ามสตริง ฟังก์ชัน คำ SQL และตัวเลข ; เก็บชื่อไทย', () {
      expect(checkIdentifiers("a > b AND c IS NOT NULL"), ['a', 'b', 'c']);
      expect(checkIdentifiers("LENGTH(name) >= 2 AND lower(x) = 'Y'"), ['name', 'x']);
      expect(checkIdentifiers("วันออก > วันเข้า"), ['วันออก', 'วันเข้า']);
      expect(checkIdentifiers("n BETWEEN 1 AND 10"), ['n']);
    });
  });

  group('ข้อมูลตั้งต้น', () {
    Project withSeed(List<Map<String, String?>> rows) {
      final p = bookings();
      p.tables.single.seedRows = rows;
      return p;
    }

    test('ค่านอกรายการ = ปัญหา ; ค่าในรายการ/ว่าง (ใช้ DEFAULT) = ผ่าน', () {
      expect(validateSeed(withSeed([{'b2': '2026-01-01', 'b3': '2026-01-02', 'b4': 'confirmed'}])), isEmpty);
      expect(validateSeed(withSeed([{'b2': '2026-01-01', 'b3': '2026-01-02'}])), isEmpty);
      final bad = validateSeed(withSeed([{'b2': '2026-01-01', 'b3': '2026-01-02', 'b4': 'refunded'}]));
      expect(bad.length, 1);
      expect(bad.single.columnId, 'b4');
      expect(bad.single.key, contains('ค่าที่อนุญาต'));
    });

    test('ตัวสร้าง SQL ข้อมูลตั้งต้นไม่ผ่านเมื่อค่านอกรายการ', () {
      expect(() => generateSeedSql(withSeed([{'b2': '2026-01-01', 'b3': '2026-01-02', 'b4': 'refunded'}])), throwsA(isA<SeedException>()));
    });
  });
}
