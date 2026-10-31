import 'package:flutter/widgets.dart';

enum LanguagePreference {
  system,
  chinese,
  english;

  Locale? get locale => switch (this) {
    system => null,
    chinese => const Locale('zh', 'CN'),
    english => const Locale('en'),
  };

  static LanguagePreference parse(String? value) =>
      values.where((option) => option.name == value).firstOrNull ?? system;
}

/// Chinese variants use Simplified Chinese; all other languages use English.
Locale resolveAppLocale(Locale? requested) => requested?.languageCode == 'zh'
    ? const Locale('zh', 'CN')
    : const Locale('en');
