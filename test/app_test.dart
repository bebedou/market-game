import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_game/ui/app.dart';

void main() {
  for (final width in [320.0, 430.0, 1024.0]) {
    testWidgets('Starter renders at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MarketGameApp());

      expect(find.text('Market Game'), findsOneWidget);
      expect(find.text('Development environment ready'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
