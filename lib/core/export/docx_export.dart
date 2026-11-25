import 'dart:convert';
import 'dart:typed_data';

/// แปลงเอกสาร Markdown ของพจนานุกรมข้อมูล (จาก exportWorkspaceDictionary) เป็นไฟล์ Word (.docx)
/// - ไม่พึ่งไลบรารีภายนอก : .docx คือ ZIP ของ XML — เขียน ZIP แบบ stored เอง
/// - รองรับเฉพาะรูปแบบที่ตัวส่งออก Markdown ของแอปสร้าง : หัวข้อ # ~ ###, รายการ "- ", ตาราง | |, **หนา**, _เอียง_, `โค้ด`, [ลิงก์](#..), <br>
/// - ผลลัพธ์คงที่ (ไม่มีวันที่/สุ่ม) — ฟอนต์ภาษาไทยกำหนดผ่าน cs/bidi เพื่อให้ Word แสดงถูกต้อง
Uint8List markdownToDocx(String markdown, {String title = '', Map<String, List<DocxImage>> imagesAfter = const {}}) {
  final queue = {for (final e in imagesAfter.entries) e.key: [...e.value]};
  final media = <String, List<int>>{};
  final rels = StringBuffer();
  var firstHeading = true;
  String drawImages(String key) {
    final list = queue[key];
    if (list == null) return '';
    final b = StringBuffer();
    for (final im in list) {
      final n = media.length + 1;
      media['word/media/image$n.png'] = im.bytes;
      rels.write('<Relationship Id="rIdImg$n" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image$n.png"/>');
      b.write(_drawing(im, n));
    }
    queue.remove(key);
    return b.toString();
  }

  final body = StringBuffer();
  final lines = const LineSplitter().convert(markdown);
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final t = line.trim();
    if (t.isEmpty) {
      i++;
      continue;
    }
    final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(t);
    if (h != null) {
      final level = h.group(1)!.length.clamp(1, 3);
      body.write(_para(h.group(2)!, style: 'Heading$level'));
      body.write(drawImages(h.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim()));
      if (firstHeading) body.write(drawImages(kDocxFirstHeading));
      firstHeading = false;
      i++;
      continue;
    }
    if (t.startsWith('|')) {
      final rows = <List<String>>[];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        final cells = _splitRow(lines[i].trim());
        i++;
        if (cells.isNotEmpty && cells.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c.trim()))) continue; // แถวคั่นหัวตาราง
        rows.add(cells);
      }
      body.write(_table(rows));
      continue;
    }
    final li = RegExp(r'^(\s*)[-*]\s+(.*)$').firstMatch(line);
    if (li != null) {
      final level = (li.group(1)!.length ~/ 2).clamp(0, 3);
      body.write(_para('• ${li.group(2)!}', indent: 360 + level * 360, hanging: 240));
      i++;
      continue;
    }
    if (t == '---' || t == '***') {
      i++;
      continue;
    }
    body.write(_para(t));
    i++;
  }
  final doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>'
      '$body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>'
      '</w:body></w:document>';
  return _zip(<String, Object>{
    '[Content_Types].xml': _contentTypes,
    '_rels/.rels': _rootRels,
    'word/document.xml': doc,
    'word/styles.xml': _styles,
    'word/_rels/document.xml.rels': _docRels.replaceFirst('</Relationships>', '$rels</Relationships>'),
    ...media,
    'docProps/core.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>${_x(title)}</dc:title><dc:creator>NSL Nebular</dc:creator></cp:coreProperties>',
  });
}

/// ภาพ PNG ที่ฝังใน Word : [width]/[height] = พิกเซลของไฟล์ ; [scale] = ตัวคูณที่ใช้วาด (ขนาดจริง = พิกเซล ÷ scale)
class DocxImage {
  const DocxImage(this.bytes, this.width, this.height, {this.scale = 2});
  final Uint8List bytes;
  final int width, height;
  final double scale;
}

/// คีย์ [markdownToDocx.imagesAfter] ที่แปลว่า "ต่อจากหัวข้อแรกของเอกสาร" (ใช้กับโปรเจกต์ที่มี ER เดียว หัวข้อไม่มีคำว่า ER:)
const kDocxFirstHeading = '*first';

