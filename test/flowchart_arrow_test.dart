import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/export/flowchart_svg.dart';
import 'package:nsl_nebular/core/export/screenflow_svg.dart';
import 'package:nsl_nebular/core/layout/flowchart_geometry.dart';
import 'package:nsl_nebular/core/layout/ortho_route.dart';
import 'package:nsl_nebular/core/layout/screenflow_geometry.dart';
import 'package:nsl_nebular/core/models/flowchart_model.dart';
import 'package:nsl_nebular/core/models/screenflow_model.dart';

/// เส้นเชื่อมต้องไม่ทะลุหัวลูกศร
void main() {
  FcEdge edge({FcArrow start = FcArrow.none, FcArrow end = FcArrow.arrow, double width = 2}) =>
      FcEdge(id: 'e', fromId: 'a', toId: 'b', startArrow: start, endArrow: end, width: width);
  const straight = <RoutePoint>[(0.0, 0.0), (0.0, 100.0)];

  test('ตัวเส้นจบที่ฐานหัวลูกศรทึบ (ซ้อนครึ่งพิกเซล) ทั้งสองปลาย ; หัวเปิด/ไม่มีหัว = ไม่ตัด', () {
    final cut = fcArrowSize(2) - 0.5;
    expect(fcLineRoute(edge(), straight), [(0.0, 0.0), (0.0, 100 - cut)]);
    expect(fcLineRoute(edge(start: FcArrow.arrow), straight), [(0.0, cut), (0.0, 100 - cut)]);
    expect(fcLineRoute(edge(end: FcArrow.open), straight), straight);
    expect(fcLineRoute(edge(end: FcArrow.none), straight), straight);
  });

  test('ท่อนสั้นกว่าระยะตัด: ตัดไม่เกินท่อน ปลายไม่ย้อนกลับ', () {
    expect(fcLineRoute(edge(), const [(0.0, 0.0), (20.0, 0.0), (20.0, 4.0)]).last, (20.0, 0.0));
  });

  test('ท่อนปลายสั้นกว่าหัวลูกศร: เลื่อนท่อนขวางถอยหลังจนพอ ปลายทั้งสองอยู่ที่เดิม', () {
    final out = fcRoomForArrows(edge(), const [(0.0, 0.0), (0.0, 94.0), (50.0, 94.0), (50.0, 100.0)]);
    final stub = fcArrowStub(edge(), FcArrow.arrow);
    expect(out, [(0.0, 0.0), (0.0, 100 - stub), (50.0, 100 - stub), (50.0, 100.0)]);
  });

  test('หัวลูกศรที่ต้นทางก็ได้ที่เหมือนกัน โดยไม่แย่งที่ของหัวปลายทาง', () {
    final both = edge(start: FcArrow.arrow);
    final stub = fcArrowStub(both, FcArrow.arrow);
    final out = fcRoomForArrows(both, const [(0.0, 0.0), (0.0, 5.0), (50.0, 5.0), (50.0, 100.0)]);
    expect(out[1].$2, stub);
    expect(out.last.$2 - out[2].$2, greaterThanOrEqualTo(stub));
  });

  test('ที่ไม่พอ: ยืดเท่าที่มี เหลือท่อนต้นทางไว้ ; เส้นตัว L หรือยาวพอแล้ว = ไม่แตะ', () {
    final tight = fcRoomForArrows(edge(), const [(0.0, 0.0), (0.0, 6.0), (12.0, 6.0), (12.0, 12.0)]);
    expect(tight, [(0.0, 0.0), (0.0, 2.0), (12.0, 2.0), (12.0, 12.0)]);
    const lShape = <RoutePoint>[(0.0, 0.0), (50.0, 0.0), (50.0, 5.0)];
    expect(fcRoomForArrows(edge(), lShape), lShape);
    const long = <RoutePoint>[(0.0, 0.0), (0.0, 40.0), (50.0, 40.0), (50.0, 100.0)];
    expect(fcRoomForArrows(edge(), long), long);
  });

  test('fcRoutes: สัญลักษณ์อยู่ชิดและเยื้องกัน ท่อนปลายยาวพอสำหรับหัวลูกศร', () {
    final d = FlowchartDiagram(nodes: [
      FcNode(id: 'a', shape: FcShape.process, x: 0, y: 0, w: 120, h: 50),
      FcNode(id: 'b', shape: FcShape.process, x: 40, y: 80, w: 120, h: 50),
    ], edges: [
      edge(width: 4),
    ]);
    final r = fcRoutes(d)['e']!;
    expect((r.last.$2 - r[r.length - 2].$2).abs(), greaterThanOrEqualTo(fcArrowStub(d.edges.single, FcArrow.arrow)));
  });

  test('Screen Flow: ท่อนปลายยาวพอ ตัวเส้นจบที่ฐานหัวลูกศร และ SVG ใช้ปลายตัด', () {
    final d = ScreenFlowDiagram(nodes: [
      SfNode(id: 'a', kind: SfKind.screen, x: 0, y: 0, w: 160, h: 120),
      SfNode(id: 'b', kind: SfKind.screen, x: 174, y: 60, w: 160, h: 120),
    ], edges: [
      SfEdge(id: 'e', fromId: 'a', toId: 'b'),
    ]);
    final r = sfRoutes(d)['e']!;
    final line = sfLineRoute(r);
    final dx = r.last.$1 - line.last.$1, dy = r.last.$2 - line.last.$2;
    final lastLen = (r.last.$1 - r[r.length - 2].$1).abs() + (r.last.$2 - r[r.length - 2].$2).abs();
    expect(dx.abs() + dy.abs(), closeTo(lastLen < kSfArrowSize - 0.5 ? lastLen : kSfArrowSize - 0.5, 0.001));
    final svg = exportScreenFlowSvg(d)!;
    expect(svg, contains('stroke-width="1.8" stroke-linejoin="round" stroke-linecap="butt"'));
  });

  test('SVG: เส้นจบก่อนปลายแหลม ปลายตัด และหัวลูกศรโปร่งเท่าตัวเส้น ; เส้นจุดยังปลายมน', () {
    final d = FlowchartDiagram(nodes: [
      FcNode(id: 'a', shape: FcShape.process, x: 0, y: 0, w: 120, h: 50),
      FcNode(id: 'b', shape: FcShape.process, x: 0, y: 130, w: 120, h: 50),
    ], edges: [
      edge(),
    ]);
    final svg = exportFlowchartSvg(d);
    expect(svg, contains('stroke-linecap="butt"'));
    expect(svg, contains(RegExp(r'<polygon points="60,130 [^"]+" fill="#[0-9A-Fa-f]{6}" fill-opacity="0.75"/>')));
    expect(svg, isNot(contains('L60 130"')));
    d.edges.single.dash = FcDash.dotted;
    expect(exportFlowchartSvg(d), contains('stroke-linecap="round" stroke-dasharray'));
  });
}
