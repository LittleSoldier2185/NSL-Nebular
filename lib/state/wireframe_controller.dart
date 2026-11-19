import '../core/clipboard/wireframe_clipboard.dart';
import '../core/l10n/l10n.dart';
import '../core/layout/box_ops.dart';
import '../core/layout/diagram_geometry.dart' show snapToGrid;
import '../core/models/wireframe_model.dart';
import '../core/models/workspace.dart';
import '../core/validate/issue.dart';
import '../core/validate/wireframe_validator.dart';
import 'box_diagram_controller.dart';
import 'workspace_controller.dart';

/// เครื่องมือของแท็บ Wireframe: เลือก / วางชิ้นส่วน ([WireframeController.toolKind])
enum WfTool { select, place }

/// controller ของเอกสาร Wireframe หนึ่งชิ้น (หน้าจอหนึ่งหน้า): เนื้อหา + ประวัติ undo/redo + สถานะหน้าจอ
/// การเปลี่ยนรูปแบบการแสดงผล/สีเน้น/ขนาดหน้าจอเข้าประวัติ undo เหมือนการแก้อื่น
class WireframeController extends BoxDiagramController<WireframeDiagram, WfComponent> {
  WireframeController.forDoc(super.doc, super.workspace) : assert(doc.content is WireframeDiagram);

  /// ตัวแทนตอนไม่มีเอกสาร Wireframe ที่ใช้งานอยู่: หน้าจอว่างที่ไม่อยู่ในโปรเจกต์ แก้ไขไม่ได้
  WireframeController.detached(WorkspaceController workspace)
      : super(ProjectDocument.wireframe(id: '', name: '', content: WireframeDiagram()), workspace);

  WireframeDiagram get diagram => content;

  @override
  Object? encodeContent(WireframeDiagram c) => c.toJson();

  @override
  WireframeDiagram decodeContent(Object? j) => WireframeDiagram.fromJson(j);

  @override
  List<WfComponent> boxesOf(WireframeDiagram c) => c.components;

  @override
  double get minSide => kWfMinSide;

  @override
  double get maxSide => kWfMaxSide;

  // ---------- เครื่องมือ ----------

  WfTool _tool = WfTool.select;
  WfKind _toolKind = WfKind.button;
  WfTool get tool => _tool;
  WfKind get toolKind => _toolKind;

  void setTool(WfTool t, {WfKind? kind}) {
    if (_tool == t && (kind == null || kind == _toolKind)) return;
    _tool = t;
    if (kind != null) _toolKind = kind;
    notifyListeners();
  }

  /// เครื่องมือวางชิ้นส่วน [k]
  void setPlaceTool(WfKind k) => setTool(WfTool.place, kind: k);

  /// Esc: ยกเลิกการพิมพ์ -> ยกเลิกเครื่องมือ -> ล้างการเลือก
  void escape() {
    if (escapeEditing()) return;
    if (_tool != WfTool.select) {
      _tool = WfTool.select;
      notifyListeners();
      return;
    }
    clearSelection();
  }

  // ---------- ลูกในภาชนะ ----------

  @override
  Set<String> moveSet(Set<String> ids) => ids.isEmpty ? ids : {...ids, ...wfDescendants(diagram, ids, parents)};

  // ---------- ค่าที่คำนวณแล้วเก็บไว้ (คำนวณใหม่เมื่อเนื้อหาเปลี่ยน) ----------

  Object? _cacheKey;
  Map<String, String> _parents = const {};
  Set<String> _hidden = const {};

  void _refresh() {
    final d = diagram;
    final key = (revision, identityHashCode(d), d.components.length);
    if (key == _cacheKey) return;
    _cacheKey = key;
    _parents = wfParentMap(d);
    _hidden = wfHiddenIds(d, _parents);
  }

  /// พ่อของแต่ละชิ้น (ภาชนะที่ครอบ) — ดู [wfParentMap]
  Map<String, String> get parents {
    _refresh();
    return _parents;
  }

  /// ชิ้นที่มองไม่เห็น (ซ่อนเอง/อยู่ในภาชนะที่ซ่อน)
  Set<String> get hiddenIds {
    _refresh();
    return _hidden;
  }

