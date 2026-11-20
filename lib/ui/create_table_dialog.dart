import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/ddl/ddl_generator.dart';
import '../core/l10n/l10n.dart';
import '../core/models/check_model.dart';
import '../core/models/column_model.dart';
import '../core/models/enums.dart';
import '../core/models/index_model.dart';
import '../core/models/project.dart';
import '../core/models/table_model.dart';
import '../core/validate/validator.dart' show checkIdentifiers;
import 'seed_grid_editor.dart';
import 'theme.dart';

/// ชนิดดัชนีของคอลัมน์ในฟอร์ม (เหมือนช่อง Index ของ phpMyAdmin)
enum ColumnIndex { none, primary, unique, plain }

/// แท็บของกล่องสร้าง/แก้ตาราง (Phase 19)
enum TableDialogTab { columns, indexes, checks, seed }

String dataTypeName(DataType t) => switch (t) {
      DataType.integer => 'INT',
      _ => t.name.toUpperCase(),
    };

/// สถานะของคอลัมน์หนึ่งแถวในฟอร์ม
class ColumnDraft {
  ColumnDraft({
    String name = '',
    this.type = DataType.integer,
    String length = '',
    String defaultValue = '',
    this.allowNull = true,
    this.index = ColumnIndex.none,
    this.autoIncrement = false,
    String comment = '',
    List<String>? allowed,
    this.id,
    this.plainIndexId,
  })  : originalIndex = index,
        key = id ?? 'n${_seq++}',
        allowed = allowed ?? [],
        name = TextEditingController(text: name),
        length = TextEditingController(text: length),
        defaultValue = TextEditingController(text: defaultValue),
        comment = TextEditingController(text: comment);

  static int _seq = 0;

  final TextEditingController name, length, defaultValue, comment;

  /// id ของคอลัมน์เดิม (โหมดแก้ไข) — null = คอลัมน์ใหม่
  final String? id;

  /// คีย์ของคอลัมน์ในฟอร์ม (id เดิม หรือคีย์ชั่วคราวของคอลัมน์ใหม่) — ใช้เป็นคีย์ของข้อมูลตั้งต้นและดัชนีหลายคอลัมน์ระหว่างแก้
  final String key;

  /// id ของดัชนีธรรมดาคอลัมน์เดียวที่มีอยู่เดิม (โหมดแก้ไข)
  final String? plainIndexId;

  /// ชนิดดัชนีตอนเปิดฟอร์ม
  final ColumnIndex originalIndex;
  DataType type;
  bool allowNull;
  ColumnIndex index;
  bool autoIncrement;

  /// ค่าที่อนุญาต (Phase 19) — ว่าง = ไม่จำกัด ; ใช้ได้กับ varchar/text
  List<String> allowed;

  /// มีดัชนีธรรมดาอยู่เดิมแต่ฟอร์มแสดงเป็น PRIMARY/UNIQUE — ต้องคงดัชนีไว้ ไม่ให้หายเงียบ ๆ
  bool keepPlain = false;

  /// ร่างจากคอลัมน์เดิมของ [t] (โหมดแก้ไข)
  factory ColumnDraft.fromColumn(TableModel t, ColumnModel c) {
    IndexModel? plain;
    for (final i in t.indexes) {
      if (!i.unique && i.columnIds.length == 1 && i.columnIds.first == c.id) plain = i;
    }
    final idx = c.isPrimaryKey
        ? ColumnIndex.primary
        : c.unique
            ? ColumnIndex.unique
            : plain != null
                ? ColumnIndex.plain
                : ColumnIndex.none;
    final len = c.type == DataType.decimal && c.length != null
        ? '${c.length},${c.scale ?? 0}'
        : (c.length?.toString() ?? '');
    return ColumnDraft(
      name: c.name,
      type: c.type,
      length: len,
      defaultValue: c.defaultValue ?? '',
      allowNull: !c.notNull && !c.isPrimaryKey,
      index: idx,
      autoIncrement: c.autoIncrement,
      comment: c.comment,
      allowed: [...c.allowedValues],
      id: c.id,
      plainIndexId: plain?.id,
    )..keepPlain = plain != null && idx != ColumnIndex.plain;
  }

  bool get usesLength => type == DataType.varchar || type == DataType.decimal;
  bool get isIntegerType => type == DataType.integer || type == DataType.bigint || type == DataType.smallint;

  /// ชนิดนี้กำหนดค่าที่อนุญาตได้ (varchar/text)
  bool get supportsAllowed => ColumnModel.supportsAllowedValues(type);

  /// มีค่าที่อนุญาตที่ใช้งานได้จริง
  bool get hasAllowed => supportsAllowed && allowed.isNotEmpty;

  void dispose() {
    name.dispose();
    length.dispose();
    defaultValue.dispose();
    comment.dispose();
  }
}

/// CHECK ระดับตารางหนึ่งรายการในฟอร์ม
class CheckDraft {
  CheckDraft({this.id, String name = '', String expr = ''})
      : name = TextEditingController(text: name),
        expr = TextEditingController(text: expr);

  final String? id;
  final TextEditingController name, expr;

  void dispose() {
    name.dispose();
    expr.dispose();
  }
}

/// ดัชนีหลายคอลัมน์ (หรือ UNIQUE index) หนึ่งรายการในฟอร์ม — คอลัมน์อ้างด้วย [ColumnDraft.key] ตามลำดับ
class IndexDraft {
  IndexDraft({this.id, String name = '', List<String>? cols, this.unique = false})
      : name = TextEditingController(text: name),
        cols = cols ?? [];

  final String? id;
  final TextEditingController name;
  final List<String> cols;
  bool unique;

  void dispose() => name.dispose();
}

/// ตรวจความยาว/precision ที่กรอก — คืนข้อความไทยต้นฉบับของปัญหา หรือ null ถ้าใช้ได้
/// varchar: จำนวนเต็ม >= 1 (ว่าง = 255) ; decimal: `p` หรือ `p,s` โดย s <= p (ว่าง = 10,2)
String? validateLengthText(DataType type, String text) {
  final t = text.trim();
  if (type == DataType.varchar) {
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    return n == null || n < 1 ? 'ความยาวต้องเป็นจำนวนเต็มตั้งแต่ 1' : null;
  }
  if (type == DataType.decimal) {
    if (t.isEmpty) return null;
    final m = RegExp(r'^(\d+)(?:\s*,\s*(\d+))?$').firstMatch(t);
    if (m == null) return 'รูปแบบเป็น 10,2 (precision,scale)';
    final p = int.parse(m.group(1)!);
    final s = m.group(2) == null ? 0 : int.parse(m.group(2)!);
    return p < 1 || s > p ? 'scale ต้องไม่เกิน precision' : null;
  }
  return null;
}

