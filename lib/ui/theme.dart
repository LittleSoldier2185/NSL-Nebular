import 'package:nsl_ui/nsl_ui.dart' show NslResolveException, NslThemeLookup, NslThemeSpec, NslTokens, kBuiltinDev, resolveTokens;
import 'package:flutter/material.dart';
import '../core/models/workspace.dart' show DocType;

export '../core/types/type_label.dart';

/// สีประจำชนิดเอกสาร: [main] = จุด/เส้น/ขอบ, [ink] = ตัวอักษรบนพื้นอ่อน, [tint] = พื้นอ่อน (ผ่าน 4.5:1 ทั้งคู่)
class DocColor {
  const DocColor(this.main, this.ink, this.tint);
  final Color main, ink, tint;
}

/// ชื่อคีย์ของสีชนิดเอกสารใน token `nebular` (`doc<คีย์>` / `doc<คีย์>Ink` / `doc<คีย์>Tint`)
/// ชนิดที่ยังไม่มีเป็น [DocType] (API) ต่อที่นี่เมื่อเพิ่มชนิดเอกสาร
const kDocColorKeys = <DocType, String>{
  DocType.er: 'Er',
  DocType.dfd: 'Dfd',
  DocType.flowchart: 'Flow',
  DocType.wireframe: 'Wire',
  DocType.screenflow: 'Screen',
  DocType.api: 'Api',
};

/// ชุดสีของหนึ่งธีม
class Palette {
  const Palette({
    this.docColors = const {},
    required this.brightness,
    required this.bg,
    required this.canvas,
    required this.dot,
    required this.surface,
    required this.surfaceHi,
    required this.border,
    required this.borderSoft,
    required this.inputBorder,
    required this.text,
    required this.muted,
    required this.primary,
    required this.primaryDark,
    required this.primaryTint,
    required this.tableHead,
    required this.warnBg,
    required this.warnText,
    required this.infoBg,
    required this.infoText,
    required this.field,
    required this.pkBg,
    required this.pkText,
    required this.uqBg,
    required this.uqText,
    required this.nnBg,
    required this.nnText,
    required this.shadow,
    required this.boardOutside,
    required this.boardEdge,
    required this.danger,
    required this.dangerBg,
    required this.dangerText,
    required this.fkSource,
    required this.fkChip,
  });

  /// สร้างจากโทเค็นของ nsl_ui (ธีม `nsl.nebular` หรือธีมที่ผู้ใช้เลือก) — ชื่อช่องของแอปกับโทเค็นต่างกันเล็กน้อย ตารางแปลงอยู่ที่นี่ที่เดียว
  factory Palette.fromTokens(NslTokens t, Brightness brightness) {
    final c = t.colors;
    Color x(String k) => t.ext('nebular', k)!;
    return Palette(
      docColors: {
        for (final e in kDocColorKeys.entries) e.key: DocColor(x('doc${e.value}'), x('doc${e.value}Ink'), x('doc${e.value}Tint')),
      },
      brightness: brightness,
      bg: c['bg'],
      canvas: x('canvas'),
      dot: x('dot'),
      surface: c['surface'],
      surfaceHi: c['surfaceRaised'],
      border: c['border'],
      borderSoft: c['borderSoft'],
      inputBorder: c['borderStrong'],
      text: c['text'],
      muted: c['textMuted'],
      primary: c['accent'],
      primaryDark: c['accentInk'],
      primaryTint: c['accentTint'],
      tableHead: x('tableHead'),
      warnBg: c['warnBg'],
      warnText: c['warnText'],
      infoBg: c['infoBg'],
      infoText: c['infoText'],
      field: c['surfaceSunken'],
      pkBg: x('pkBg'),
      pkText: x('pkText'),
      uqBg: x('uqBg'),
      uqText: x('uqText'),
      nnBg: x('nnBg'),
      nnText: x('nnText'),
      shadow: c['shadow'],
      boardOutside: x('boardOutside'),
      boardEdge: x('boardEdge'),
      danger: c['danger'],
      dangerBg: c['dangerBg'],
      dangerText: c['dangerText'],
      fkSource: x('fkSource'),
      fkChip: x('fkChip'),
    );
  }

  /// สีประจำชนิดเอกสารแต่ละชนิด (จาก token `nebular.doc*` ของ nsl_ui) — ใช้ผ่าน [docColor] / [C.doc]
  final Map<DocType, DocColor> docColors;

  /// สีของชนิดเอกสารนั้น ; ชนิดที่ไม่มีในพาเลตต์ (ไม่ควรเกิดกับพาเลตต์จาก `fromTokens`) ใช้สีหลักของธีมแทน
  DocColor docColor(DocType t) => docColors[t] ?? DocColor(primary, primaryDark, primaryTint);