  List<Issue>? _issues;
  Object? _issuesKey;

  /// ผลตรวจหน้าจอนี้ — คำนวณใหม่เมื่อเนื้อหา/โปรเจกต์เปลี่ยน ; ระหว่างลากใช้ผลเดิม (ตรวจใหม่ตอนปล่อยเมาส์)
  List<Issue> get issues {
    final key = (revision, workspace.changeTick, identityHashCode(diagram));
    final cached = _issues;
    if (cached != null && (key == _issuesKey || gestureActive)) return cached;
    _issuesKey = key;
    return _issues = validateWireframe(diagram, workspace: workspace.workspace);
  }

  // ---------- ซ่อน / ล็อก / กลุ่ม / หมุน ----------

  @override
  bool isLocked(WfComponent b) => b.locked;

  @override
  bool selectableOnCanvas(WfComponent b) => !b.locked && !hiddenIds.contains(b.id);

  /// การคลิก/ลากกรอบบนแคนวาสเลือกเฉพาะชิ้นที่โดน ไม่ลามไปทั้งกลุ่ม — จะเลือกทั้งกลุ่มต้องกดที่แถวกลุ่มในแผงเลเยอร์ (หรือติ๊กช่องของกลุ่ม)
  @override
  Set<String> withGroup(String id) => {id};

  /// สมาชิกทั้งกลุ่ม [group] (ใช้ตอนกดแถวกลุ่ม)
  Set<String> groupIds(String group) => {for (final c in diagram.components) if (c.group == group) c.id};

  @override
  double rotationOf(WfComponent b) => b.rotation;

  @override
  void setRotationOf(WfComponent b, double degrees) => b.rotation = wfNormAngle(degrees);

  @override
  bool get canRotate => true;

  /// ซ่อน/แสดงชิ้น [ids] — undo ได้
  void setHidden(Iterable<String> ids, bool hidden) => updateComponents(ids, (c) => c.hidden = hidden);

  /// ล็อก/ปลดล็อกชิ้น [ids] — undo ได้
  void setLocked(Iterable<String> ids, bool locked) => updateComponents(ids, (c) => c.locked = locked);

  /// ลบรายการกลุ่มที่ไม่มีสมาชิกแล้ว (เฉพาะใน [only] ถ้าระบุ) — ใช้ตอนเลิกกลุ่ม/ลบชิ้น ไม่ใช้กับกลุ่มเปล่าที่ผู้ใช้สร้างไว้
  static void _dropEmpty(WireframeDiagram d, Set<String> only) {
    final used = {for (final c in d.components) ?c.group};
    d.groups.removeWhere((g) => only.contains(g.id) && !used.contains(g.id));
  }

  /// จัดชิ้นที่เลือก (ตั้งแต่ 2 ชิ้น) เป็นกลุ่มเดียว — สมาชิกถูกย้ายมาติดกันในลำดับการซ้อน ณ ตำแหน่งของสมาชิกที่อยู่บนสุด
  /// (ลำดับภายในคงเดิม ; กลุ่มเดิมของสมาชิกที่ว่างลงถูกลบ) — undo ขั้นเดียว ; คืนรหัสกลุ่มใหม่ (null = ไม่ได้ทำ)
  String? groupSelection() {
    final ids = selectedIds;
    if (!active || ids.length < 2) return null;
    final gid = workspace.newId('g');
    edit((d) {
      d.syncGroups();
      final list = d.components;
      final members = [for (final c in list) if (ids.contains(c.id)) c];
      final old = {for (final m in members) ?m.group};
      final topIndex = list.lastIndexWhere((c) => ids.contains(c.id));
      final below = list.sublist(0, topIndex + 1).where((c) => !ids.contains(c.id)).toList();
      final above = list.sublist(topIndex + 1);
      for (final m in members) {
        m.group = gid;
      }
      list
        ..clear()
        ..addAll(below)
        ..addAll(members)
        ..addAll(above);
      d.groups.add(WfGroup(id: gid, name: d.nextGroupName(tr('กลุ่ม'))));
      _dropEmpty(d, old);
    });
    notifyListeners();
    return gid;
  }

