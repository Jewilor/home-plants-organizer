import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_plants_organizer/main.dart';

void main() {
  testWidgets('Android wheel scrolling keeps content within its bounds', (
    tester,
  ) async {
    await tester.pumpWidget(const PlantApp());
    final scroll = find.byKey(const ValueKey('page-0'));
    expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
        )
        .position;
    final point = tester.getCenter(scroll);
    for (final delta in [2000.0, -2000.0]) {
      for (var i = 0; i < 20; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: point,
            scrollDelta: Offset(0, delta),
            kind: PointerDeviceKind.mouse,
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        position.pixels,
        inInclusiveRange(position.minScrollExtent, position.maxScrollExtent),
      );
      expect(
        position.pixels,
        delta > 0 ? position.maxScrollExtent : position.minScrollExtent,
      );
      expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
