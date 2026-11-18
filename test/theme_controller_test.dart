// ธีมกลางของ NSL (nsl_ui) ในแอปจริง: เลือกธีมจากที่เก็บ → สีเปลี่ยนสด, safe mode, ธีมเสีย/ผิดแอปถอยไปธีมในตัว
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/ui/theme.dart';
import 'package:nsl_nebular/ui/theme_dialog.dart';
import 'package:nsl_ui/nsl_ui.dart';

NslThemeSpec _theme(String id, {required String accent, String extendsId = 'nsl.nebular'}) => parseNslt(
      '{"schema":1,"id":"$id","name":"$id","extends":"$extendsId","apps":["nebular"],'
      '"light":{"colors":{"accent":"$accent"}},"dark":{"colors":{"accent":"$accent"}}}',
    ).spec!;

Future<void> _setup(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
}

void main() {
  tearDown(() => C.use(kLightPalette));

  group('paletteFor', () {
    test('ไม่มีธีม = ธีมในตัว', () {
      expect(identical(paletteFor(Brightness.light), kLightPalette), isTrue);
      expect(identical(paletteFor(Brightness.dark), kDarkPalette), isTrue);
    });

    test('ธีมที่สืบทอด nsl.nebular เปลี่ยนเฉพาะสีที่ระบุ (accent) ส่วนอื่นเท่าเดิม', () {
      final p = paletteFor(Brightness.light, theme: _theme('mine', accent: '#AA2244'), lookup: builtinThemeById);
      expect(p.primary, const Color(0xFFAA2244));
      expect(p.bg, kLightPalette.bg);
      expect(p.pkBg, kLightPalette.pkBg);
    });

    test('ธีมฐานหาย → ถอยไปธีมในตัว ไม่โยน', () {
      final p = paletteFor(Brightness.light, theme: _theme('orphan', accent: '#AA2244', extendsId: 'missing'), lookup: (_) => null);
      expect(identical(p, kLightPalette), isTrue);
    });

    test('ธีมของแอปอื่น (เช่น nsl.orbit) ใช้ได้ : ส่วนขยายของ nebular มีค่าเริ่มต้นเสมอ จึงไม่โยนและได้พาเลตต์ครบ', () {
      final other = _theme('for-orbit', accent: '#AA2244', extendsId: 'nsl.orbit');
      final p = paletteFor(Brightness.light, theme: other, lookup: builtinThemeById);
      expect(p.primary, const Color(0xFFAA2244));
      expect(p.canvas, isNot(const Color(0x00000000)));
    });
  });

  group('แอปจริง', () {
    Future<NslThemeController> controller(NslThemeSpec? selected) async {
      final st = NslMemoryThemeStorage();
      if (selected != null) await st.saveTheme(selected);
      final c = NslThemeController(st);
      await c.reload();
      if (selected != null) await c.select(selected.id);
      return c;
    }

    testWidgets('เลือกธีมจากที่เก็บ → สีของแอปเปลี่ยน', (tester) async {
      await _setup(tester);
      final c = await controller(_theme('mine', accent: '#AA2244'));
      addTearDown(c.dispose);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th), themes: c));
      await tester.pumpAndSettle();
      expect(C.primary, const Color(0xFFAA2244));
    });

    testWidgets('safe mode → ไม่ใช้ธีมของผู้ใช้ ; ปิดแล้วกลับมา (สดโดยไม่เปิดแอปใหม่)', (tester) async {
      await _setup(tester);
      final c = await controller(_theme('mine', accent: '#AA2244'));
      addTearDown(c.dispose);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th), themes: c));
      await tester.pumpAndSettle();
      await tester.runAsync(() => c.setSafeMode(true));
      await tester.pumpAndSettle();
      expect(C.primary, kLightPalette.primary);
      await tester.runAsync(() => c.setSafeMode(false));
      await tester.pumpAndSettle();
      expect(C.primary, const Color(0xFFAA2244));
    });

    testWidgets('ไม่มีที่เก็บธีม (themes = null) = ธีมในตัวเหมือนเดิม', (tester) async {
      await _setup(tester);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th)));
      await tester.pumpAndSettle();
      expect(C.primary, kLightPalette.primary);
    });

    testWidgets('เปลี่ยนธีมสด: เอกสารที่เปิดอยู่ไม่หาย', (tester) async {
      await _setup(tester);
      final c = await controller(null);
      addTearDown(c.dispose);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th), themes: c));
      await tester.pumpAndSettle();
      final before = tester.state<State>(find.byType(NslDevApp));
      await tester.runAsync(() async {
        await c.store.saveTheme(_theme('late', accent: '#118833'));
        await c.reload();
        await c.select('late');
      });
      await tester.pumpAndSettle();
      expect(C.primary, const Color(0xFF118833));
      expect(identical(tester.state<State>(find.byType(NslDevApp)), before), isTrue, reason: 'State ของแอปต้องไม่ถูกสร้างใหม่ (เอกสารอยู่ใน State)');
    });
  });

  group('หน้าเลือกธีม', () {
    Future<NslThemeController> withThemes() async {
      final st = NslMemoryThemeStorage();
      await st.saveTheme(_theme('mine', accent: '#AA2244'));
      final c = NslThemeController(st);
      await c.reload();
      return c;
    }

    testWidgets('มีปุ่มจานสีเมื่อมีที่เก็บ ; ไม่มีที่เก็บ = ไม่มีปุ่ม', (tester) async {
      await _setup(tester);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.palette_outlined), findsNothing);

      final c = await withThemes();
      addTearDown(c.dispose);
      await tester.pumpWidget(NslDevApp(key: UniqueKey(), settings: AppSettings(lang: Lang.th), themes: c));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
    });

    testWidgets('เปิดหน้า → เลือกธีมของผู้ใช้ สีเปลี่ยนสดและหน้าปิดเอง → เปิดใหม่ เปิด safe mode → กลับธีมในตัวได้', (tester) async {
      await _setup(tester);
      final c = await withThemes();
      addTearDown(c.dispose);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th), themes: c));
      await tester.pumpAndSettle();

      Future<void> open() async {
        await tester.tap(find.byIcon(Icons.palette_outlined));
        await tester.pumpAndSettle();
      }

      await open();
      expect(find.byKey(const ValueKey('theme-mine')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('theme-mine')));
      await tester.pumpAndSettle();
      expect(find.byType(ThemeDialog), findsNothing);
      expect(c.settings.activeThemeId, 'mine');
      expect(C.primary, const Color(0xFFAA2244));

      await open();
      await tester.tap(find.byKey(const ValueKey('theme-safe')));
      await tester.pumpAndSettle();
      expect(c.safeMode, isTrue);
      expect(C.primary, kLightPalette.primary);

      await open();
      await tester.tap(find.byKey(const ValueKey('theme-safe'))); // ปิด safe mode → กลับมาใช้ธีมที่เลือกไว้
      await tester.pumpAndSettle();
      expect(C.primary, const Color(0xFFAA2244));

      await open();
      await tester.tap(find.byKey(const ValueKey('theme-builtin')));
      await tester.pumpAndSettle();
      expect(c.settings.activeThemeId, isNull);
      expect(C.primary, kLightPalette.primary);
    });

    testWidgets('ภาษาอังกฤษ: หน้าเลือกธีมไม่มีอักษรไทยหลุด และไม่ overflow ที่ความกว้าง 360', (tester) async {
      await _setup(tester);
      final c = await withThemes();
      addTearDown(c.dispose);
      AppSettings(lang: Lang.en); // ตั้งภาษาของ tr()
      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ThemeDialog(controller: c))));
      await tester.pumpAndSettle();
      final thai = RegExp(r'[฀-๿]');
      final leaks = [
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          if (thai.hasMatch(t.data ?? '')) t.data,
      ];
      expect(leaks, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
