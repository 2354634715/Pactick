import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/core/licenses/supplemental_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled supplemental notices cover native libraries and font credit',
    () async {
      final entries = parseSupplementalLicenses(
        await rootBundle.loadString(supplementalLicenseAsset),
      ).toList();
      final names = entries.expand((entry) => entry.packages).toSet();
      expect(names, contains('Material Icons (Flutter font)'));
      expect(names, contains('FreeType'));
      expect(names, contains('Independent JPEG Group'));
      expect(
        names.any((name) => name.startsWith('androidx.core:core:')),
        isTrue,
      );
      expect(
        names.any(
          (name) => name.startsWith('org.jetbrains.kotlin:kotlin-stdlib:'),
        ),
        isTrue,
      );
      final font = entries.singleWhere(
        (entry) => entry.packages.contains('Material Icons (Flutter font)'),
      );
      expect(
        font.paragraphs.map((p) => p.text).join('\n'),
        contains('Attribution 4.0 International'),
      );
    },
  );

  test(
    'registry exposes font notice once after repeated registration',
    () async {
      registerSupplementalLicenses();
      registerSupplementalLicenses();
      final entries = await LicenseRegistry.licenses.toList();
      expect(
        entries.where(
          (entry) => entry.packages.contains('Material Icons (Flutter font)'),
        ),
        hasLength(1),
      );
    },
  );

  test('invalid notice assets fail instead of silently hiding obligations', () {
    for (final contents in [
      '{"schema_version":2,"entries":[]}',
      '{"schema_version":1,"entries":[]}',
      '{"schema_version":1,"entries":[{"packages":[],"text":"license"}]}',
      '{"schema_version":1,"entries":[{"packages":["native"],"text":""}]}',
    ]) {
      expect(
        () => parseSupplementalLicenses(contents).toList(),
        throwsFormatException,
      );
    }
  });
}