String _drawing(DocxImage im, int n) {
  const emuPerPx = 9525; // 96 dpi
  const maxW = 6 * 914400, maxH = 8 * 914400; // 6 x 8 นิ้ว : พอดีหน้า A4 ที่เว้นขอบ
  var cx = im.width / im.scale * emuPerPx, cy = im.height / im.scale * emuPerPx;
  final k = [1.0, maxW / cx, maxH / cy].reduce((a, b) => a < b ? a : b);
  cx *= k;
  cy *= k;
  final x = cx.round(), y = cy.round();
  return '<w:p><w:pPr><w:jc w:val="center"/><w:spacing w:after="120"/></w:pPr><w:r><w:drawing>'
      '<wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="$x" cy="$y"/><wp:docPr id="$n" name="Picture $n"/>'
      '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic>'
      '<pic:nvPicPr><pic:cNvPr id="$n" name="image$n.png"/><pic:cNvPicPr/></pic:nvPicPr>'
      '<pic:blipFill><a:blip r:embed="rIdImg$n"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
      '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$x" cy="$y"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
      '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>';
}

List<String> _splitRow(String row) {
  var s = row;
  if (s.startsWith('|')) s = s.substring(1);
  final cells = <String>[];
  final cur = StringBuffer();
  for (var k = 0; k < s.length; k++) {
    final ch = s[k];
    if (ch == '\\' && k + 1 < s.length && (s[k + 1] == '|' || s[k + 1] == '\\')) {
      cur.write('\\${s[k + 1]}'); // ปล่อยให้ตัวแปลงข้อความ inline คลาย escape
      k++;
    } else if (ch == '|') {
      cells.add(cur.toString());
      cur.clear();
    } else {
      cur.write(ch);
    }
  }
  if (cur.toString().trim().isNotEmpty) cells.add(cur.toString());
  return cells;
}

String _table(List<List<String>> rows) {
  if (rows.isEmpty) return '';
  final cols = rows.fold<int>(0, (a, r) => r.length > a ? r.length : a);
  const total = 9638; // ความกว้างพื้นที่เขียน (twips) A4 ขอบ 2 ซม.
  final w = total ~/ cols;
  final b = StringBuffer('<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="$total" w:type="dxa"/><w:tblLayout w:type="fixed"/></w:tblPr><w:tblGrid>');
  for (var c = 0; c < cols; c++) {
    b.write('<w:gridCol w:w="$w"/>');
  }
  b.write('</w:tblGrid>');
  for (var r = 0; r < rows.length; r++) {
    final head = r == 0;
    b.write('<w:tr>${head ? '<w:trPr><w:tblHeader/></w:trPr>' : ''}');
    for (var c = 0; c < cols; c++) {
      final text = c < rows[r].length ? rows[r][c].trim() : '';
      b.write('<w:tc><w:tcPr><w:tcW w:w="$w" w:type="dxa"/>${head ? '<w:shd w:val="clear" w:color="auto" w:fill="E8EEF3"/>' : ''}</w:tcPr>'
          '${_para(text, bold: head, size: 18, spacingAfter: 0)}</w:tc>');
    }
    b.write('</w:tr>');
  }
  b.write('</w:tbl>');
  b.write('<w:p><w:pPr><w:spacing w:after="60"/></w:pPr></w:p>');
  return b.toString();
}

String _para(String text, {String? style, int? indent, int? hanging, bool bold = false, int? size, int spacingAfter = 80}) {
  final ppr = StringBuffer('<w:pPr>');
  if (style != null) ppr.write('<w:pStyle w:val="$style"/>');
  if (indent != null) ppr.write('<w:ind w:left="$indent" w:hanging="${hanging ?? 0}"/>');
  ppr.write('<w:spacing w:after="$spacingAfter"/></w:pPr>');
  return '<w:p>$ppr${_runs(text, bold: bold, size: size)}</w:p>';
}

/// แปลงข้อความ inline ของ Markdown เป็น run ของ Word
String _runs(String text, {bool bold = false, int? size}) {
  var s = text;
  var italicAll = false;
  if (s.length > 2 && s.startsWith('_') && s.endsWith('_') && !s.substring(1, s.length - 1).contains('_ ')) {
    s = s.substring(1, s.length - 1);
    italicAll = true;
  }
  final out = StringBuffer();
  final re = RegExp(r'`([^`]*)`|\*\*(.+?)\*\*|\[([^\]]*)\]\(#[^)]*\)|<br\s*/?>');
  var pos = 0;
  void plain(String seg, {bool b = false, bool code = false}) {
    if (seg.isEmpty) return;
    final unescaped = seg.replaceAllMapped(RegExp(r'\\([|\\])'), (m) => m.group(1)!);
    out.write(_run(unescaped, bold: bold || b, italic: italicAll, code: code, size: size));
  }

  for (final m in re.allMatches(s)) {
    plain(s.substring(pos, m.start));
    if (m.group(1) != null) {
      plain(m.group(1)!, code: true);
    } else if (m.group(2) != null) {
      plain(m.group(2)!, b: true);
    } else if (m.group(3) != null) {
      plain(m.group(3)!);
    } else {
      out.write('<w:r><w:br/></w:r>');
    }
    pos = m.end;
  }
  plain(s.substring(pos));
  return out.toString();
}

