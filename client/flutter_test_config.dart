import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/core/localization/app_localizations.dart';

/// Existing Chinese GUI expectations use an explicit system locale. Locale
/// tests override it to exercise English and unsupported-language fallback.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
    binding.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
    AppLocalizations.languageCode = 'zh';
  });
  await testMain();
}