/// ความยาว/ทศนิยมจากข้อความในช่อง — อ่านไม่ได้ = ไม่ระบุ (ใช้กับตัวอย่าง SQL ที่ต้องไม่โยน error ระหว่างพิมพ์)
(int?, int?) _lengthOf(DataType type, String text) {
  final lt = text.trim();
  if (lt.isEmpty || validateLengthText(type, lt) != null) return (null, null);
  if (type == DataType.varchar) return (int.parse(lt), null);
  if (type == DataType.decimal) {
    final parts = lt.split(',').map((e) => int.parse(e.trim())).toList();
    return (parts[0], parts.length > 1 ? parts[1] : 0);
  }
  return (null, null);
}

/// แปลงฟอร์มเป็นตาราง (id ของคอลัมน์/ดัชนีสร้างจาก [newId])
/// PRIMARY หลายแถว = PK ผสม; INDEX = ดัชนีธรรมดาแยกต่อคอลัมน์
///
/// [checks] = CHECK ระดับตาราง (รายการที่ไม่มีนิพจน์ถูกข้าม) ;
/// [indexDrafts] = ดัชนีหลายคอลัมน์จากแท็บดัชนี — ไม่ส่ง (null) = คงดัชนีหลายคอลัมน์/UNIQUE index เดิมของ [existing] ไว้ตามเดิม ;
/// [seedRows] = ข้อมูลตั้งต้น โดยคีย์ของแต่ละช่องคือ [ColumnDraft.key] — ไม่ส่ง = คงของเดิม
TableModel buildTableFromDrafts({
  required String Function(String prefix) newId,
  required String name,
  required String comment,
  required List<ColumnDraft> drafts,
  TableModel? existing,
  List<CheckDraft> checks = const [],
  List<IndexDraft>? indexDrafts,
  List<Map<String, String?>>? seedRows,
}) {
  final cols = <ColumnModel>[];
  final indexes = <IndexModel>[];
  final keyToId = <String, String>{};
  final tableName = name.trim();
  for (final d in drafts) {
    final isPk = d.index == ColumnIndex.primary;
    int? len;
    int? scale;
    final lt = d.length.text.trim();
    if (d.type == DataType.varchar && lt.isNotEmpty) len = int.parse(lt);
    if (d.type == DataType.decimal && lt.isNotEmpty) {
      final parts = lt.split(',').map((e) => int.parse(e.trim())).toList();
      len = parts[0];
      scale = parts.length > 1 ? parts[1] : 0;
    }
    final dv = d.defaultValue.text.trim();
    final col = ColumnModel(
      id: d.id ?? newId('c'),
      name: d.name.text.trim(),
      type: d.type,
      length: len,
      scale: scale,
      isPrimaryKey: isPk,
      notNull: isPk || !d.allowNull,
      unique: d.index == ColumnIndex.unique,
      autoIncrement: d.autoIncrement,
      defaultValue: dv.isEmpty ? null : dv,
      comment: d.comment.text.trim(),
      allowedValues: d.supportsAllowed ? [...d.allowed] : [],
    );
    cols.add(col);
    keyToId[d.key] = col.id;
    if (d.index == ColumnIndex.plain || (d.keepPlain && d.plainIndexId != null)) {
      indexes.add(IndexModel(id: d.plainIndexId ?? newId('i'), name: 'idx_${tableName}_${col.name}', columnIds: [col.id]));
    }
  }
  if (indexDrafts != null) {
    for (final x in indexDrafts) {
      final ids = [for (final k in x.cols) ?keyToId[k]];
      if (ids.isEmpty) continue;
      final n = x.name.text.trim();
      indexes.add(IndexModel(id: x.id ?? newId('i'), name: n.isEmpty ? 'idx_${tableName}_${ids.length}' : n, columnIds: ids, unique: x.unique));
    }
  } else if (existing != null) {
    // ดัชนีหลายคอลัมน์ / UNIQUE index เดิมคงไว้ (ตัดคอลัมน์ที่ถูกลบออก) — ฟอร์มนี้แก้ได้เฉพาะดัชนีคอลัมน์เดียว
    final keptIds = {for (final c in cols) c.id};
    final plainIds = {for (final d in drafts) if (d.plainIndexId != null) d.plainIndexId};
    for (final i in existing.indexes) {
      if (plainIds.contains(i.id)) continue;
      final ids = [for (final id in i.columnIds) if (keptIds.contains(id)) id];
      if (ids.isEmpty) continue;
      indexes.add(IndexModel(id: i.id, name: i.name, columnIds: ids, unique: i.unique));
    }
  }
  final builtChecks = [
    for (final k in checks)
      if (k.expr.text.trim().isNotEmpty) CheckModel(id: k.id ?? newId('k'), name: k.name.text.trim(), expr: k.expr.text.trim()),
  ];
  final seed = seedRows == null
      ? [for (final r in existing?.seedRows ?? const <Map<String, String?>>[]) Map<String, String?>.of(r)]
      : [
          for (final r in seedRows)
            {for (final e in r.entries) keyToId[e.key] ?? e.key: e.value},
        ];
  return TableModel(
    id: existing?.id ?? newId('t'),
    name: tableName,
    comment: comment.trim(),
    columns: cols,
    indexes: indexes,
    checks: builtChecks,
    seedRows: seed,
  );
}

/// สร้างตารางแบบฟอร์ม เหมือนหน้า "Create table" ของ phpMyAdmin:
/// ตั้งชื่อ กำหนดจำนวนคอลัมน์ แล้วกรอกชื่อ/ชนิด/ความยาว/ค่าเริ่มต้น/Null/Index/A_I/ค่าที่อนุญาต/หมายเหตุ + ดัชนี + CHECK + ข้อมูลตั้งต้น
/// คืนตารางที่สร้างเสร็จ (ยังไม่ได้เพิ่มเข้าโปรเจกต์) หรือ null ถ้ายกเลิก
/// [dialect] ใช้แสดงตัวอย่าง SQL ; [project] ใช้ตรวจข้อมูลตั้งต้น (FK ฯลฯ)
Future<TableModel?> showCreateTableDialog(
  BuildContext context, {
  required String Function(String) newId,
  Dialect dialect = Dialect.mysql,
  Project? project,
}) =>
    showDialog<TableModel>(context: context, builder: (_) => CreateTableDialog(newId: newId, dialect: dialect, project: project));

