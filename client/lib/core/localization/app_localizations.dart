import 'package:flutter/widgets.dart';

import 'english.dart';

/// UI messages use Chinese source text as stable catalog keys. User data is
/// never passed to this catalog. Placeholders are replaced after translation.
class AppLocalizations {
  AppLocalizations._();

  static String languageCode = 'zh';

  static String translate(
    String source, {
    String? languageCode,
    Map<String, Object?> args = const {},
  }) {
    final language = languageCode ?? AppLocalizations.languageCode;
    final template = language == 'en'
        ? englishTranslations[source] ?? source
        : source;
    return template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (match) {
      final name = match[1]!;
      return args.containsKey(name) ? '${args[name] ?? ''}' : match[0]!;
    });
  }
}

String tr(String source, {Map<String, Object?> args = const {}}) =>
    AppLocalizations.translate(source, args: args);

extension PactickTranslations on BuildContext {
  String tr(String source, {Map<String, Object?> args = const {}}) =>
      AppLocalizations.translate(
        source,
        languageCode: Localizations.localeOf(this).languageCode,
        args: args,
      );
}
