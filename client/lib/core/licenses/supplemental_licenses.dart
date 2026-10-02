import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const supplementalLicenseAsset = 'assets/licenses/supplemental.json';
bool _registered = false;

Iterable<LicenseEntry> parseSupplementalLicenses(String contents) sync* {
  final document = jsonDecode(contents);
  if (document is! Map<String, dynamic> || document['schema_version'] != 1) {
    throw const FormatException('不支持的补充许可格式');
  }
  final entries = document['entries'];
  if (entries is! List || entries.isEmpty) {
    throw const FormatException('补充许可清单为空');
  }
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) {
      throw const FormatException('补充许可条目无效');
    }
    final packages = entry['packages'];
    final text = entry['text'];
    if (packages is! List ||
        packages.isEmpty ||
        packages.any((name) => name is! String || name.trim().isEmpty) ||
        text is! String ||
        text.trim().isEmpty) {
      throw const FormatException('补充许可缺少组件名称或正文');
    }
    yield LicenseEntryWithLineBreaks(packages.cast<String>(), text);
  }
}

void registerSupplementalLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    final contents = await rootBundle.loadString(supplementalLicenseAsset);
    for (final entry in parseSupplementalLicenses(contents)) {
      yield entry;
    }
  });
}