/// แก้โครงสร้างตารางที่มีอยู่ด้วยฟอร์มเดียวกัน คืนตารางใหม่ (id ตาราง/คอลัมน์เดิมคงไว้) หรือ null ถ้ายกเลิก
/// [relationCount] คืนจำนวนเส้น FK ที่ผูกกับคอลัมน์ ใช้เตือนก่อนลบคอลัมน์
Future<TableModel?> showEditTableDialog(
  BuildContext context, {
  required TableModel table,
  required String Function(String) newId,
  required int Function(String columnId) relationCount,
  List<String> otherTableNames = const [],
  Dialect dialect = Dialect.mysql,
  Project? project,
  TableDialogTab initialTab = TableDialogTab.columns,
}) =>
    showDialog<TableModel>(
      context: context,
      builder: (_) => CreateTableDialog(
        newId: newId,
        editing: table,
        relationCount: relationCount,
        otherTableNames: otherTableNames,
        dialect: dialect,
        project: project,
        initialTab: initialTab,
      ),
    );

class CreateTableDialog extends StatefulWidget {
  const CreateTableDialog({
    super.key,
    required this.newId,
    this.initialColumns = 4,
    this.editing,
    this.relationCount,
    this.otherTableNames = const [],
    this.dialect = Dialect.mysql,
    this.project,
    this.initialTab = TableDialogTab.columns,
  });
  final String Function(String prefix) newId;
  final int initialColumns;

  /// ตารางที่กำลังแก้ (null = สร้างใหม่)
  final TableModel? editing;
  final int Function(String columnId)? relationCount;
  final List<String> otherTableNames;
  final Dialect dialect;

  /// โปรเจกต์ (ใช้ตรวจข้อมูลตั้งต้นของแท็บ "ข้อมูลตั้งต้น") — ไม่ส่ง = โปรเจกต์เปล่าตาม [dialect]
  final Project? project;
  final TableDialogTab initialTab;

  @override
  State<CreateTableDialog> createState() => _CreateTableDialogState();
}

class _CreateTableDialogState extends State<CreateTableDialog> {
  static const _maxColumns = 100;
  final _name = TextEditingController();
  final _comment = TextEditingController();
  final _count = TextEditingController();
  final _drafts = <ColumnDraft>[];
  final _checks = <CheckDraft>[];
  final _indexes = <IndexDraft>[];
  final _open = <ColumnDraft>{}; // แถวที่ขยายรายละเอียด
  final _allowedInput = <ColumnDraft, TextEditingController>{};
  var _seed = <Map<String, String?>>[];
  var _seedProblems = 0;
  var _tab = TableDialogTab.columns;
  /// null = อัตโนมัติ : เปิดเมื่อหน้าต่างสูงพอ (ตามดีไซน์ เปิดเป็นค่าเริ่มต้น) ปิดเมื่อหน้าต่างเตี้ยเพื่อให้รายการคอลัมน์มีที่พอ ; ผู้ใช้กดสลับแล้วใช้ค่านั้น
  bool? _sqlOpenChoice;

