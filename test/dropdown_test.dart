import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/ui/widgets.dart';

/// วิดเจ็ต Dropdown ที่ใช้ทั่วแอป : ตัวเลือก null (เช่น "ทุกชนิด" / "ไม่ผูกตาราง") ต้องเลือกได้
/// (เดิมถูกทิ้งเพราะแยกไม่ออกจาก "ไม่ได้เลือก" ทำให้ล้างตัวกรองไม่ได้)
void main() {
  Future<List<String?>> pump(WidgetTester tester, {required String? value, List<String?> items = const [null, 'a', 'b']}) async {
    final picked = <String?>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            child: Dropdown<String?>(
              key: const ValueKey('dd'),
              value: value,
              items: items,
              labelOf: (v) => v == null ? 'ไม่มี' : 'ค่า $v',
              onChanged: picked.add,
            ),
          ),
        ),
      ),
    ));
    return picked;
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('dd')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('เลือกตัวเลือก null ได้ (เรียก onChanged ด้วย null)', (tester) async {
    final picked = await pump(tester, value: 'a');
    await choose(tester, 'ไม่มี');
    expect(picked, [null]);
  });

  testWidgets('เลือกตัวเลือกปกติ ; เลือกตัวเดิมซ้ำก็แจ้ง', (tester) async {
    final picked = await pump(tester, value: null);
    await choose(tester, 'ค่า b');
    expect(picked, ['b']);
    await choose(tester, 'ไม่มี');
    expect(picked, ['b', null]);
  });

  testWidgets('แสดงป้ายของค่าปัจจุบัน รวมกรณี null', (tester) async {
    await pump(tester, value: null);
    expect(find.text('ไม่มี'), findsOneWidget);
    await pump(tester, value: 'b');
    expect(find.text('ค่า b'), findsOneWidget);
  });

  testWidgets('ค่าที่ไม่อยู่ในรายการ = ไม่เลือก ไม่ error (เดิมจะ assert)', (tester) async {
    final picked = await pump(tester, value: 'ไม่มีในรายการ');
    expect(tester.takeException(), isNull);
    await choose(tester, 'ค่า a');
    expect(picked, ['a']);
  });

  testWidgets('รายการเปลี่ยน → เมนูตามรายการใหม่ (ลำดับตรงกับตัวข้อมูลเสมอ)', (tester) async {
    var picked = await pump(tester, value: 'a', items: const ['a', 'b']);
    await pump(tester, value: 'a', items: const ['x', 'a', 'b']);
    picked = await pump(tester, value: 'a', items: const ['x', 'a', 'b']);
    await choose(tester, 'ค่า x');
    expect(picked, ['x']);
  });
}
