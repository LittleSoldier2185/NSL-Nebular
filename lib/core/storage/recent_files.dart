/// ไฟล์โปรเจกต์ที่เปิด/บันทึกล่าสุด (แสดงในหน้า Start) — ข้อมูลของเครื่องนี้ เก็บใน settings ไม่เก็บในไฟล์โปรเจกต์
class RecentFile {
  const RecentFile({
    required this.path,
    required this.name,
    required this.openedAt,
    this.pinned = false,
    this.docCount = 0,
    this.docTypes = const [],
  });

  final String path;

  /// ชื่อที่แสดง (ชื่อโปรเจกต์ ณ ตอนเปิด/บันทึก)
  final String name;
  final DateTime openedAt;
  final bool pinned;

  /// จำนวนเอกสารในโปรเจกต์ ณ ตอนนั้น (แสดงในการ์ด)
  final int docCount;

  /// ชนิดเอกสารที่มี (ชื่อ [DocType] ไม่ซ้ำ ตามลำดับที่เจอ) — ใช้วาดจุดสีในการ์ด ; เก็บเป็นข้อความเพื่อไม่ผูกกับ enum
  final List<String> docTypes;

  RecentFile copyWith({String? name, DateTime? openedAt, bool? pinned, int? docCount, List<String>? docTypes}) => RecentFile(
        path: path,
        name: name ?? this.name,
        openedAt: openedAt ?? this.openedAt,
        pinned: pinned ?? this.pinned,
        docCount: docCount ?? this.docCount,
        docTypes: docTypes ?? this.docTypes,
      );

  Map<String, Object?> toJson() => {
        'path': path,
        'name': name,
        'at': openedAt.millisecondsSinceEpoch,
        if (pinned) 'pin': true,
        'docs': docCount,
        'types': docTypes,
      };

  /// อ่านจาก JSON — ข้อมูลผิดรูปแบบ = null (ข้ามรายการนั้น ไม่ทำให้ทั้งรายการเสีย)
  static RecentFile? fromJson(Object? j) {
    if (j is! Map) return null;
    final path = j['path'];
    final at = j['at'];
    if (path is! String || path.isEmpty || at is! int) return null;
    final name = j['name'];
    final docs = j['docs'];
    final types = j['types'];
    return RecentFile(
      path: path,
      name: name is String && name.isNotEmpty ? name : _baseName(path),
      openedAt: DateTime.fromMillisecondsSinceEpoch(at),
      pinned: j['pin'] == true,
      docCount: docs is int && docs >= 0 ? docs : 0,
      docTypes: types is List ? [for (final t in types) if (t is String) t] : const [],
    );
  }
}

String _baseName(String path) {
  final file = path.split(RegExp(r'[\\/]')).last;
  final dot = file.lastIndexOf('.');
  return dot > 0 ? file.substring(0, dot) : file;
}

/// เทียบ path ให้เป็นไฟล์เดียวกันบน Windows: ไม่สนตัวพิมพ์และ \ กับ /
String recentKey(String path) => path.replaceAll('\\', '/').toLowerCase();

/// รายการไฟล์ล่าสุด: ปักหมุดอยู่บนสุด ที่เหลือเรียงเปิดล่าสุดก่อน ; ไม่ปักหมุดเก็บไม่เกิน [maxUnpinned] รายการ
class RecentFiles {
  RecentFiles([Iterable<RecentFile> items = const []]) : _items = _normalize(items);

  static const maxUnpinned = 20;

  final List<RecentFile> _items;

  List<RecentFile> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

  static List<RecentFile> _normalize(Iterable<RecentFile> src) {
    final byKey = <String, RecentFile>{};
    for (final f in src) {
      final k = recentKey(f.path);
      final old = byKey[k];
      // path ซ้ำ: เก็บอันที่เปิดล่าสุด (คงหมุดไว้ถ้าอันใดอันหนึ่งปัก)
      if (old == null || f.openedAt.isAfter(old.openedAt)) {
        byKey[k] = f.copyWith(pinned: f.pinned || (old?.pinned ?? false));
      } else if (f.pinned && !old.pinned) {
        byKey[k] = old.copyWith(pinned: true);
      }
    }
    final all = byKey.values.toList()..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    final pinned = [for (final f in all) if (f.pinned) f];
    final rest = [for (final f in all) if (!f.pinned) f].take(maxUnpinned);
    return [...pinned, ...rest];
  }

  /// บันทึกว่าเปิด/บันทึกไฟล์ [path] เมื่อ [now] — ถ้ามีอยู่แล้วคงหมุดไว้และยกขึ้นบน
  RecentFiles touch(String path, {required String name, required DateTime now, int docCount = 0, List<String> docTypes = const []}) {
    final k = recentKey(path);
    final old = _items.where((f) => recentKey(f.path) == k).firstOrNull;
    final next = RecentFile(path: path, name: name, openedAt: now, pinned: old?.pinned ?? false, docCount: docCount, docTypes: docTypes);
    return RecentFiles([..._items.where((f) => recentKey(f.path) != k), next]);
  }

  RecentFiles togglePin(String path) {
    final k = recentKey(path);
    return RecentFiles([for (final f in _items) recentKey(f.path) == k ? f.copyWith(pinned: !f.pinned) : f]);
  }

  RecentFiles remove(String path) {
    final k = recentKey(path);
    return RecentFiles(_items.where((f) => recentKey(f.path) != k));
  }

  /// ตัดไฟล์ที่ไม่มีอยู่แล้วออก ([exists] ส่งมาจากภายนอกเพื่อให้เทสต์ได้โดยไม่แตะดิสก์)
  RecentFiles pruneMissing(bool Function(String path) exists) => RecentFiles(_items.where((f) => exists(f.path)));

  List<Map<String, Object?>> toJson() => [for (final f in _items) f.toJson()];

  /// อ่านจาก JSON — ไม่ใช่รายการ = ว่าง ; รายการที่ผิดรูปแบบถูกข้าม
  static RecentFiles fromJson(Object? j) =>
      j is List ? RecentFiles([for (final e in j) ?RecentFile.fromJson(e)]) : RecentFiles();
}