  /// เลิกจัดกลุ่มของชิ้นที่เลือก (กลุ่มที่ว่างลงถูกลบ) — คืน true ถ้ามีกลุ่มให้เลิก
  bool ungroupSelection() {
    final ids = selectedIds;
    if (!active || !selectedBoxes.any((c) => c.group != null)) return false;
    final old = {for (final c in selectedBoxes) ?c.group};
    edit((d) {
      for (final c in d.components) {
        if (ids.contains(c.id)) c.group = null;
      }
      _dropEmpty(d, old);
    });
    notifyListeners();
    return true;
  }

  /// ที่เลือกอยู่มีสมาชิกของกลุ่ม (เปิด/ปิดปุ่ม "เลิกกลุ่ม")
  bool get selectionHasGroup => selectedBoxes.any((c) => c.group != null);

  /// สร้างกลุ่มเปล่า (ยังไม่มีสมาชิก) — วางเหนือชิ้นบนสุดที่เลือกอยู่ ไม่ได้เลือก = บนสุด ; คืนรหัสกลุ่ม (null = แก้ไม่ได้)
  String? addEmptyGroup() {
    if (!active) return null;
    final gid = workspace.newId('g');
    final sel = selectedIds;
    final list = diagram.components;
    final top = list.lastIndexWhere((c) => sel.contains(c.id));
    edit((d) {
      d.syncGroups();
      d.groups.add(WfGroup(id: gid, name: d.nextGroupName(tr('กลุ่ม')), at: top < 0 ? d.components.length : top + 1));
    });
    return gid;
  }

  /// ลบกลุ่ม [group] (สมาชิกยังอยู่ แค่ไม่อยู่ในกลุ่มแล้ว) — undo ได้
  bool removeGroup(String group) {
    if (!active || diagram.groupById(group) == null && wfGroupMembers(diagram, group).isEmpty) return false;
    edit((d) {
      for (final c in d.components) {
        if (c.group == group) c.group = null;
      }
      d.groups.removeWhere((g) => g.id == group);
    });
    return true;
  }

  /// เปลี่ยนชื่อกลุ่ม (ว่าง = ใช้คำว่า "กลุ่ม") — undo ได้
  void renameGroup(String group, String name) => editIfChanged((d) {
        d.syncGroups();
        d.groupById(group)?.name = name.trim();
      });

  /// ชื่อที่แสดงของกลุ่ม [group]
  String groupLabel(String group) {
    final n = diagram.groupById(group)?.name ?? '';
    return n.isEmpty ? tr('กลุ่ม') : n;
  }

  // ---------- แผงเลเยอร์: แถว + ลากเปลี่ยนลำดับ ----------

  /// แถวในแผงเลเยอร์ (บนสุดก่อน): หัวกลุ่ม แล้วตามด้วยสมาชิก (ถ้ากลุ่มไม่ได้พับใน [collapsed]) ; ชิ้นที่ไม่อยู่กลุ่มเป็นแถวเดี่ยว ;
  /// กลุ่มเปล่าอยู่ตามตำแหน่ง [WfGroup.at]
  List<WfLayerRow> layerRows(Set<String> collapsed) {
    final d = diagram;
    final n = d.components.length;
    final used = {for (final c in d.components) ?c.group};
    final empties = [for (final g in d.groups) if (!used.contains(g.id)) g];
    final rows = <WfLayerRow>[];
    final seen = <String>{};
    void emitEmpty(int at) {
      for (final g in empties) {
        if (g.at.clamp(0, n) == at) rows.add(WfLayerRow(group: g.id, header: true, open: !collapsed.contains(g.id)));
      }
    }

    for (var i = n - 1; i >= 0; i--) {
      emitEmpty(i + 1);
      final c = d.components[i];
      final g = c.group;
      if (g == null) {
        rows.add(WfLayerRow(id: c.id));
        continue;
      }
      if (!seen.add(g)) continue;
      final open = !collapsed.contains(g);
      rows.add(WfLayerRow(group: g, header: true, open: open));
      if (open) {
        for (final m in wfGroupMembers(d, g).reversed) {
          rows.add(WfLayerRow(id: m.id, group: g));
        }
      }
    }
    emitEmpty(0);
    return rows;
  }