  final Brightness brightness;
  final Color bg, canvas, dot, surface, surfaceHi, border, borderSoft, inputBorder;
  final Color text, muted, primary, primaryDark, primaryTint, tableHead;
  final Color warnBg, warnText, infoBg, infoText, field;
  final Color pkBg, pkText, uqBg, uqText, nnBg, nnText;

  /// สีเงา (ธีมมืดต้องเข้มกว่าเพื่อให้เห็นความลึก)
  final Color shadow;

  /// พื้นนอกกรอบกระดาน/ขอบกรอบ, สีอันตราย, สีแถวต้นทาง FK (เดิมเป็นค่าตายตัวใน `C`)
  final Color boardOutside, boardEdge, danger, dangerBg, dangerText, fkSource, fkChip;
}

/// พาเลตต์ในตัว คำนวณจากธีม `nsl.nebular` ของ nsl_ui (ไม่มีค่าสีตายตัวในไฟล์นี้ — ค่าเดิมถูกเก็บเป็นเทสต์ `test/theme_nsl_ui_parity_test.dart`)
final Palette kLightPalette = Palette.fromTokens(resolveTokens(kBuiltinDev, Brightness.light), Brightness.light);
final Palette kDarkPalette = Palette.fromTokens(resolveTokens(kBuiltinDev, Brightness.dark), Brightness.dark);

/// พาเลตต์ของโหมด [brightness] จากธีม [theme] (ไฟล์ธีมของผู้ใช้/ธีมที่เลือก ; null = ธีมในตัว `nsl.nebular`)
/// ธีมใช้ไม่ได้ (ธีมฐานหาย, วนลูป, ลึกเกิน, ขาดสีที่แอปต้องใช้) = ถอยไปธีมในตัว ไม่ให้แอปเปิดไม่ขึ้น
Palette paletteFor(Brightness brightness, {NslThemeSpec? theme, NslThemeLookup? lookup}) {
  final builtin = brightness == Brightness.dark ? kDarkPalette : kLightPalette;
  if (theme == null) return builtin;
  try {
    return Palette.fromTokens(resolveTokens(theme, brightness, lookup: lookup), brightness);
  } on NslResolveException {
    return builtin;
  } catch (_) {
    return builtin; // ธีมที่ไม่มีส่วนขยาย nebular (เช่นธีมของแอปอื่น) ทำให้ ext() เป็น null — ถอยกลับ
  }
}


/// สีและสไตล์ตามดีไซน์ "NSL Nebular — หน้าหลัก"
///
/// อ่านจากพาเลตต์ที่ใช้อยู่ตอนนี้ ([use]) — ตอนสลับธีมแอปจะสร้างต้นไม้วิดเจ็ตใหม่ทั้งหมด
class C {
  static Palette _p = kLightPalette;

  static Palette get palette => _p;
  static bool get isDark => _p.brightness == Brightness.dark;
  static void use(Palette p) => _p = p;

  /// รันงานด้วยพาเลตต์ที่กำหนดชั่วคราว (ใช้ตอน export ภาพ ให้ได้สีสว่างเสมอไม่ว่าธีมแอปเป็นอะไร)
  static T withPalette<T>(Palette p, T Function() body) {
    final prev = _p;
    _p = p;
    try {
      return body();
    } finally {
      _p = prev;
    }
  }

  static Color get bg => _p.bg;
  static Color get canvas => _p.canvas;
  static Color get dot => _p.dot;
  static Color get surface => _p.surface;
  static Color get surfaceHi => _p.surfaceHi;
  static Color get border => _p.border;
  static Color get borderSoft => _p.borderSoft;
  static Color get inputBorder => _p.inputBorder;
  static Color get text => _p.text;
  static Color get muted => _p.muted;
  static Color get primary => _p.primary;
  static Color get primaryDark => _p.primaryDark;
  static Color get primaryTint => _p.primaryTint;
  static Color get tableHead => _p.tableHead;
  static Color get warnBg => _p.warnBg;
  static Color get warnText => _p.warnText;
  static Color get infoBg => _p.infoBg;
  static Color get infoText => _p.infoText;
  static Color get field => _p.field;

  /// แถบบนพื้นเข้ม (Phase 17): พื้นใช้โทเค็นหัวตาราง (`tableHead`) เหมือนหัวการ์ดตาราง ; ตัวอักษร/เส้นบนพื้นเข้มเป็นสีขาวโปร่งตามระดับ
  /// (เหมือนข้อความบนหัวการ์ดตาราง จึงไม่ต้องมีโทเค็นใหม่ใน nsl_ui)
  static Color get barBg => _p.tableHead;
  static Color get onBar => Colors.white;
  static Color get onBarMuted => Colors.white.withValues(alpha: 0.72);
  static Color get barBorder => Colors.white.withValues(alpha: 0.22);
  static Color get barField => Colors.black.withValues(alpha: 0.22);
  static Color get barHover => Colors.white.withValues(alpha: 0.12);

  /// พื้นนอกกรอบกระดาน (เข้มกว่าพื้นกระดาน เพื่อให้เห็นขอบ)
  static Color get boardOutside => _p.boardOutside;
  static Color get boardEdge => _p.boardEdge;

