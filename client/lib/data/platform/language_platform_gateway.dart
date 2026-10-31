import 'dart:io';

import 'package:flutter/services.dart';

/// Native reminders retain the language choice while Flutter is not running.
class LanguagePlatformGateway {
  const LanguagePlatformGateway();

  static const _channel = MethodChannel('pactick/language');

  Future<void> configure(String preference) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('configure', {'preference': preference});
  }
}