  /// ลากแถว [oldIndex] ไปวางที่ [newIndex] (ดัชนีในรายการหลังเอาแถวที่ลากออกแล้ว แบบ onReorderItem) — undo ขั้นเดียว
  ///
  /// - ลากหัวกลุ่ม = ย้ายทั้งกลุ่ม (ไม่แทรกกลางกลุ่มอื่น) ; กลุ่มเปล่าก็ลากได้
  /// - ลากชิ้นไปวางใต้หัวกลุ่มที่กางอยู่ (รวมกลุ่มเปล่า) หรือเหนือสมาชิกของกลุ่ม = เข้ากลุ่มนั้น ; วางนอกกลุ่ม = ออกจากกลุ่ม
  /// - กลุ่มที่สมาชิกถูกลากออกหมดยังอยู่เป็นกลุ่มเปล่า (ลบได้จากปุ่มบนหัวกลุ่ม)
  /// คืน true ถ้าลำดับ/กลุ่มเปลี่ยน
  /// [explicit] = ผู้ใช้ระบุกลุ่มปลายทางเอง ([group] ; null = นอกกลุ่ม) — ใช้เมื่อวางด้วยการลากบนแถว ไม่เดาจากแถวข้างเคียง
  bool moveLayerRow(Set<String> collapsed, int oldIndex, int newIndex, {bool explicit = false, String? group}) {
    final rows = layerRows(collapsed);
    if (oldIndex < 0 || oldIndex >= rows.length || (oldIndex == newIndex && !explicit)) return false;
    final moving = rows[oldIndex];
    final withoutMoved = [...rows]..removeAt(oldIndex);
    final below = newIndex < withoutMoved.length ? withoutMoved[newIndex] : null;

    // แถวที่ย้ายไปด้วยกัน
    final block = <WfLayerRow>[moving];
    if (moving.header && moving.open) {
      for (var i = oldIndex + 1; i < rows.length && !rows[i].header && rows[i].group == moving.group; i++) {
        block.add(rows[i]);
      }
    }
    if (below != null && block.contains(below)) return false;
    final rest = [for (final r in rows) if (!block.contains(r)) r];
    var pos = below == null ? rest.length : rest.indexOf(below);

    String? newGroup = moving.group;
    if (moving.header) {
      // ไม่แทรกกลางกลุ่มอื่น: เลื่อนลงไปจนพ้นสมาชิกของกลุ่มนั้น
      while (pos < rest.length && !rest[pos].header && rest[pos].group != null && pos > 0 && (rest[pos - 1].group == rest[pos].group)) {
        pos++;
      }
    } else if (explicit) {
      newGroup = group;
    } else {
      final above = pos > 0 ? rest[pos - 1] : null;
      final under = pos < rest.length ? rest[pos] : null;
      if (above != null && above.header && above.open) {
        newGroup = above.group;
      } else if (under != null && !under.header && under.group != null) {
        newGroup = under.group;
      } else if (above != null && !above.header && above.group != null && above.group == moving.group) {
        newGroup = moving.group; // สมาชิกตัวท้ายที่วางต่อจากสมาชิกในกลุ่มเดิม = ยังอยู่กลุ่มเดิม
      } else {
        newGroup = null;
      }
    }
    rest.insertAll(pos, block);

    // ลำดับชิ้น (บนสุดก่อน) + กลุ่มใหม่ + ตำแหน่งของหัวกลุ่ม (ใช้เมื่อกลุ่มว่าง)
    final groupOf = <String, String?>{};
    final topFirst = <String>[];
    final headerSeen = <String, int>{}; // กลุ่ม -> จำนวนชิ้นที่อยู่เหนือหัวกลุ่ม
    for (final r in rest) {
      if (r.header) {
        headerSeen[r.group!] = topFirst.length;
        if (!r.open) {
          for (final m in wfGroupMembers(diagram, r.group!).reversed) {
            topFirst.add(m.id);
            groupOf[m.id] = r.group;
          }
        }
        continue;
      }
      topFirst.add(r.id!);
      groupOf[r.id!] = r == moving ? newGroup : r.group;
    }
    final total = topFirst.length;
    return editIfChanged((d) {
      final byId = {for (final c in d.components) c.id: c};
      if (total != byId.length) return;
      d.components
        ..clear()
        ..addAll([for (final id in topFirst.reversed) byId[id]!]);
      for (final c in d.components) {
        c.group = groupOf[c.id];
      }
      d.syncGroups();
      final used = {for (final c in d.components) ?c.group};
      for (final g in d.groups) {
        final above = headerSeen[g.id];
        if (above != null && !used.contains(g.id)) g.at = total - above; // ตำแหน่งเก็บเฉพาะกลุ่มเปล่า (มีสมาชิกแล้วตามสมาชิก)
      }
    });
  }