  /// สีอันตราย (ลบ / error)
  static Color get danger => _p.danger;
  static Color get dangerBg => _p.dangerBg;
  static Color get dangerText => _p.dangerText;

  /// สีประจำชนิดเอกสาร (จุดในแท็บ/Explorer, ขอบการ์ด, ปุ่มหลักของเอกสารนั้น)
  static DocColor doc(DocType? t) => _p.docColor(t ?? DocType.er);

  /// แถวที่กำลังเป็นต้นทางของการลากเส้น FK
  static Color get fkSource => _p.fkSource;
  static Color get fkChip => _p.fkChip;

  static Color get pkBg => _p.pkBg;
  static Color get pkText => _p.pkText;
  static Color get uqBg => _p.uqBg;
  static Color get uqText => _p.uqText;
  static Color get nnBg => _p.nnBg;
  static Color get nnText => _p.nnText;

  // ---- ความลึก (elevation) ----
  static Color _sh(double a) => _p.shadow.withValues(alpha: isDark ? (a * 2.4).clamp(0, 1) : a);

  /// ยกเล็กน้อย: ปุ่ม, ช่องค้นหา
  static List<BoxShadow> get shadowSm => [
        BoxShadow(color: _sh(0.06), blurRadius: 2, offset: const Offset(0, 1)),
        BoxShadow(color: _sh(0.06), blurRadius: 6, offset: const Offset(0, 2)),
      ];

  /// ยกปานกลาง: การ์ดตาราง, แผงลอย
  static List<BoxShadow> get shadowMd => [
        BoxShadow(color: _sh(0.07), blurRadius: 3, offset: const Offset(0, 1)),
        BoxShadow(color: _sh(0.10), blurRadius: 14, offset: const Offset(0, 6)),
      ];

  /// ลอยสูง: ตารางที่เลือก/กำลังลาก, เมนู, dialog
  static List<BoxShadow> get shadowLg => [
        BoxShadow(color: _sh(0.10), blurRadius: 6, offset: const Offset(0, 2)),
        BoxShadow(color: _sh(0.16), blurRadius: 28, offset: const Offset(0, 14)),
      ];

  /// เงาเข้าด้านบนของแผงด้านข้าง/แถบบน ให้เห็นว่าแผงอยู่เหนือ canvas
  static List<BoxShadow> get shadowBar => [
        BoxShadow(color: _sh(0.08), blurRadius: 10, offset: const Offset(0, 2)),
      ];
}

/// ฟอนต์หลักของแอป (ไทย + อังกฤษ): Noto Sans Thai แพ็กมากับแอป (assets/fonts)
const kThai = 'Noto Sans Thai';

/// ฟอนต์สำรองสำหรับสัญลักษณ์ที่ Noto Sans Thai ไม่มี (เช่น ● ✓ →) — ใช้ฟอนต์ที่มากับระบบ
const kFontFallback = ['Leelawadee UI', 'Segoe UI Symbol', 'Segoe UI', 'Tahoma'];
const kMono = 'JetBrains Mono';

/// ใส่ฟอนต์ที่ผู้ใช้เลือกให้ตาราง ([family] = ชื่อฟอนต์ที่ติดตั้งในเครื่อง) — null = ไม่เปลี่ยน (ใช้ Noto Sans Thai)
/// ฟอนต์ที่ไม่มีอักษรไทยหรือไม่มีในเครื่องจะตกไปใช้ Noto Sans Thai ตามลำดับสำรอง
TextStyle tableFont(TextStyle base, String? family) =>
    family == null ? base : base.copyWith(fontFamily: family, fontFamilyFallback: [kThai, ...kFontFallback]);

const monoStyle = TextStyle(fontFamily: kMono, fontFamilyFallback: ['Consolas']);

ThemeData buildTheme([Palette? palette]) {
  final p = palette ?? kLightPalette;
  final dark = p.brightness == Brightness.dark;
  final base = dark ? ThemeData.dark() : ThemeData.light();
  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    fontFamily: kThai,
    fontFamilyFallback: kFontFallback,
    scaffoldBackgroundColor: p.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: kLightPalette.primary, brightness: p.brightness, surface: p.surface)
        .copyWith(primary: p.primary, onPrimary: Colors.white),
    textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
    dividerColor: p.borderSoft,
    canvasColor: p.surface,
    dialogTheme: DialogThemeData(
      backgroundColor: p.surfaceHi,
      elevation: 12,
      shadowColor: p.shadow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.borderSoft)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surfaceHi,
      elevation: 10,
      shadowColor: p.shadow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: p.borderSoft)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? p.surfaceHi : p.tableHead,
      contentTextStyle: const TextStyle(color: Colors.white, fontFamily: kThai),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: dark ? p.surfaceHi : p.tableHead, borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: kThai),
    ),
  );
}
