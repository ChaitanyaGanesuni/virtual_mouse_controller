import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The screen's main vertical list. (`find.byType(Scrollable).last` is not
/// it: selectable text has a Scrollable of its own.)
Finder mainList() => find
    .descendant(
      of: find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.vertical).first,
      matching: find.byType(Scrollable),
    )
    .first;

/// Scrolls [target] into view, clear of bars at the screen edges, and taps it.
Future<void> scrollToAndTap(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 200, scrollable: mainList());
  await tester.drag(mainList(), const Offset(0, -150));
  await tester.pumpAndSettle();
  await tester.tap(target);
}