  // ---------- ข้อความ ----------

  /// ข้อความที่แก้บนแคนวาส: ตาราง = หัวคอลัมน์บรรทัดละคอลัมน์ ; อื่น ๆ = ข้อความของชิ้น
  String inlineText(WfComponent c) => c.kind == WfKind.table ? c.columns.join('\n') : c.text;

  @override
  void applyEditedText(({String id, bool isEdge}) t, String text) {
    final c = diagram.componentById(t.id);
    if (c == null) return;
    if (c.kind == WfKind.table) {
      setColumns(t.id, [for (final l in text.split('\n')) if (l.trim().isNotEmpty) l.trim()]);
    } else {
      setText(t.id, text);
    }
  }

  /// หัวคอลัมน์ของตาราง (undo ขั้นเดียว)
  void setColumns(String id, List<String> columns) => updateComponents([id], (c) {
        c.columns
          ..clear()
          ..addAll(columns.take(30));
      });

  void setText(String id, String text) {
    final c = diagram.componentById(id);
    if (c == null || c.text == text) return;
    edit((d) => d.componentById(id)!.text = text);
  }

  /// ข้อความเริ่มต้นของชิ้นใหม่
  static String defaultText(WfKind k) => switch (k) {
        WfKind.heading => tr('หัวข้อหน้า'),
        WfKind.label => tr('ป้ายข้อความ'),
        WfKind.paragraph => tr('ข้อความย่อหน้าตัวอย่าง อธิบายเนื้อหาของส่วนนี้'),
        WfKind.button => tr('ปุ่ม'),
        WfKind.input => tr('กรอกข้อความ'),
        WfKind.textarea => tr('กรอกรายละเอียด'),
        WfKind.checkbox => tr('จดจำฉันไว้'),
        WfKind.radio => tr('ตัวเลือก'),
        WfKind.toggle => tr('เปิดใช้งาน'),
        WfKind.select => tr('เลือก…'),
        WfKind.search => tr('ค้นหา…'),
        WfKind.card => tr('ชื่อการ์ด'),
        WfKind.tabs => tr('แท็บ 1\nแท็บ 2\nแท็บ 3'),
        WfKind.navbar => tr('ชื่อแอป'),
        WfKind.sidebar => tr('เมนู 1\nเมนู 2\nเมนู 3'),
        WfKind.modal => tr('หัวข้อหน้าต่าง'),
        WfKind.badge => tr('ใหม่'),
        WfKind.breadcrumb => tr('หน้าแรก\nหมวดหมู่\nหน้านี้'),
        WfKind.list => tr('รายการที่ 1\nรายการที่ 2\nรายการที่ 3'),
        WfKind.link => tr('อ่านเพิ่มเติม'),
        WfKind.chip => tr('แท็ก'),
        WfKind.progress => '60%',
        WfKind.alert => tr('ข้อความแจ้งเตือนสำคัญ'),
        WfKind.datepicker => tr('เลือกวันที่'),
        WfKind.upload => tr('ลากไฟล์มาวาง หรือคลิกเพื่อเลือก'),
        WfKind.stepper => tr('ข้อมูล\nที่อยู่\nยืนยัน'),
        WfKind.accordion => tr('หัวข้อที่ 1\nหัวข้อที่ 2\nหัวข้อที่ 3'),
        WfKind.footer => tr('ลิขสิทธิ์ © บริษัทของคุณ'),
        WfKind.tooltip => tr('ข้อความช่วยเหลือ'),
        WfKind.calendar => tr('พฤศจิกายน 2569'),
        WfKind.stat => tr('ยอดขายวันนี้\n1,250'),
        WfKind.tree => tr('โฟลเดอร์\n  ไฟล์ 1\n  ไฟล์ 2\nโฟลเดอร์ 2'),
        _ => '',
      };