String _run(String text, {bool bold = false, bool italic = false, bool code = false, int? size}) {
  final rpr = StringBuffer('<w:rPr>');
  if (code) {
    rpr.write('<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Tahoma"/>');
  }
  if (bold) rpr.write('<w:b/><w:bCs/>');
  if (italic) rpr.write('<w:i/><w:iCs/>');
  if (size != null) rpr.write('<w:sz w:val="$size"/><w:szCs w:val="$size"/>');
  rpr.write('</w:rPr>');
  return '<w:r>$rpr<w:t xml:space="preserve">${_x(text)}</w:t></w:r>';
}

String _x(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

// ───────────────────────── ZIP (stored) ─────────────────────────

Uint8List _zip(Map<String, Object> files) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  var count = 0;
  for (final e in files.entries) {
    final name = utf8.encode(e.key);
    final v = e.value;
    final List<int> data = v is String ? utf8.encode(v) : v as List<int>;
    final crc = _crc32(data);
    final offset = out.length;
    out.add(_le32(0x04034b50));
    out.add([20, 0, 0, 8, 0, 0, 0, 0, 0x21, 0]); // version, flags(UTF-8), method=stored, time, date (1980-01-01)
    out.add(_le32(crc));
    out.add(_le32(data.length));
    out.add(_le32(data.length));
    out.add(_le16(name.length));
    out.add(_le16(0));
    out.add(name);
    out.add(data);

    central.add(_le32(0x02014b50));
    central.add([20, 0, 20, 0, 0, 8, 0, 0, 0, 0, 0x21, 0]); // made-by, needed, flags, method, time, date
    central.add(_le32(crc));
    central.add(_le32(data.length));
    central.add(_le32(data.length));
    central.add(_le16(name.length));
    central.add(_le16(0)); // extra
    central.add(_le16(0)); // comment
    central.add(_le16(0)); // disk
    central.add(_le16(0)); // internal attrs
    central.add(_le32(0)); // external attrs
    central.add(_le32(offset));
    central.add(name);
    count++;
  }
  final cdOffset = out.length;
  final cd = central.toBytes();
  out.add(cd);
  out.add(_le32(0x06054b50));
  out.add(_le16(0));
  out.add(_le16(0));
  out.add(_le16(count));
  out.add(_le16(count));
  out.add(_le32(cd.length));
  out.add(_le32(cdOffset));
  out.add(_le16(0));
  return out.toBytes();
}

List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _le32(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];

final List<int> _crcTable = List.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xff] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

// ───────────────────────── ส่วนประกอบคงที่ของ .docx ─────────────────────────

const _contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Default Extension="png" ContentType="image/png"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
    '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
    '</Types>';

const _rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
    '</Relationships>';

const _docRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '</Relationships>';

const _styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Tahoma" w:cs="Tahoma"/>'
    '<w:sz w:val="22"/><w:szCs w:val="24"/><w:lang w:val="en-US" w:eastAsia="th-TH" w:bidi="th-TH"/></w:rPr></w:rPrDefault></w:docDefaults>'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>'
    '<w:pPr><w:keepNext/><w:spacing w:before="240" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:bCs/><w:color w:val="0F766E"/><w:sz w:val="40"/><w:szCs w:val="40"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>'
    '<w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:bCs/><w:sz w:val="30"/><w:szCs w:val="30"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>'
    '<w:pPr><w:keepNext/><w:spacing w:before="160" w:after="60"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:bCs/><w:color w:val="475569"/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:style>'
    '<w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/><w:tblPr><w:tblInd w:w="0" w:type="dxa"/>'
    '<w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>'
    '<w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:basedOn w:val="TableNormal"/><w:tblPr><w:tblBorders>'
    '<w:top w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/><w:left w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
    '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/><w:right w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
    '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
    '</w:tblBorders></w:tblPr></w:style>'
    '</w:styles>';
