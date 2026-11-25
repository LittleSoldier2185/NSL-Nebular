import '../models/wireframe_model.dart';
import 'wireframe_render.dart';

/// ตำแหน่งของข้อความหนึ่งก้อนที่ตัววาดวางจริง (พิกัดโลกของ Wireframe ก่อนหมุน)
typedef WfSlot = ({int index, double x, double y, double w, double h, int align, double size, bool bold});

/// ชนิดที่ข้อความเป็น "รายการหลายค่า" (บรรทัดละรายการ) — แก้ในการ์ดรายการ ; ตาราง = หัวคอลัมน์
/// (ย่อหน้า/กล่องข้อความ = ข้อความอิสระ ; tree = มีการเยื้อง จึงยังใช้ช่องพิมพ์หลายบรรทัด)
bool wfItemsKind(WfKind k) => const {
      WfKind.tabs,
      WfKind.list,
      WfKind.sidebar,
      WfKind.breadcrumb,
      WfKind.table,
      WfKind.stepper,
      WfKind.accordion,
      WfKind.stat,
      WfKind.bottomNav,
      WfKind.bottomSheet,
      WfKind.drawer,
      WfKind.segmented,
      WfKind.optionGroup,
      WfKind.emptyState,
      WfKind.toast,
      WfKind.kanban,
      WfKind.timeline,
    }.contains(k);

/// ค่าทั้งหมดในการ์ดรายการ: ตาราง = หัวคอลัมน์ ; ชิ้นอื่น = บรรทัดที่ไม่ว่างของข้อความ
List<String> wfSlotValues(WfComponent c) => c.kind == WfKind.table ? List.of(c.columns) : c.items;

final Map<WfKind, bool> _hasText = {};

/// ชิ้นชนิดนี้แสดงข้อความของตัวเองในภาพหรือไม่ — ตรวจจากตัววาดจริง (ใส่ข้อความตัวอย่างแล้วดูว่าถูกวาดไหม)
/// ชนิดที่ไม่แสดงข้อความ (รูป ไอคอน เส้นคั่น แผนที่ ฯลฯ) จึงพิมพ์ข้อความใส่ไม่ได้
bool wfKindHasText(WfKind k) => _hasText.putIfAbsent(k, () {
      const probe = 'Zq9';
      final c = WfComponent(id: 'probe', kind: k, text: '$probe\n$probe\n$probe', columns: [probe, probe, probe], x: 0, y: 0);
      var seen = false;
      void walk(Iterable<WfPrim> ps) {
        for (final p in ps) {
          if (p is WfTextPrim && p.text.contains(probe)) seen = true;
          if (p is WfGroupPrim) walk(p.children);
        }
      }

      walk(wfComponentPrims(WireframeDiagram(components: [c]), c));
      return seen;
    });