  // ---------- ชิ้นส่วน ----------

  /// วางชิ้นส่วนใหม่ให้ศูนย์กลางอยู่ที่ ([cx],[cy]) แล้วเลือกมัน
  WfComponent? addComponent(WfKind kind, double cx, double cy, {bool snap = false, String? text}) {
    if (!active) return null;
    var (w, h) = wfDefaultSize(kind);
    // แถบนำทางบน: กว้างเต็มหน้าจอ
    if (kind == WfKind.navbar) w = diagram.width;
    var x = cx - w / 2, y = cy - h / 2;
    if (kind == WfKind.navbar) x = 0;
    if (snap) {
      x = snapToGrid(x);
      y = snapToGrid(y);
    }
    late WfComponent c;
    edit((d) {
      c = WfComponent(
        id: workspace.newId('w'),
        kind: kind,
        text: text ?? defaultText(kind),
        x: x,
        y: y,
        w: w,
        h: h,
        columns: kind == WfKind.table ? [tr('ชื่อ'), tr('สถานะ'), tr('วันที่')] : null,
        align: const {WfKind.button, WfKind.badge, WfKind.chip, WfKind.tooltip, WfKind.footer}.contains(kind) ? WfAlign.center : WfAlign.left,
      );
      d.components.add(c);
    });
    clearOtherSelection();
    dropBoxSelection();
    setSelection([c.id]);
    _tool = WfTool.select;
    notifyListeners();
    return c;
  }

  /// แก้ชิ้นส่วนหลายชิ้นพร้อมกัน — undo ขั้นเดียว ; ไม่มีอะไรเปลี่ยน = ไม่เข้าประวัติ
  void updateComponents(Iterable<String> ids, void Function(WfComponent c) change) {
    final list = {for (final id in ids) if (diagram.componentById(id) != null) id};
    if (list.isEmpty) return;
    editIfChanged((d) {
      for (final c in d.components) {
        if (list.contains(c.id)) change(c);
      }
    });
  }

  @override
  void removeBoxes(WireframeDiagram c, Set<String> ids) {
    final old = {for (final x in c.components) if (ids.contains(x.id)) ?x.group};
    c.components.removeWhere((x) => ids.contains(x.id));
    _dropEmpty(c, old); // ลบสมาชิกหมดทั้งกลุ่ม = ลบกลุ่มด้วย
  }

  /// ลบชิ้นที่เลือก (ลูกในภาชนะไม่ถูกลบ — ยังอยู่ที่เดิม)
  int deleteSelection() => deleteSelectedBoxes();

  // ---------- หน้าจอ / รูปแบบ ----------

  /// เปลี่ยนรูปแบบการแสดงผล (มีผลเฉพาะการวาด) — undo ได้
  void setStyle(WfStyle s) => editIfChanged((d) => d.style = s);

  /// สีเน้นของเอกสาร — undo ได้
  void setAccent(int argb) => editIfChanged((d) => d.accent = argb | 0xFF000000);

  /// เลือกขนาดหน้าจอสำเร็จรูป (custom = คงขนาดเดิมแต่ปลดล็อกให้กำหนดเอง)
  void setDevice(WfDevice dev) => editIfChanged((d) {
        d.device = dev;
        if (dev != WfDevice.custom) {
          d.width = dev.width;
          d.height = dev.height;
        }
      });

  /// กำหนดขนาดหน้าจอเอง (เปลี่ยนเป็นแบบกำหนดเอง) — ค่าถูกจำกัดในช่วงที่รองรับ
  void setFrameSize(double w, double h) => editIfChanged((d) {
        final nw = w.clamp(WireframeDiagram.minFrame, WireframeDiagram.maxFrame).toDouble();
        final nh = h.clamp(WireframeDiagram.minFrame, WireframeDiagram.maxFrame).toDouble();
        if (nw == d.width && nh == d.height) return;
        d.width = nw;
        d.height = nh;
        d.device = WfDevice.values.firstWhere((x) => x != WfDevice.custom && x.width == nw && x.height == nh,
            orElse: () => WfDevice.custom);
      });