  bool get _sqlOpen => _sqlOpenChoice ?? MediaQuery.sizeOf(context).height >= 780;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    final e = widget.editing;
    if (e != null) {
      _name.text = e.name;
      _comment.text = e.comment;
      for (final c in e.columns) {
        _drafts.add(ColumnDraft.fromColumn(e, c));
      }
      if (_drafts.isEmpty) _drafts.add(ColumnDraft());
      _count.text = '${_drafts.length}';
      for (final k in e.checks) {
        _checks.add(CheckDraft(id: k.id, name: k.name, expr: k.expr));
      }
      final plainIds = {for (final d in _drafts) if (d.plainIndexId != null) d.plainIndexId};
      for (final i in e.indexes) {
        if (plainIds.contains(i.id)) continue; // ดัชนีธรรมดาคอลัมน์เดียว = ช่อง Index ในตารางคอลัมน์
        _indexes.add(IndexDraft(id: i.id, name: i.name, cols: [...i.columnIds], unique: i.unique));
      }
      _seed = [for (final r in e.seedRows) Map<String, String?>.of(r)];
      for (final d in _drafts) {
        if (d.hasAllowed) _open.add(d);
      }
      return;
    }
    _drafts.add(ColumnDraft(
      name: 'id',
      allowNull: false,
      index: ColumnIndex.primary,
      autoIncrement: true,
    ));
    _resize(widget.initialColumns);
  }

  @override
  void dispose() {
    _name.dispose();
    _comment.dispose();
    _count.dispose();
    for (final d in _drafts) {
      d.dispose();
    }
    for (final k in _checks) {
      k.dispose();
    }
    for (final x in _indexes) {
      x.dispose();
    }
    for (final c in _allowedInput.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// ปรับจำนวนแถว: เพิ่มต่อท้าย / ตัดจากท้าย (ข้อมูลแถวที่เหลือคงเดิม)
  void _resize(int n) {
    n = n.clamp(1, _maxColumns);
    while (_drafts.length < n) {
      _drafts.add(ColumnDraft());
    }
    while (_drafts.length > n) {
      _forget(_drafts.removeLast());
    }
    _count.text = '$n';
  }

  void _forget(ColumnDraft d) {
    _open.remove(d);
    _allowedInput.remove(d)?.dispose();
    for (final x in _indexes) {
      x.cols.remove(d.key);
    }
    d.dispose();
  }

  void _applyCount() {
    final n = int.tryParse(_count.text.trim());
    if (n == null) return;
    setState(() => _resize(n));
  }

  void _remove(int i) {
    if (_drafts.length <= 1) return;
    setState(() {
      _forget(_drafts.removeAt(i));
      _count.text = '${_drafts.length}';
    });
  }

  // ---------- ตรวจความถูกต้อง ----------

  bool get _editing => widget.editing != null;

  String? get _nameError {
    final n = _name.text.trim();
    if (n.isEmpty) return tr('ต้องตั้งชื่อตาราง');
    final dup = widget.otherTableNames.any((o) => o.toLowerCase() == n.toLowerCase());
    return dup ? tr('ชื่อซ้ำกับตารางอื่น') : null;
  }

  String? _colNameError(int i) {
    final n = _drafts[i].name.text.trim();
    if (n.isEmpty) return tr('ต้องตั้งชื่อ');
    final dup = _drafts.indexed.any((e) => e.$1 != i && e.$2.name.text.trim().toLowerCase() == n.toLowerCase());
    return dup ? tr('ชื่อซ้ำ') : null;
  }

  String? _lengthError(int i) {
    final e = validateLengthText(_drafts[i].type, _drafts[i].length.text);
    return e == null ? null : tr(e);
  }

  String? _aiError(int i) {
    final d = _drafts[i];
    if (!d.autoIncrement) return null;
    return d.isIntegerType ? null : tr('A_I ใช้ได้กับชนิดจำนวนเต็มเท่านั้น');
  }

  /// ค่าเริ่มต้นต้องอยู่ในรายการค่าที่อนุญาต (ถ้ามี)
  String? _defaultError(int i) {
    final d = _drafts[i];
    if (!d.hasAllowed) return null;
    final v = d.defaultValue.text.trim();
    if (v.isEmpty || v.toUpperCase() == 'NULL') return null;
    final unq = v.length >= 2 && v.startsWith("'") && v.endsWith("'") ? v.substring(1, v.length - 1) : v;
    return d.allowed.contains(unq) ? null : tr('ไม่อยู่ในค่าที่อนุญาต');
  }

  /// ชื่อ CHECK ซ้ำกันในตารางเดียวกัน (ชื่อว่างไม่นับ)
  String? _checkNameError(int i) {
    final n = _checks[i].name.text.trim().toLowerCase();
    if (n.isEmpty) return null;
    final dup = _checks.indexed.any((e) => e.$1 != i && e.$2.name.text.trim().toLowerCase() == n);
    return dup ? tr('ชื่อซ้ำ') : null;
  }

  String? _indexError(int i) {
    final x = _indexes[i];
    if (x.name.text.trim().isEmpty) return tr('ต้องตั้งชื่อดัชนี');
    final dup = _indexes.indexed.any((e) => e.$1 != i && e.$2.name.text.trim().toLowerCase() == x.name.text.trim().toLowerCase());
    if (dup) return tr('ชื่อซ้ำ');
    return x.cols.isEmpty ? tr('เลือกคอลัมน์อย่างน้อย 1') : null;
  }

  bool get _valid =>
      _nameError == null &&
      _drafts.isNotEmpty &&
      [for (var i = 0; i < _drafts.length; i++) i].every(
        (i) => _colNameError(i) == null && _lengthError(i) == null && _aiError(i) == null && _defaultError(i) == null,
      ) &&
      [for (var i = 0; i < _checks.length; i++) i].every((i) => _checkNameError(i) == null) &&
      [for (var i = 0; i < _indexes.length; i++) i].every((i) => _indexError(i) == null);

  Future<void> _save() async {
    if (!_valid) return;
    final e = widget.editing;
    if (e != null) {
      // คอลัมน์เดิมที่หายไปจากฟอร์ม = ถูกลบ ; เตือนถ้ามี FK ผูกอยู่
      final kept = {for (final d in _drafts) d.id};
      var rels = 0;
      final dropped = <String>[];
      for (final c in e.columns) {
        if (kept.contains(c.id)) continue;
        dropped.add(c.name);
        rels += widget.relationCount?.call(c.id) ?? 0;
      }
      if (dropped.isNotEmpty) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('ลบ {0} คอลัมน์?', [dropped.length])),
            content: Text(rels > 0
                ? tr('คอลัมน์ {0} จะถูกลบ พร้อมความสัมพันธ์ FK {1} เส้นที่ผูกอยู่ (ย้อนกลับได้ด้วย Undo)', [dropped.join(', '), rels])
                : tr('คอลัมน์ {0} จะถูกลบ (ย้อนกลับได้ด้วย Undo)', [dropped.join(', ')])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ลบและบันทึก'))),
            ],
          ),
        );
        if (ok != true || !mounted) return;
      }
    }
    Navigator.pop(
      context,
      buildTableFromDrafts(
        newId: widget.newId,
        name: _name.text,
        comment: _comment.text,
        drafts: _drafts,
        existing: e,
        checks: _checks,
        indexDrafts: _indexes,
        seedRows: _seed,
      ),
    );
  }

  // ---------- ตารางจำลอง (ตัวอย่าง SQL + แท็บข้อมูลตั้งต้น) ----------

  /// ตารางจากค่าที่กรอกอยู่ตอนนี้ — ทนค่าที่ยังไม่ครบ/ผิด (ไม่โยน error) ; id ของคอลัมน์ = [ColumnDraft.key]
  TableModel _preview() {
    final tn = _name.text.trim().isEmpty ? 'table_name' : _name.text.trim();
    final cols = <ColumnModel>[
      for (final d in _drafts)
        () {
          final (len, scale) = _lengthOf(d.type, d.length.text);
          final dv = d.defaultValue.text.trim();
          final isPk = d.index == ColumnIndex.primary;
          return ColumnModel(
            id: d.key,
            name: d.name.text.trim().isEmpty ? 'column' : d.name.text.trim(),
            type: d.type,
            length: len,
            scale: scale,
            isPrimaryKey: isPk,
            notNull: isPk || !d.allowNull,
            unique: d.index == ColumnIndex.unique,
            autoIncrement: d.autoIncrement,
            defaultValue: dv.isEmpty ? null : dv,
            comment: d.comment.text.trim(),
            allowedValues: d.supportsAllowed ? [...d.allowed] : [],
          );
        }(),
    ];
    return TableModel(
      id: widget.editing?.id ?? '_new',
      name: tn,
      comment: _comment.text.trim(),
      columns: cols,
      checks: [
        for (var i = 0; i < _checks.length; i++)
          if (_checks[i].expr.text.trim().isNotEmpty) CheckModel(id: 'k$i', name: _checks[i].name.text.trim(), expr: _checks[i].expr.text.trim()),
      ],
    );
  }

  Project get _project => widget.project ?? Project(name: 'new', dialect: widget.dialect);

  String _sqlText() {
    final t = _preview();
    final p = Project(name: 'preview', dialect: widget.dialect, tables: [t]);
    return DdlGenerator.forDialect(widget.dialect).createTable(p, t, const {});
  }

  /// เปลี่ยนเมื่อคอลัมน์/ค่าที่อนุญาตเปลี่ยน -> ตารางข้อมูลตั้งต้นสร้างใหม่ (แถวคงอยู่ทาง [_seed])
  String _seedSignature() => [
        for (final d in _drafts) '${d.key}|${d.name.text}|${d.type.name}|${d.allowNull}|${d.index.name}|${d.autoIncrement}|${d.defaultValue.text}|${d.hasAllowed ? d.allowed.join('\u0001') : ''}',
      ].join('\n');

  // ---------- UI ----------

  static const _wTog = 30.0, _wName = 150.0, _wType = 118.0, _wLen = 84.0, _wDef = 122.0;
  static const _wNull = 52.0, _wIndex = 106.0, _wAi = 48.0, _wEnum = 78.0, _wDel = 36.0;
  static const _rowWidth = _wTog + _wName + _wType + _wLen + _wDef + _wNull + _wIndex + _wAi + _wEnum + _wDel + 8 * 9;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        // สูงตามหน้าต่าง (เหลือขอบ 20 บน-ล่าง) ไม่เกิน 900 — รายการคอลัมน์ต้องมีที่พอเมื่อเปิดแถบตัวอย่าง SQL
        constraints: BoxConstraints(maxWidth: 1040, maxHeight: (MediaQuery.sizeOf(context).height - 40).clamp(420.0, 900.0)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_editing ? tr('แก้ไขโครงสร้างตาราง') : tr('สร้างตาราง'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
                _editing
                    ? tr('แก้คอลัมน์ ดัชนี CHECK และข้อมูลตั้งต้นของตารางในกล่องเดียว ดูตัวอย่าง SQL ด้านล่าง แล้วกดบันทึก')
                    : tr('กรอกชื่อตารางและรายละเอียดของทุกคอลัมน์ในครั้งเดียว ดูตัวอย่าง SQL ด้านล่าง แล้วกดสร้าง'),
                style: TextStyle(fontSize: 12.5, color: C.muted)),
            const SizedBox(height: 12),
            Wrap(spacing: 14, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.start, children: [
              SizedBox(width: 260, child: _field(_name, tr('ชื่อตาราง'), 'ct-table-name', error: _nameError)),
              SizedBox(width: 300, child: _field(_comment, tr('หมายเหตุตาราง (ไม่บังคับ)'), 'ct-table-comment')),
              SizedBox(
                width: 210,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('ct-count'),
                      controller: _count,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onSubmitted: (_) => _applyCount(),
                      decoration: InputDecoration(
                        labelText: tr('จำนวนคอลัมน์'),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    key: const ValueKey('ct-apply-count'),
                    onPressed: _applyCount,
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 12)),
                    child: Text(tr('ตกลง')),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            _tabBar(),
            const SizedBox(height: 10),
            Flexible(child: _tabBody()),
            const SizedBox(height: 8),
            _sqlBar(),
            const SizedBox(height: 8),
            Row(children: [
              if (_tab == TableDialogTab.columns)
                TextButton.icon(
                  key: const ValueKey('ct-add'),
                  onPressed: _drafts.length >= _maxColumns ? null : () => setState(() => _resize(_drafts.length + 1)),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(tr('เพิ่มคอลัมน์')),
                ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('ct-save'),
                onPressed: _valid ? () => _save() : null,
                child: Text(_editing ? tr('บันทึก') : tr('สร้าง')),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String key, {String? error}) => TextField(
        key: ValueKey(key),
        controller: c,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          errorText: error,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  // ---------- แท็บ ----------

  Widget _tabBar() {
    Widget tab(TableDialogTab t, String key, String label, int n, {bool bad = false}) {
      final on = _tab == t;
      return InkWell(
        key: ValueKey(key),
        onTap: () => setState(() => _tab = t),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? C.primary : Colors.transparent, width: 2))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w600 : FontWeight.w400, color: on ? C.primaryDark : C.muted)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(color: bad ? C.dangerBg : C.field, borderRadius: BorderRadius.circular(99)),
              child: Text('$n', style: TextStyle(fontSize: 11, color: bad ? C.dangerText : C.muted)),
            ),
          ]),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.borderSoft))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          tab(TableDialogTab.columns, 'ct-tab-columns', tr('คอลัมน์'), _drafts.length),
          tab(TableDialogTab.indexes, 'ct-tab-indexes', tr('ดัชนี'), _indexes.length),
          tab(TableDialogTab.checks, 'ct-tab-checks', 'CHECK', _checks.where((k) => k.expr.text.trim().isNotEmpty).length),
          tab(TableDialogTab.seed, 'ct-tab-seed', tr('ข้อมูลตั้งต้น'), _seed.length, bad: _seedProblems > 0),
        ]),
      ),
    );
  }

  Widget _tabBody() => switch (_tab) {
        TableDialogTab.columns => _columnsTab(),
        TableDialogTab.indexes => _indexesTab(),
        TableDialogTab.checks => _checksTab(),
        TableDialogTab.seed => _seedTab(),
      };

  // ---------- แท็บ: คอลัมน์ (แบบ C แถวขยายได้) ----------

  Widget _columnsTab() => Container(
        decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: _rowWidth + 24,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _headerRow(),
              Flexible(
                // สร้างทุกแถวพร้อมกัน (ไม่เกิน 100 แถว) แทนรายการแบบสร้างเมื่อเลื่อนถึง : ทุกช่องอยู่ในต้นไม้วิดเจ็ตเสมอ (ทดสอบ/โฟกัสข้ามแถวไม่หลุด)
                child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < _drafts.length; i++) ...[
                      _columnRow(i),
                      if (_open.contains(_drafts[i])) _detailRow(i),
                    ],
                  ]),
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _headerRow() {
    Widget h(String t, double w) => SizedBox(
          width: w,
          child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.muted)),
        );
    return Container(
      color: C.field,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(children: [
        h('', _wTog),
        const SizedBox(width: 8),
        h(tr('ชื่อ'), _wName),
        const SizedBox(width: 8),
        h(tr('ชนิด'), _wType),
        const SizedBox(width: 8),
        h(tr('ความยาว'), _wLen),
        const SizedBox(width: 8),
        h(tr('ค่าเริ่มต้น'), _wDef),
        const SizedBox(width: 8),
        h('Null', _wNull),
        const SizedBox(width: 8),
        h('Index', _wIndex),
        const SizedBox(width: 8),
        h('A_I', _wAi),
        const SizedBox(width: 8),
        h(tr('ค่าจำกัด'), _wEnum),
        const SizedBox(width: 8),
        const SizedBox(width: _wDel),
      ]),
    );
  }

  InputDecoration _dec({String? error, String? hint}) => InputDecoration(
        isDense: true,
        hintText: hint,
        errorText: error,
        errorStyle: const TextStyle(fontSize: 10.5, height: 1),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        border: const OutlineInputBorder(),
      );

  /// ช่องค่าเริ่มต้น: มีค่าที่อนุญาต = เลือกจากรายการ (ค่าที่ตกรายการแสดงเป็นแดง) ไม่งั้นพิมพ์เอง
  Widget _defaultField(int i, ColumnDraft d) {
    if (!d.hasAllowed) {
      return TextField(
        key: ValueKey('ct-default-$i'),
        controller: d.defaultValue,
        onChanged: (_) => setState(() {}),
        style: monoStyle.copyWith(fontSize: 12.5),
        decoration: _dec(hint: tr('ไม่มี')),
      );
    }
    final cur = d.defaultValue.text.trim();
    final extra = cur.isNotEmpty && !d.allowed.contains(cur) ? cur : null;
    return DropdownButtonFormField<String>(
      key: ValueKey('ct-default-$i-${d.allowed.length}-${extra ?? ''}'),
      initialValue: cur.isEmpty || d.allowed.contains(cur) || extra != null ? cur : '',
      isDense: true,
      isExpanded: true,
      decoration: _dec(error: _defaultError(i)),
      style: monoStyle.copyWith(fontSize: 12.5, color: C.text),
      items: [
        DropdownMenuItem(value: '', child: Text(tr('ไม่มี'), style: TextStyle(color: C.muted, fontSize: 12))),
        for (final v in d.allowed) DropdownMenuItem(value: v, child: Text(v)),
        if (extra != null) DropdownMenuItem(value: extra, child: Text(extra, style: TextStyle(color: C.danger))),
      ],
      onChanged: (v) => setState(() => d.defaultValue.text = v ?? ''),
    );
  }

  Widget _columnRow(int i) {
    final d = _drafts[i];
    const gap = SizedBox(width: 8);
    final open = _open.contains(d);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: C.borderSoft))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: _wTog,
          child: IconButton(
            key: ValueKey('ct-expand-$i'),
            tooltip: open ? tr('ซ่อนรายละเอียด') : tr('รายละเอียด: ค่าที่อนุญาต หมายเหตุ'),
            iconSize: 20,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => open ? _open.remove(d) : _open.add(d)),
            icon: Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded, color: C.muted),
          ),
        ),
        gap,
        SizedBox(
          width: _wName,
          child: TextField(
            key: ValueKey('ct-name-$i'),
            controller: d.name,
            onChanged: (_) => setState(() {}),
            style: monoStyle.copyWith(fontSize: 12.5),
            decoration: _dec(error: _colNameError(i), hint: 'column_${i + 1}'),
          ),
        ),
        gap,
        SizedBox(
          width: _wType,
          child: DropdownButtonFormField<DataType>(
            key: ValueKey('ct-type-$i'),
            initialValue: d.type,
            isDense: true,
            isExpanded: true,
            decoration: _dec(),
            style: TextStyle(fontSize: 12.5, color: C.text, fontFamily: kThai),
            items: [
              for (final t in DataType.values) DropdownMenuItem(value: t, child: Text(dataTypeName(t))),
            ],
            onChanged: (t) => setState(() {
              if (t == null) return;
              d.type = t;
              if (!d.isIntegerType) d.autoIncrement = false;
              if (!d.usesLength) d.length.clear();
              if (!d.supportsAllowed) d.allowed.clear(); // ชนิดนี้ไม่มีค่าที่อนุญาต
            }),
          ),
        ),
        gap,
        SizedBox(
          width: _wLen,
          child: TextField(
            key: ValueKey('ct-len-$i'),
            controller: d.length,
            enabled: d.usesLength,
            onChanged: (_) => setState(() {}),
            style: monoStyle.copyWith(fontSize: 12.5),
            decoration: _dec(
              error: _lengthError(i),
              hint: d.type == DataType.decimal ? '10,2' : (d.type == DataType.varchar ? '255' : '—'),
            ),
          ),
        ),
        gap,
        SizedBox(width: _wDef, child: _defaultField(i, d)),
        gap,
        SizedBox(
          width: _wNull,
          child: Checkbox(
            key: ValueKey('ct-null-$i'),
            value: d.allowNull && d.index != ColumnIndex.primary,
            // PRIMARY บังคับ NOT NULL
            onChanged: d.index == ColumnIndex.primary ? null : (v) => setState(() => d.allowNull = v ?? true),
          ),
        ),
        gap,
        SizedBox(
          width: _wIndex,
          child: DropdownButtonFormField<ColumnIndex>(
            key: ValueKey('ct-index-$i'),
            initialValue: d.index,
            isDense: true,
            isExpanded: true,
            decoration: _dec(),
            style: TextStyle(fontSize: 12.5, color: C.text, fontFamily: kThai),
            items: const [
              DropdownMenuItem(value: ColumnIndex.none, child: Text('—')),
              DropdownMenuItem(value: ColumnIndex.primary, child: Text('PRIMARY')),
              DropdownMenuItem(value: ColumnIndex.unique, child: Text('UNIQUE')),
              DropdownMenuItem(value: ColumnIndex.plain, child: Text('INDEX')),
            ],
            onChanged: (v) => setState(() {
              d.index = v ?? ColumnIndex.none;
              if (d.index == ColumnIndex.primary) d.allowNull = false;
            }),
          ),
        ),
        gap,
        SizedBox(
          width: _wAi,
          child: Column(children: [
            Checkbox(
              key: ValueKey('ct-ai-$i'),
              value: d.autoIncrement,
              onChanged: d.isIntegerType ? (v) => setState(() => d.autoIncrement = v ?? false) : null,
            ),
          ]),
        ),
        gap,
        SizedBox(
          width: _wEnum,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: d.hasAllowed
                ? InkWell(
                    key: ValueKey('ct-enum-badge-$i'),
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => setState(() => _open.add(d)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: C.palette.infoBg, borderRadius: BorderRadius.circular(4)),
                      child: Text('ENUM ${d.allowed.length}', style: monoStyle.copyWith(fontSize: 10.5, fontWeight: FontWeight.w700, color: C.palette.infoText)),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
        gap,
        SizedBox(
          width: _wDel,
          child: IconButton(
            key: ValueKey('ct-remove-$i'),
            tooltip: tr('ลบคอลัมน์นี้'),
            iconSize: 17,
            padding: EdgeInsets.zero,
            onPressed: _drafts.length <= 1 ? null : () => _remove(i),
            icon: Icon(Icons.delete_outline, color: C.danger),
          ),
        ),
      ]),
    );
  }

  /// แถบรายละเอียดใต้แถว: ค่าที่อนุญาต (varchar/text) + หมายเหตุ
  Widget _detailRow(int i) {
    final d = _drafts[i];
    return Container(
      key: ValueKey('ct-detail-$i'),
      width: double.infinity,
      color: C.field,
      padding: const EdgeInsets.fromLTRB(52, 8, 16, 12),
      child: Wrap(spacing: 24, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.start, children: [
        SizedBox(
          width: 430,
          child: d.supportsAllowed
              ? _allowedEditor(i, d)
              : Text(tr('ค่าที่อนุญาตใช้ได้กับ VARCHAR / TEXT'), style: TextStyle(fontSize: 12, color: C.muted)),
        ),
        SizedBox(
          width: 300,
          child: TextField(
            key: ValueKey('ct-comment-$i'),
            controller: d.comment,
            decoration: _dec().copyWith(labelText: tr('หมายเหตุ')),
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
      ]),
    );
  }

  void _addAllowed(int i, ColumnDraft d, String raw) {
    final v = raw.trim();
    if (v.isEmpty) return;
    if (d.allowed.contains(v)) {
      _allowedInput[d]?.clear();
      return;
    }
    setState(() {
      d.allowed.add(v);
      _allowedInput[d]?.clear();
    });
  }

  Widget _allowedEditor(int i, ColumnDraft d) {
    final input = _allowedInput.putIfAbsent(d, TextEditingController.new);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('ค่าที่อนุญาต (ENUM)'), style: TextStyle(fontSize: 11.5, color: C.muted)),
      const SizedBox(height: 4),
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (var j = 0; j < d.allowed.length; j++)
          Container(
            padding: const EdgeInsets.fromLTRB(10, 1, 2, 1),
            decoration: BoxDecoration(color: C.palette.infoBg, borderRadius: BorderRadius.circular(99)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(d.allowed[j], style: monoStyle.copyWith(fontSize: 12, color: C.palette.infoText)),
              InkWell(
                key: ValueKey('ct-allowed-rm-$i-$j'),
                borderRadius: BorderRadius.circular(99),
                onTap: () => setState(() => d.allowed.removeAt(j)),
                child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 13, color: C.palette.infoText)),
              ),
            ]),
          ),
        SizedBox(
          width: 170,
          child: TextField(
            key: ValueKey('ct-allowed-add-$i'),
            controller: input,
            onSubmitted: (v) => _addAllowed(i, d, v),
            onChanged: (v) {
              // วางหลายค่าคั่นด้วยจุลภาค/ขึ้นบรรทัดใหม่ = เพิ่มทีเดียว
              if (v.contains(',') || v.contains('\n')) {
                for (final part in v.split(RegExp(r'[,\n]'))) {
                  _addAllowed(i, d, part);
                }
              }
            },
            style: monoStyle.copyWith(fontSize: 12),
            decoration: _dec(hint: tr('+ เพิ่มค่า แล้วกด Enter')),
          ),
        ),
      ]),
      const SizedBox(height: 3),
      Text(
        d.allowed.isEmpty ? tr('เว้นว่าง = รับค่าอะไรก็ได้') : (widget.dialect == Dialect.mysql ? tr('MySQL/MariaDB: สร้างเป็นชนิด ENUM(...)') : tr('สร้างเป็น CHECK (คอลัมน์ IN (...))')),
        style: TextStyle(fontSize: 11, color: C.muted),
      ),
    ]);
  }

  // ---------- แท็บ: ดัชนี ----------

  Widget _indexesTab() => Container(
        decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              tr('ดัชนีหลายคอลัมน์ (และ UNIQUE หลายคอลัมน์) ลำดับคอลัมน์มีผลกับการค้นหา — ดัชนีคอลัมน์เดียวตั้งที่ช่อง Index ในแท็บคอลัมน์'),
              style: TextStyle(fontSize: 12.5, color: C.muted),
            ),
            const SizedBox(height: 10),
            if (_indexes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(tr('ยังไม่มีดัชนีหลายคอลัมน์'), key: const ValueKey('ct-index-empty'), style: TextStyle(color: C.muted)),
              ),
            for (var i = 0; i < _indexes.length; i++) _indexCard(i),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              key: const ValueKey('ct-idx-add'),
              onPressed: () => setState(() => _indexes.add(IndexDraft(name: 'idx_${_name.text.trim().isEmpty ? 'table' : _name.text.trim()}_${_indexes.length + 1}'))),
              icon: const Icon(Icons.add, size: 16),
              label: Text(tr('เพิ่มดัชนี')),
            ),
          ]),
        ),
      );

  String _colNameOfKey(String key) {
    for (final d in _drafts) {
      if (d.key == key) return d.name.text.trim().isEmpty ? '(?)' : d.name.text.trim();
    }
    return '?';
  }

  Widget _indexCard(int i) {
    final x = _indexes[i];
    final free = [for (final d in _drafts) if (!x.cols.contains(d.key)) d];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(
            width: 260,
            child: TextField(
              key: ValueKey('ct-idx-name-$i'),
              controller: x.name,
              onChanged: (_) => setState(() {}),
              style: monoStyle.copyWith(fontSize: 12.5),
              decoration: _dec(error: _indexError(i) == tr('ต้องตั้งชื่อดัชนี') || _indexError(i) == tr('ชื่อซ้ำ') ? _indexError(i) : null).copyWith(labelText: tr('ชื่อดัชนี')),
            ),
          ),
          const SizedBox(width: 12),
          Checkbox(key: ValueKey('ct-idx-unique-$i'), value: x.unique, onChanged: (v) => setState(() => x.unique = v ?? false)),
          const Text('UNIQUE'),
          const Spacer(),
          IconButton(
            key: ValueKey('ct-idx-del-$i'),
            tooltip: tr('ลบดัชนีนี้'),
            iconSize: 18,
            onPressed: () => setState(() => _indexes.removeAt(i).dispose()),
            icon: Icon(Icons.delete_outline, color: C.danger),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (var j = 0; j < x.cols.length; j++)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 1, 2, 1),
              decoration: BoxDecoration(color: C.primaryTint, borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${j + 1}. ${_colNameOfKey(x.cols[j])}', style: monoStyle.copyWith(fontSize: 12, color: C.primaryDark)),
                InkWell(
                  key: ValueKey('ct-idx-col-rm-$i-$j'),
                  borderRadius: BorderRadius.circular(99),
                  onTap: () => setState(() => x.cols.removeAt(j)),
                  child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 13, color: C.primaryDark)),
                ),
              ]),
            ),
          if (free.isNotEmpty)
            PopupMenuButton<ColumnDraft>(
              key: ValueKey('ct-idx-col-add-$i'),
              tooltip: tr('เพิ่มคอลัมน์'),
              onSelected: (d) => setState(() => x.cols.add(d.key)),
              itemBuilder: (_) => [
                for (final d in free)
                  PopupMenuItem(value: d, height: 34, child: Text(d.name.text.trim().isEmpty ? '(?)' : d.name.text.trim(), style: monoStyle.copyWith(fontSize: 12.5))),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(tr('+ เลือกคอลัมน์ ▾'), style: TextStyle(fontSize: 12.5, color: C.primaryDark)),
              ),
            ),
        ]),
        if (_indexError(i) == tr('เลือกคอลัมน์อย่างน้อย 1'))
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(_indexError(i)!, style: TextStyle(fontSize: 11.5, color: C.danger))),
      ]),
    );
  }

  // ---------- แท็บ: CHECK ----------

  /// ชื่อคอลัมน์ที่นิพจน์ CHECK อ้างถึงแต่ไม่มีในฟอร์ม
  List<String> _unknownColumnsIn(String expr) {
    final names = {for (final d in _drafts) d.name.text.trim().toLowerCase()};
    return [for (final w in checkIdentifiers(expr)) if (!names.contains(w.toLowerCase())) w];
  }

  void _addCheck({String expr = ''}) => setState(() {
        final tn = _name.text.trim().isEmpty ? 'table' : _name.text.trim();
        _checks.add(CheckDraft(name: 'chk_${tn}_${_checks.length + 1}', expr: expr));
      });

  void _checkTemplate(bool range) {
    final cols = _drafts.where((d) => d.name.text.trim().isNotEmpty).toList();
    String n(int i, String fallback) => i < cols.length ? cols[i].name.text.trim() : fallback;
    if (range) {
      final dates = cols.where((d) => d.type == DataType.date || d.type == DataType.datetime || d.type == DataType.timestamp).toList();
      final a = dates.length >= 2 ? dates[0].name.text.trim() : n(0, 'start_at');
      final b = dates.length >= 2 ? dates[1].name.text.trim() : n(1, 'end_at');
      _addCheck(expr: '$b > $a');
    } else {
      final nums = cols.where((d) => (d.type == DataType.decimal || d.type == DataType.integer || d.type == DataType.bigint || d.type == DataType.float || d.type == DataType.smallint) && d.index != ColumnIndex.primary).toList();
      _addCheck(expr: '${nums.isNotEmpty ? nums.first.name.text.trim() : n(0, 'amount')} >= 0');
    }
  }

  Widget _checksTab() => Container(
        decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              tr('เงื่อนไขที่ทุกแถวต้องเป็นจริง เช่น วันออกต้องหลังวันเข้า ราคาต้องไม่ติดลบ — เขียนนิพจน์ SQL เอง (ชื่อคอลัมน์ไม่ต้องใส่เครื่องหมายอ้าง) รายการที่ไม่มีนิพจน์จะไม่ถูกใส่ใน SQL'),
              style: TextStyle(fontSize: 12.5, color: C.muted),
            ),
            const SizedBox(height: 10),
            if (_checks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(tr('ยังไม่มีเงื่อนไข CHECK'), key: const ValueKey('ct-check-empty'), style: TextStyle(color: C.muted)),
              ),
            for (var i = 0; i < _checks.length; i++) _checkCard(i),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(
                key: const ValueKey('ct-check-add'),
                onPressed: _addCheck,
                icon: const Icon(Icons.add, size: 16),
                label: Text(tr('เพิ่มเงื่อนไข')),
              ),
              Text(tr('เริ่มจากแม่แบบ:'), style: TextStyle(fontSize: 12, color: C.muted)),
              OutlinedButton(key: const ValueKey('ct-check-tpl-range'), onPressed: () => _checkTemplate(true), child: Text(tr('ช่วงค่า a > b'))),
              OutlinedButton(key: const ValueKey('ct-check-tpl-pos'), onPressed: () => _checkTemplate(false), child: Text(tr('ค่าไม่ติดลบ'))),
            ]),
            if (widget.dialect == Dialect.mysql)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: C.warnBg, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  tr('MySQL ก่อน 8.0.16 และ MariaDB ก่อน 10.2.1 รับ CHECK แต่ไม่บังคับใช้ — ถ้าฐานข้อมูลของคุณเป็นรุ่นเก่า เงื่อนไขนี้จะไม่ทำงาน'),
                  style: TextStyle(fontSize: 12, color: C.warnText),
                ),
              ),
          ]),
        ),
      );

  Widget _checkCard(int i) {
    final k = _checks[i];
    final unknown = _unknownColumnsIn(k.expr.text);
    final blank = k.expr.text.trim().isEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 230,
            child: TextField(
              key: ValueKey('ct-check-name-$i'),
              controller: k.name,
              onChanged: (_) => setState(() {}),
              style: monoStyle.copyWith(fontSize: 12.5),
              decoration: _dec(error: _checkNameError(i)).copyWith(labelText: tr('ชื่อเงื่อนไข')),
            ),
          ),
          const SizedBox(width: 8),
          Padding(padding: const EdgeInsets.only(top: 10), child: Text('CHECK (', style: monoStyle.copyWith(fontSize: 12.5, color: C.muted))),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              key: ValueKey('ct-check-expr-$i'),
              controller: k.expr,
              onChanged: (_) => setState(() {}),
              style: monoStyle.copyWith(fontSize: 12.5),
              decoration: _dec(hint: 'check_out > check_in'),
            ),
          ),
          const SizedBox(width: 6),
          Padding(padding: const EdgeInsets.only(top: 10), child: Text(')', style: monoStyle.copyWith(fontSize: 12.5, color: C.muted))),
          IconButton(
            key: ValueKey('ct-check-del-$i'),
            tooltip: tr('ลบเงื่อนไขนี้'),
            iconSize: 18,
            onPressed: () => setState(() => _checks.removeAt(i).dispose()),
            icon: Icon(Icons.delete_outline, color: C.danger),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: blank
              ? Text(tr('ยังไม่มีนิพจน์ — จะไม่ถูกใส่ใน SQL'), key: ValueKey('ct-check-note-$i'), style: TextStyle(fontSize: 11.5, color: C.muted))
              : unknown.isNotEmpty
                  ? Text(tr('ไม่พบคอลัมน์ {0} ในตารางนี้', [unknown.join(', ')]), key: ValueKey('ct-check-note-$i'), style: TextStyle(fontSize: 11.5, color: C.warnText))
                  : Text(tr('ใช้คอลัมน์ {0} · ผ่านการตรวจ', [checkIdentifiers(k.expr.text).join(', ')]), key: ValueKey('ct-check-note-$i'), style: TextStyle(fontSize: 11.5, color: C.muted)),
        ),
      ]),
    );
  }

  // ---------- แท็บ: ข้อมูลตั้งต้น ----------

  Widget _seedTab() => SeedGridEditor(
        key: ValueKey('ct-seed-${_seedSignature()}'),
        project: _project,
        table: _preview(),
        initialRows: _seed,
        showHint: false,
        onChanged: (rows, problems) {
          _seed = rows;
          if (_seedProblems != problems.length) {
            // เปลี่ยนจำนวนปัญหา = วาดแท็บใหม่ (ป้ายสีแดง) หลังเฟรมนี้ ไม่ให้ setState ซ้อนกลางการสร้าง
            _seedProblems = problems.length;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          } else {
            setState(() {});
          }
        },
      );

  // ---------- แถบตัวอย่าง SQL ----------

  Widget _sqlBar() {
    const bg = Color(0xFF0F172A), fg = Color(0xFFE2E8F0), mut = Color(0xFF94A3B8), hi = Color(0xFF5EEAD4);
    final lines = _sqlText().split('\n');
    return Container(
      key: const ValueKey('ct-sql-bar'),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          key: const ValueKey('ct-sql-toggle'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _sqlOpenChoice = !_sqlOpen),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              Icon(_sqlOpen ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 18, color: mut),
              const SizedBox(width: 4),
              Text(tr('ตัวอย่าง SQL'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${widget.dialect.label} · ${widget.dialect == Dialect.mysql ? tr('ค่าที่อนุญาต = ENUM(...)') : tr('ค่าที่อนุญาต = CHECK (… IN (…))')} · ${tr('บรรทัดสีเขียวคือ ENUM/CHECK')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: mut),
                ),
              ),
            ]),
          ),
        ),
        if (_sqlOpen)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 130),
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final (li, l) in lines.indexed)
                    Text(
                      l,
                      key: l.contains('ENUM(') || l.contains('CHECK') ? ValueKey('ct-sql-hi-$li') : null,
                      style: monoStyle.copyWith(fontSize: 12, height: 1.6, color: l.contains('ENUM(') || l.contains('CHECK') ? hi : fg),
                    ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
