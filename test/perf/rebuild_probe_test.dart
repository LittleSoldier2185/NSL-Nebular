// นับวิดเจ็ตที่ถูกสร้างใหม่ระหว่างแพน (หาว่าอะไรฟัง controller แล้ว rebuild ทุกเฟรม)
@Tags(['perf'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as w show debugOnRebuildDirtyWidget;
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

import 'diagrams_bench_test.dart' show build;

void main() {
  testWidgets('นับ rebuild ตอนเลือก', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(initialProject: build()));
    await tester.pump(const Duration(milliseconds: 500));
    final ws = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    final dfd = ws.dfdController('dfd')!, wf = ws.wireframeController('wf')!, sf = ws.screenflowController('sf')!;
    final fc = ws.flowchartController('fc')!;
    for (final (id, _, sel) in <(String, dynamic, void Function())>[
      ('dfd', dfd, () => dfd.selectNode('d150')),
      ('fc', fc, () => fc.selectNode('c150')),
      ('wf', wf, () => wf.selectBox('w500')),
      ('sf', sf, () => sf.selectBox('s150')),
    ]) {
      sel();
      void act(int i) => id == 'dfd'
          ? dfd.selectNode('d${i * 7 + 3}')
          : id == 'fc'
              ? fc.selectNode('c${i * 7 + 3}')
              : id == 'wf'
                  ? wf.selectBox('w${i * 7 + 3}')
                  : sf.selectBox('s${i * 7 + 3}');
      ws.openDocument(id);
      await tester.pumpAndSettle();
      final counts = <String, int>{};
      final times = <String, int>{};
      w.debugOnRebuildDirtyWidget = (e, _) => counts[e.widget.runtimeType.toString()] = (counts[e.widget.runtimeType.toString()] ?? 0) + 1;
      final sw = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        act(i);
        await tester.pump();
      }
      times[id] = sw.elapsedMilliseconds ~/ 5;
      w.debugOnRebuildDirtyWidget = null;
      final top = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      // ignore: avoid_print
      print('PROBE $id ${times[id]}ms/frame : ${top.where((e) => !RegExp(r'^(_?Inherited|Text|Rich|Raw|Default|Focus|_Focus|Actions|_Actions|Builder|Gesture|_Ink|_Parent|InkWell|InkResponse|Container|Padding|SizedBox|Row|Column|Expanded|Flexible|Icon|Material|_Material|_Shape|Notification|Semantics|MouseRegion|Listener|Align|Center|ConstrainedBox|DecoratedBox|Positioned|Stack|KeyedSubtree|ExcludeFocus|_Visibility|Tooltip|OverlayPortal|Animated|IconTheme|Theme|_Selection|KeepAlive|AutomaticKeepAlive|Cupertino|ListenableBuilder|ValueListenableBuilder|LayoutBuilder|Opacity|ClipRRect|ClipRect|Transform|CustomPaint|Wrap|Spacer|Divider|ColoredBox|Scrollbar|_Scroll|Visibility|Offstage|IgnorePointer|AbsorbPointer|Draggable|DragTarget|Card|ListTile|Ink|Hero|Flex|Baseline|FittedBox|LimitedBox|IntrinsicHeight|IntrinsicWidth|Directionality|MediaQuery|PrimaryScrollController|Shortcuts|_Shortcuts|DefaultTextStyle|DropdownMenuItem|DropdownButton|DropdownButtonHideUnderline|IndexedStack|Checkbox|_Checkbox|Radio|Switch|Slider|TextField|EditableText|_Editable|UndoHistory|TextFieldTapRegion|TapRegion|CompositedTransformTarget|CompositedTransformFollower|RepaintBoundary|Scrollable|Viewport|SliverList|NotificationListener|ScrollConfiguration|GlowingOverscrollIndicator|StretchingOverscrollIndicator|ListView|SingleChildScrollView|SliverPadding|_Sliver|Ticker|_Effective|AnimatedBuilder|FadeTransition|ScaleTransition|_RenderTheaterMarker|_Overlay|Overlay|_Theater|ModalBarrier|Navigator|_Inline|Button|IconButton|_IconButton|TextButton|FilledButton|OutlinedButton|ElevatedButton|_Button|ButtonStyleButton|Tab|PhysicalModel|PhysicalShape|_Painted|Image|RawImage|SafeArea|Builder|StatefulBuilder|Form|FormField|_Form|_TextField|InputDecorator|_Decorator|_Helper|_Border|_Scribble|Scribble|Selectable|SelectionContainer|SelectionArea|Badge|Chip|_Chip|RawChip)').hasMatch(e.key)).take(20).map((e) => '${e.key}=${e.value ~/ 5}').join(' ')}');
    }
  });
}
