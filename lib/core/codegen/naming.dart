/// ชื่อสำหรับโค้ดที่สร้าง (ใช้ร่วมกันในตัวสร้างของ Phase 10)
library;

List<String> _words(String s) {
  final spaced = s
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ')
      .trim();
  return spaced.isEmpty ? <String>[] : spaced.split(' ');
}

String _cap(String w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';

/// `order_items` → `OrderItems` ; ไม่มีอักษรละติน = [fallback] ; ขึ้นต้นด้วยตัวเลข = ต่อ `X` ข้างหน้า
String pascalCase(String s, {String fallback = 'Item'}) {
  final w = _words(s);
  final out = w.isEmpty ? fallback : w.map(_cap).join();
  return RegExp(r'^[0-9]').hasMatch(out) ? 'X$out' : out;
}

/// `Order Items` → `orderItems`
String camelCase(String s, {String fallback = 'item'}) {
  final p = pascalCase(s, fallback: fallback);
  return '${p[0].toLowerCase()}${p.substring(1)}';
}

/// `OrderItems` / `order items` → `order_items`
String snakeCase(String s, {String fallback = 'item'}) {
  final w = _words(s);
  return w.isEmpty ? fallback : w.map((x) => x.toLowerCase()).join('_');
}

/// รูปเอกพจน์อย่างง่าย (`orders` → `order`, `categories` → `category`)
String singular(String word) {
  if (word.length > 3 && word.toLowerCase().endsWith('ies')) return '${word.substring(0, word.length - 3)}y';
  if (word.length > 3 && RegExp(r'(ss|sh|ch|x)es$', caseSensitive: false).hasMatch(word)) return word.substring(0, word.length - 2);
  if (word.length > 1 && word.toLowerCase().endsWith('s') && !word.toLowerCase().endsWith('ss')) return word.substring(0, word.length - 1);
  return word;
}

/// สตริงในเครื่องหมาย ' สำหรับ PHP / Dart (escape \ และ ')
String singleQuoted(String s) => "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

/// สตริง Dart ในเครื่องหมาย ' (escape \ ' และ $ — `$` ใน Dart คือการแทรกค่า)
String dartQuoted(String s) => "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";