  // ---------- ผูกข้อมูล ER ----------

  /// ผูก/เลิกผูก ([ref] = null) ชิ้น [id] กับตาราง/คอลัมน์ใน ER
  void setRef(String id, WfDataRef? ref) => updateComponents([id], (c) => c.ref = ref);

  /// เปิดเอกสาร ER ที่ชิ้น [id] ผูกไว้แล้วเลือกตาราง (และคอลัมน์) — คืน false ถ้าไม่ได้ผูก/หาไม่พบ
  bool gotoBoundTable(String id) {
    final r = diagram.componentById(id)?.ref;
    if (r == null) return false;
    final er = workspace.erController(r.docId);
    if (er == null || er.project.tableById(r.tableId) == null) return false;
    workspace.openDocument(er.docId);
    er.selectTable(r.tableId, columnId: r.columnId);
    return true;
  }

  // ---------- ทำสำเนา / คลิปบอร์ด ----------

  /// ทำสำเนาชิ้นที่เลือก (พร้อมลูกในภาชนะ) เลื่อนไป 20 px แล้วเลือกสำเนา
  int duplicateSelection() {
    final text = copySelectionText();
    return text == null ? 0 : pasteText(text, offset: 20);
  }

  /// ข้อความสำหรับคลิปบอร์ด (null = ไม่มีอะไรเลือก) — ลูกในภาชนะติดไปด้วย
  String? copySelectionText() {
    final ids = moveSet({for (final c in selectedBoxes) c.id});
    return ids.isEmpty ? null : encodeWireframeClipboard(diagram, ids);
  }

  /// วางจากคลิปบอร์ดของโปรแกรม (ข้ามแท็บ/โปรเจกต์ได้) ; คืนจำนวนชิ้นที่วาง (0 = ไม่ใช่ข้อมูล Wireframe) ; id ใหม่ทั้งหมด
  int pasteText(String? text, {double offset = 20}) {
    final src = decodeWireframeClipboard(text);
    if (!active || src == null) return 0;
    final ids = <String>[];
    final groups = <String, String>{}; // กลุ่มเดิม -> กลุ่มใหม่ (สำเนาเป็นกลุ่มของตัวเอง ไม่ปนกับต้นฉบับ)
    edit((d) {
      for (final c in src) {
        final id = workspace.newId('w');
        ids.add(id);
        final g = c.group == null ? null : groups.putIfAbsent(c.group!, () => workspace.newId('g'));
        d.components.add(WfComponent.tryFromJson({...c.toJson(), 'id': id, 'x': c.x + offset, 'y': c.y + offset, 'group': g, 'locked': false})!);
      }
      for (final g in groups.values) {
        d.groups.add(WfGroup(id: g, name: d.nextGroupName(tr('กลุ่ม'))));
      }
    });
    // เลือกเฉพาะชิ้นบนสุด (ไม่ใช่ลูก) เพื่อให้ลากย้ายทั้งก้อนได้ทันที
    final parents = wfParentMap(diagram);
    final top = [for (final id in ids) if (!ids.contains(parents[id])) id];
    setSelection(top);
    return ids.length;
  }

  // ---------- มุมมอง ----------

  @override
  ({double left, double top, double right, double bottom})? contentBounds({Set<String>? only}) {
    if (only != null) return boxesBounds(diagram.components.where((c) => only.contains(c.id)), pad: 40);
    final b = boxesBounds([...diagram.components, WfComponent(id: '', kind: WfKind.container, w: diagram.width, h: diagram.height)],
        pad: 40);
    return b;
  }
}

/// แถวหนึ่งในแผงเลเยอร์: หัวกลุ่ม ([header], [group], [open]) หรือชิ้นส่วน ([id] ; [group] = กลุ่มที่สังกัด)
class WfLayerRow {
  WfLayerRow({this.id, this.group, this.header = false, this.open = true});
  final String? id;
  final String? group;
  final bool header;
  final bool open;

  @override
  String toString() => header ? 'G($group${open ? '' : ',closed'})' : (group == null ? id! : '$id@$group');
}
