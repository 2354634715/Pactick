import 'dart:convert';

const calendarExposureSettingKey = 'system_calendar_exposed_v1';

/// Missing history is empty. Invalid history is an error, never a reason to
/// allow a transfer into the private vault or publish another ordinary record.
Set<String> decodeSystemCalendarExposure(String? encoded) {
  if (encoded == null) return <String>{};
  final Object? decoded;
  try {
    decoded = jsonDecode(encoded);
  } on FormatException {
    throw const FormatException('Invalid system calendar exposure history.');
  }
  if (decoded is! List) {
    throw const FormatException('Invalid system calendar exposure history.');
  }
  final values = <String>{};
  for (final value in decoded) {
    if (value is! String || !_validKey(value)) {
      throw const FormatException('Invalid system calendar exposure history.');
    }
    values.add(value);
  }
  return values;
}

String encodeSystemCalendarExposure(Set<String> values) {
  if (values.any((value) => !_validKey(value))) {
    throw const FormatException('Invalid system calendar exposure history.');
  }
  return jsonEncode(values.toList()..sort());
}

bool _validKey(String key) {
  final separator = key.indexOf('\u0000');
  return separator > 0 &&
      separator < key.length - 1 &&
      key.indexOf('\u0000', separator + 1) == -1 &&
      {'task', 'plan_block'}.contains(key.substring(0, separator));
}
