import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/core/licenses/supplemental_licenses.dart';
import 'package:pactick/features/settings/pages/local_data_settings.dart';

void main() {
  testWidgets('about opens product licenses directly and returns to settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    registerSupplementalLicenses();
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        supportedLocales: [Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: ReleasesAboutCard()),
      ),
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('关于 Pactick'));
      await tester.pump();
      await LicenseRegistry.licenses.toList();
    });
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('许可'), findsOneWidget);
    expect(find.byType(AboutDialog), findsNothing);
    expect(tester.takeException(), isNull);

    final fontNotice = find.text('Material Icons (Flutter font)');
    await tester.scrollUntilVisible(fontNotice, 300);
    await tester.tap(fontNotice);
    await tester.pumpAndSettle();
    expect(find.textContaining('Attribution 4.0 International'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('关于 Pactick'), findsOneWidget);
    expect(find.byType(LicensePage), findsNothing);
    expect(find.byType(AboutDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
