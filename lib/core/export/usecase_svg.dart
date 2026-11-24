import '../layout/usecase_layout.dart';
import '../models/workspace.dart';
import 'svg_util.dart';

class _Theme {
  const _Theme({required this.canvas, required this.surface, required this.text, required this.muted, required this.line, required this.accent, required this.tint});
  final String canvas, surface, text, muted, line, accent, tint;
}

const _light = _Theme(canvas: '#F6F8FB', surface: '#FFFFFF', text: '#1B2430', muted: '#64748B', line: '#64748B', accent: '#4C8A2E', tint: '0.10');
const _dark = _Theme(canvas: '#121820', surface: '#19212B', text: '#E6EBF2', muted: '#94A3B8', line: '#94A3B8', accent: '#8BC568', tint: '0.18');

/// ภาพ SVG ของแผนภาพ Use Case ที่จัดวางโดย [layoutUseCaseDiagram] — null ถ้าไม่มี Use Case
/// [overrides] = ตำแหน่งที่ผู้ใช้ลาก ; [dark] = ธีมมืด ; [transparent] = ไม่มีพื้นหลัง
String? exportUseCaseSvg(Workspace w, {Map<String, (double, double)> overrides = const {}, bool dark = false, String? title, bool transparent = false}) {
  final d = layoutUseCaseDiagram(w, overrides: overrides);
  final bounds = d.bounds, boundary = d.boundary;
  if (d.isEmpty || bounds == null || boundary == null) return null;
  final th = dark ? _dark : _light;
  final width = bounds.right - bounds.left, height = bounds.bottom - bounds.top;
  final out = StringBuffer()
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" width="${svgNum(width)}" height="${svgNum(height)}" '
        'viewBox="${svgNum(bounds.left)} ${svgNum(bounds.top)} ${svgNum(width)} ${svgNum(height)}" font-family="$kSvgSans" font-size="13">')
    ..writeln('<title>${svgEsc(title ?? 'Use Case — ${d.systemName}')}</title>')
    ..writeln('<defs><marker id="uc-arrow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto" markerUnits="userSpaceOnUse">'
        '<path d="M1 1 L9 5 L1 9" fill="none" stroke="${th.line}" stroke-width="1.4"/></marker></defs>');
  if (!transparent) {
    out.writeln('<rect x="${svgNum(bounds.left)}" y="${svgNum(bounds.top)}" width="${svgNum(width)}" height="${svgNum(height)}" fill="${th.canvas}"/>');
  }
  // กรอบระบบ
  out
    ..writeln('<rect x="${svgNum(boundary.x)}" y="${svgNum(boundary.y)}" width="${svgNum(boundary.w)}" height="${svgNum(boundary.h)}" rx="10" '
        'fill="${th.surface}" fill-opacity="0.6" stroke="${th.muted}" stroke-width="1.4"/>')
    ..writeln('<text x="${svgNum(boundary.x + 14)}" y="${svgNum(boundary.y + 26)}" font-weight="700" fill="${th.muted}">${svgEsc(d.systemName)}</text>');

  // เส้น (วาดก่อนโหนด)
  for (final e in d.edges) {
    final line = ucEdgeLine(d, e);
    if (line == null) continue;
    final (x1, y1, x2, y2) = (line.x1, line.y1, line.x2, line.y2);
    final dashed = e.kind != UcEdgeKind.association;
    out.writeln('<line x1="${svgNum(x1)}" y1="${svgNum(y1)}" x2="${svgNum(x2)}" y2="${svgNum(y2)}" stroke="${th.line}" stroke-width="1.4"'
        '${dashed ? ' stroke-dasharray="7 5" marker-end="url(#uc-arrow)"' : ''}/>');
    if (dashed) {
      final mx = (x1 + x2) / 2, my = (y1 + y2) / 2 - 6;
      final tag = e.kind == UcEdgeKind.include ? '«include»' : '«extend»';
      out.writeln('<text x="${svgNum(mx)}" y="${svgNum(my)}" text-anchor="middle" font-style="italic" font-size="11.5" fill="${th.muted}" '
          'paint-order="stroke" stroke="${th.surface}" stroke-width="4">${svgEsc(tag)}</text>');
      if (e.condition.isNotEmpty) {
        out.writeln('<text x="${svgNum(mx)}" y="${svgNum(my + 14)}" text-anchor="middle" font-size="11" fill="${th.muted}" '
            'paint-order="stroke" stroke="${th.surface}" stroke-width="4">${svgEsc('[${svgWrap(e.condition, 160, 6.2, 1).first}]')}</text>');
      }
    }
  }

  // โหนด
  for (final n in d.nodes) {
    if (n.isActor) {
      final cx = n.cx, top = n.y;
      out
        ..writeln('<g>')
        ..writeln('<circle cx="${svgNum(cx)}" cy="${svgNum(top + 12)}" r="10" fill="none" stroke="${th.text}" stroke-width="1.6"/>')
        ..writeln('<path d="M${svgNum(cx)} ${svgNum(top + 22)} V${svgNum(top + 52)} M${svgNum(cx - 18)} ${svgNum(top + 33)} H${svgNum(cx + 18)} '
            'M${svgNum(cx)} ${svgNum(top + 52)} L${svgNum(cx - 14)} ${svgNum(top + 72)} M${svgNum(cx)} ${svgNum(top + 52)} L${svgNum(cx + 14)} ${svgNum(top + 72)}" '
            'fill="none" stroke="${th.text}" stroke-width="1.6" stroke-linecap="round"/>');
      final lines = svgWrap(n.label, kActorW + 20, 7.2, 2);
      for (final (i, line) in lines.indexed) {
        out.writeln('<text x="${svgNum(cx)}" y="${svgNum(top + 90 + i * 14)}" text-anchor="middle" font-weight="600" fill="${th.text}">${svgEsc(line)}</text>');
      }
      out.writeln('</g>');
    } else {
      final ell = 'cx="${svgNum(n.cx)}" cy="${svgNum(n.cy)}" rx="${svgNum(n.w / 2)}" ry="${svgNum(n.h / 2)}"';
      out
        ..writeln('<ellipse $ell fill="${th.surface}"/>')
        ..writeln('<ellipse $ell fill="${th.accent}" fill-opacity="${th.tint}" stroke="${th.accent}" stroke-width="1.7"/>');
      final lines = svgWrap(n.label, n.w - 44, 7.4, 2);
      final total = lines.length * 15 + 13;
      var y = n.cy - total / 2 + 12;
      for (final line in lines) {
        out.writeln('<text x="${svgNum(n.cx)}" y="${svgNum(y)}" text-anchor="middle" font-weight="600" fill="${th.text}">${svgEsc(line)}</text>');
        y += 15;
      }
      out.writeln('<text x="${svgNum(n.cx)}" y="${svgNum(y)}" text-anchor="middle" font-size="11" fill="${th.muted}">${svgEsc(n.sub)}</text>');
    }
  }
  out.writeln('</svg>');
  return out.toString();
}
