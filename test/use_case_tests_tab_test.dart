import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/export/usecase_testcases.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/use_case.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// Phase 32: แท็บ "กรณีทดสอบ" ของหน้า Use Case (แบบ A : ตารางพรีวิว)
void main() {
  late WorkspaceController wc;
  late UseCase a, b;

  Future<void> boot(WidgetTester tester, {Size size = const Size(1600, 950), Lang lang = Lang.th, bool seed = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => currentLang = Lang.th);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang, showExplorer: true)));
    wc = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    if (seed) {
      final r1 = wc.addRequirement(text: 'จอง');
      wc.addRequirement(text: 'ชำระเงิน');
      a = wc.addUseCase(name: 'จองห้อง', actor: 'Guest');
      b = wc.addUseCase(name: 'ชำระเงิน', actor: 'Guest');
      wc.updateUseCase(a.id, (x) {
        x.reqIds.add(r1.id);
        x.preconditions = 'เข้าสู่ระบบแล้ว';
        x.postconditions = 'มีการจอง';
        x.steps.addAll([
          UcStep(id: 's1', text: 'เลือกห้อง'),
          UcStep(id: 's2', who: UcWho.system, text: 'ตรวจห้องว่าง'),
        ]);
        x.branches
          ..add(UcBranch(id: 'b1', atStepId: 's2', condition: 'ห้องเต็ม', outcome: 'เสนอห้องอื่น', returnStepId: 's1'))
          ..add(UcBranch(id: 'b2', atStepId: 's2', exception: true, condition: 'ระบบล่ม', ends: true));
      });
      wc.updateUseCase(b.id, (x) => x.steps.add(UcStep(id: 'p1', text: 'จ่ายเงิน')));
    }
    wc.showUseCases();
    await tester.pumpAndSettle();
    if (seed) {
      await tester.tap(find.byKey(const ValueKey('uc-tab-tests')));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('แท็บกรณีทดสอบ: หัวสรุป (กรณี/ชนิด/ความต้องการ) ตรงกับตัวสร้าง ; ทุกกรณีมีแถว', (tester) async {
    await boot(tester);
    final cases = generateTestCases(wc.workspace);
    expect(cases.length, 4, reason: 'UC-01: หลัก+ทางเลือก+ข้อผิดพลาด (3) ; UC-02: หลัก (1)');
    String t(String k) => tester.widget<Container>(find.byKey(ValueKey(k))).child is Text ? ((tester.widget<Container>(find.byKey(ValueKey(k))).child as Text).data ?? '') : '';
    expect(t('uc-tc-total'), '4 กรณี');
    expect(t('uc-tc-main'), 'หลัก 2');
    expect(t('uc-tc-alt'), 'ทางเลือก 1');
    expect(t('uc-tc-exc'), 'ข้อผิดพลาด 1');
    expect(t('uc-tc-req'), 'ความต้องการที่มีกรณีทดสอบ 1 / 2 ข้อ');
    for (final c in cases) {
      expect(find.byKey(ValueKey('uc-tc-${c.id}')), findsOneWidget, reason: c.id);
    }
    expect(tester.widget<Text>(find.byKey(const ValueKey('uc-tc-footer'))).data, 'แสดง 4 จาก 4 กรณี · กดแถวเพื่อขยายขั้นตอน');
    expect(tester.takeException(), isNull);
  });

  testWidgets('กดแถวขยายขั้นตอน (ผู้ใช้/ระบบ + บรรทัดเงื่อนไข) กดซ้ำพับ ; หลายแถวเปิดพร้อมกันได้', (tester) async {
    await boot(tester);
    final cases = generateTestCases(wc.workspace);
    final alt = cases.firstWhere((c) => c.kind == TcKind.alternative);
    expect(find.text('ที่ขั้นที่ 2 : เมื่อ ห้องเต็ม', findRichText: true), findsNothing, reason: 'พับอยู่');
    await tester.tap(find.byKey(ValueKey('uc-tc-${alt.id}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ที่ขั้นที่ 2 : เมื่อ ห้องเต็ม', findRichText: true), findsOneWidget);
    expect(find.textContaining('กลับไปขั้นที่ 1', findRichText: true), findsWidgets);
    final main = cases.first;
    await tester.tap(find.byKey(ValueKey('uc-tc-${main.id}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('เลือกห้อง', findRichText: true), findsWidgets);
    await tester.tap(find.byKey(ValueKey('uc-tc-${alt.id}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ที่ขั้นที่ 2 : เมื่อ ห้องเต็ม', findRichText: true), findsNothing, reason: 'พับกลับ');
    expect(tester.takeException(), isNull);
  });

  testWidgets('ตัวกรองชนิดและ Use Case : ลดแถว ปรับท้ายตาราง ; ไม่ตรง = บอกว่าไม่พบ ; ตัวกรอง Use Case ที่ถูกลบไม่ค้าง', (tester) async {
    await boot(tester);
    final cases = generateTestCases(wc.workspace);
    Future<void> pick(String key, String label) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await pick('uc-tc-filter-kind', 'ข้อผิดพลาด');
    expect(find.byKey(ValueKey('uc-tc-${cases.firstWhere((c) => c.kind == TcKind.exception).id}')), findsOneWidget);
    expect(find.byKey(ValueKey('uc-tc-${cases.first.id}')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('uc-tc-footer'))).data, startsWith('แสดง 1 จาก 4'));

    await pick('uc-tc-filter-uc', 'UC-02 ชำระเงิน');
    expect(find.byKey(const ValueKey('uc-tc-none')), findsOneWidget, reason: 'UC-02 ไม่มีข้อผิดพลาด');

    await pick('uc-tc-filter-kind', 'ทุกชนิด');
    expect(find.byKey(ValueKey('uc-tc-${cases.last.id}')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('uc-tc-footer'))).data, startsWith('แสดง 1 จาก 4'));

    wc.deleteUseCase(b.id);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uc-tc-none')), findsNothing, reason: 'Use Case ที่กรองอยู่ถูกลบ → กลับไปแสดงทั้งหมด');
    expect(tester.takeException(), isNull);
  });

  testWidgets('แก้สเปก → ตารางตามทัน (สร้างจากสเปกเสมอ)', (tester) async {
    await boot(tester);
    expect(find.byKey(const ValueKey('uc-tc-total')), findsOneWidget);
    wc.updateUseCase(b.id, (x) => x.branches.add(UcBranch(id: 'bx', atStepId: 'p1', condition: 'บัตรหมดอายุ', ends: true)));
    await tester.pumpAndSettle();
    expect((tester.widget<Container>(find.byKey(const ValueKey('uc-tc-total'))).child as Text).data, '5 กรณี');
  });

  testWidgets('เมนูส่งออก: Markdown ตาราง · Given/When/Then · CSV', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('uc-tc-export')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uc-tc-export-table')), findsOneWidget);
    expect(find.byKey(const ValueKey('uc-tc-export-gwt')), findsOneWidget);
    expect(find.byKey(const ValueKey('uc-tc-export-csv')), findsOneWidget);
  });

  testWidgets('ยังไม่มีขั้นตอน/กรณี: ไม่มี Use Case ทั้งโปรเจกต์ = หน้าว่างของทั้งหน้า ; ลบหมดขณะอยู่แท็บนี้ = ข้อความว่าง ไม่ล้ม', (tester) async {
    await boot(tester);
    for (final u in List.of(wc.useCases)) {
      wc.deleteUseCase(u.id);
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uc-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('จอกว้างน้อย (900px) ตารางเลื่อนแนวนอน ไม่ล้น ; ภาษาอังกฤษไม่มีไทยหลุดในโครง', (tester) async {
    await boot(tester, size: const Size(900, 900), lang: Lang.en);
    expect(tester.takeException(), isNull);
    final thai = RegExp(r'[฀-๿]');
    const userData = {'จองห้อง', 'ชำระเงิน', 'เลือกห้อง', 'ตรวจห้องว่าง', 'ห้องเต็ม', 'เสนอห้องอื่น', 'ระบบล่ม', 'จ่ายเงิน', 'เข้าสู่ระบบแล้ว', 'มีการจอง', 'จอง'};
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final s = t.data ?? t.textSpan?.toPlainText() ?? '';
      if (!thai.hasMatch(s)) continue;
      expect(userData.any(s.contains), isTrue, reason: 'ไทยที่ไม่ใช่ข้อมูลผู้ใช้: $s');
    }
    expect(find.text('All types'), findsOneWidget);
  });
}
