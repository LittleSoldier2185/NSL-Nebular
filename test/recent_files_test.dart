import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/storage/recent_files.dart';
import 'package:nsl_nebular/state/app_settings.dart';

DateTime t(int minute) => DateTime(2026, 11, 18, 10, minute);

void main() {
  settingsPersistence();
  group('RecentFiles', () {
    test('touch: ล่าสุดอยู่บนสุด ; เปิดซ้ำ = ยกขึ้นบนและไม่ซ้ำ ; path ต่างตัวพิมพ์/ทิศทางทับ = ไฟล์เดียวกัน', () {
      var r = RecentFiles();
      r = r.touch(r'C:\a\shop.nsln', name: 'shop', now: t(1));
      r = r.touch(r'C:\a\blog.nsln', name: 'blog', now: t(2));
      expect(r.items.map((f) => f.name), ['blog', 'shop']);
      r = r.touch('c:/A/SHOP.nsln', name: 'shop v2', now: t(3), docCount: 4, docTypes: ['er', 'dfd']);
      expect(r.items.map((f) => f.name), ['shop v2', 'blog']);
      expect(r.items.first.docCount, 4);
      expect(r.items.first.docTypes, ['er', 'dfd']);
    });

    test('ปักหมุด: อยู่บนสุดแม้เก่ากว่า ; เปิดซ้ำคงหมุดไว้ ; ปลดหมุดกลับไปเรียงตามเวลา', () {
      var r = RecentFiles()
          .touch('a.nsln', name: 'a', now: t(1))
          .touch('b.nsln', name: 'b', now: t(2))
          .touch('c.nsln', name: 'c', now: t(3));
      r = r.togglePin('a.nsln');
      expect(r.items.map((f) => f.name), ['a', 'c', 'b']);
      r = r.touch('a.nsln', name: 'a', now: t(9));
      expect(r.items.first.pinned, true);
      r = r.togglePin('a.nsln');
      expect(r.items.map((f) => f.name), ['a', 'c', 'b']); // a เปิดล่าสุด (t9) จึงยังอยู่บน
      r = r.touch('b.nsln', name: 'b', now: t(10));
      expect(r.items.map((f) => f.name), ['b', 'a', 'c']);
    });

    test('จำกัดไฟล์ที่ไม่ปักหมุดไม่เกิน ${RecentFiles.maxUnpinned} ; ที่ปักหมุดไม่ถูกตัด', () {
      var r = RecentFiles().touch('keep.nsln', name: 'keep', now: t(0)).togglePin('keep.nsln');
      for (var i = 1; i <= RecentFiles.maxUnpinned + 5; i++) {
        r = r.touch('f$i.nsln', name: 'f$i', now: DateTime(2026, 11, 18, 11, 0, i));
      }
      expect(r.items.length, RecentFiles.maxUnpinned + 1);
      expect(r.items.first.name, 'keep');
      expect(r.items.any((f) => f.name == 'f1'), false); // เก่าสุดถูกตัด
      expect(r.items.any((f) => f.name == 'f${RecentFiles.maxUnpinned + 5}'), true);
    });

    test('remove และ pruneMissing', () {
      var r = RecentFiles().touch('a.nsln', name: 'a', now: t(1)).touch('b.nsln', name: 'b', now: t(2));
      expect(r.remove('A.NSLN').items.map((f) => f.name), ['b']);
      expect(r.pruneMissing((p) => p == 'b.nsln').items.map((f) => f.name), ['b']);
      expect(r.pruneMissing((_) => false).isEmpty, true);
    });

    test('JSON ไป-กลับได้ครบ ; ข้อมูลเสียถูกข้ามรายการเดียว ไม่ทำให้ทั้งรายการเสีย', () {
      final r = RecentFiles()
          .touch('a.nsln', name: 'a', now: t(1), docCount: 2, docTypes: ['er'])
          .touch('b.nsln', name: 'b', now: t(2))
          .togglePin('a.nsln');
      final back = RecentFiles.fromJson(jsonDecode(jsonEncode(r.toJson())));
      expect(jsonEncode(back.toJson()), jsonEncode(r.toJson()));
      expect(back.items.first.pinned, true);
      expect(back.items.first.docTypes, ['er']);

      final messy = RecentFiles.fromJson([
        {'path': 'ok.nsln', 'at': t(5).millisecondsSinceEpoch},
        {'path': 3, 'at': 1},
        {'name': 'no path', 'at': 1},
        'junk',
        null,
        {'path': 'bad-time.nsln', 'at': 'x'},
      ]);
      expect(messy.items.map((f) => f.path), ['ok.nsln']);
      expect(messy.items.single.name, 'ok'); // ไม่มีชื่อ = ใช้ชื่อไฟล์
      expect(RecentFiles.fromJson('not a list').isEmpty, true);
      expect(RecentFiles.fromJson(null).isEmpty, true);
    });
  });
}

/// บันทึก/โหลดผ่านไฟล์ settings จริง (AppSettings)
void settingsPersistence() {
  test('AppSettings: ไฟล์ล่าสุดถูกบันทึกลง settings.json และโหลดกลับได้ครบ (รวมหมุด) ; ไฟล์เก่าไม่มีคีย์ = รายการว่าง', () {
    final dir = Directory.systemTemp.createTempSync('nsl_settings');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/settings.json');

    final s = AppSettings.load(file); // ยังไม่มีไฟล์ = ค่าเริ่มต้น
    expect(s.recentFiles, isEmpty);
    s.addRecent(r'C:\a\shop.nsln', name: 'shop', now: t(1), docCount: 3, docTypes: ['er', 'dfd']);
    s.addRecent(r'C:\a\blog.nsln', name: 'blog', now: t(2));
    s.toggleRecentPin(r'C:\a\shop.nsln');

    final back = AppSettings.load(file);
    expect(back.recentFiles.map((f) => (f.name, f.pinned, f.docCount)), [('shop', true, 3), ('blog', false, 0)]);
    expect(back.recentFiles.first.docTypes, ['er', 'dfd']);

    // ไฟล์ settings เก่าที่ไม่มี recent
    file.writeAsStringSync('{"theme":"dark"}');
    expect(AppSettings.load(file).recentFiles, isEmpty);
    // recent เสียรูปแบบ: ไม่ทำให้ settings ทั้งไฟล์เสีย
    file.writeAsStringSync('{"theme":"dark","recent":"junk"}');
    final broken = AppSettings.load(file);
    expect(broken.dark, true);
    expect(broken.recentFiles, isEmpty);
  });
}
