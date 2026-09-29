import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_toko/features/verification/ui/consent_screen.dart';

void main() {
  testWidgets('consent remains accessible on small screens with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: const ConsentScreen(
          storeId: 'store',
          storeName: 'Toko Sederhana',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.byType(CheckboxListTile), 300);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Lanjut'), 200);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Lanjut'))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}
