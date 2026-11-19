import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/cli/nebular_api.dart';
import 'package:nsl_nebular/core/export/svg_export.dart';
import 'package:nsl_nebular/core/layout/diagram_geometry.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/project.dart';
import 'package:nsl_nebular/core/models/workspace.dart';

/// บั๊กอ่านแผนภาพ ER ผิด (เจอจากการรีวิวภาพ samples/hotel_booking.nsln):
/// 1. คอลัมน์ที่เป็น FK+UQ เห็นแค่ป้าย FK → คนอ่านคิดว่า 1:1 ไม่มี UNIQUE
/// 2. ปลายฝั่งลูกไม่มีวงกลม "ศูนย์" → อ่านเป็น "ต้องมีพอดี 1" แทน "0 หรือ 1"
/// 3. เส้นแนวนอนของสองความสัมพันธ์ทับกันเป๊ะ → ดูเหมือนต่อผิดตาราง
void main() {
  late Project er;

  setUpAll(() async {
    final w = await loadProject('samples/hotel_booking.nsln');
    er = w.documentsOf(DocType.er).single.er!;
  });

  ColumnModel col(String table, String name) =>
      er.tables.firstWhere((t) => t.name == table).columns.firstWhere((c) => c.name == name);

  group('ป้ายคอลัมน์', () {
    test('FK ที่เป็น UNIQUE เห็นทั้ง FK และ UQ', () {
      expect(columnFlags(col('reviews', 'booking_id'), isFk: true), ['FK', 'UQ']);
    });
    test('PK ที่เป็น FK (ตารางเชื่อม) เห็นทั้ง PK และ FK', () {
      expect(columnFlags(col('room_type_amenities', 'amenity_id'), isFk: true), ['PK', 'FK']);
    });
    test('ป้ายเดียวยังเหมือนเดิม และ PK ไม่ขึ้น UQ ซ้ำ', () {
      expect(columnFlags(col('users', 'id'), isFk: false), ['PK']);
      expect(columnFlags(col('users', 'email'), isFk: false), ['UQ']);
      expect(columnFlags(col('payments', 'booking_id'), isFk: true), ['FK']);
      expect(columnFlags(col('users', 'phone'), isFk: false), isEmpty);
      final pkUq = ColumnModel(id: 'x', name: 'x', isPrimaryKey: true, unique: true);
      expect(columnFlags(pkUq, isFk: false), ['PK']);
    });
    test('SVG วาดป้าย UQ ของ reviews.booking_id', () {
      final svg = exportSvg(er)!;
      final reviews = svg.substring(svg.indexOf('>reviews<'));
      final row = reviews.substring(reviews.indexOf('>booking_id<') - 900, reviews.indexOf('>booking_id<'));
      expect(row, contains('>FK<'));
      expect(row, contains('>UQ<'));
    });
  });

  group('ปลายฝั่งลูก', () {
    test('SVG มีวงกลม "ศูนย์" ที่ปลายลูกครบทุกเส้น ห่างจากขอบการ์ดตามชนิด', () {
      final svg = exportSvg(er)!;
      for (final r in er.relations) {
        final g = relationGeometry(er, r)!;
        final cx = g.fx + g.d0 * childZeroOffset(g.oneToOne);
        String n(double v) {
          final t = v.toStringAsFixed(2);
          return t.contains('.') ? t.replaceFirst(RegExp(r'\.?0+$'), '') : t;
        }
        expect(svg, contains('<circle cx="${n(cx)}" cy="${n(g.fy)}" r="4.5"'), reason: r.id);
      }
    });
  });

  group('เส้นไม่ทับกัน', () {
    test('ไม่มีช่วงแนวนอนของสองความสัมพันธ์ทับกันในไฟล์ตัวอย่างโรงแรม', () {
      final routes = relationRoutes(er);
      final ids = routes.keys.toList();
      final clashes = <String>[];
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          if (_hClash(routes[ids[i]]!, routes[ids[j]]!)) clashes.add('${ids[i]} × ${ids[j]}');
        }
      }
      expect(clashes, isEmpty);
    });

    test('เส้นเข้า rooms.id ไม่อยู่ระดับเดียวกับเส้นที่ออกจากแถว room_types.id', () {
      final toRooms = er.relations.firstWhere((r) => r.toTableId == er.tables.firstWhere((t) => t.name == 'rooms').id);
      final route = relationRoutes(er)[toRooms.id]!;
      final g = relationGeometry(er, toRooms)!;
      // ปลายเส้นยังอยู่ภายในแถวของคอลัมน์แม่
      expect((route.last.$2 - g.ty).abs(), lessThanOrEqualTo(12));
      expect(route.last.$1, g.tx);
    });
  });
}

bool _hClash(List<RoutePoint> a, List<RoutePoint> b) {
  for (var s = 1; s < a.length; s++) {
    if ((a[s - 1].$2 - a[s].$2).abs() > 0.001) continue;
    final a0 = math.min(a[s - 1].$1, a[s].$1), a1 = math.max(a[s - 1].$1, a[s].$1);
    for (var u = 1; u < b.length; u++) {
      if ((b[u - 1].$2 - b[u].$2).abs() > 0.001) continue;
      if ((b[u].$2 - a[s].$2).abs() >= kRouteMinSeparation) continue;
      final b0 = math.min(b[u - 1].$1, b[u].$1), b1 = math.max(b[u - 1].$1, b[u].$1);
      if (math.min(a1, b1) - math.max(a0, b0) > -kRouteCollinearGap) return true;
    }
  }
  return false;
}
