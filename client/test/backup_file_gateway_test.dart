import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/data/platform/backup_file_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pactick/backup_files');
  const gateway = BackupFileGateway();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('exports exact Unicode JSON through the system picker', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'saveJson');
      expect(call.arguments, {
        'contents': '{"title":"本地专注 🌱"}',
        'suggestedName': 'my-backup.json',
      });
      return true;
    });
    expect(
      await gateway.saveJson(
        '{"title":"本地专注 🌱"}',
        suggestedName: 'my-backup.json',
      ),
      isTrue,
    );
  });

  test(
    'cancelled save and import are distinct from successful writes',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'saveJson' ? false : null,
      );
      expect(await gateway.saveJson('{}'), isFalse);
      expect(await gateway.openJson(), isNull);
    },
  );

  test(
    'imports content without changing it before archive validation',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => '{"version":900}',
      );
      expect(await gateway.openJson(), '{"version":900}');
    },
  );

  test(
    'file provider errors reach the UI instead of claiming success',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'backup_io_error');
      });
      await expectLater(
        gateway.saveJson('{}'),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(gateway.openJson(), throwsA(isA<PlatformException>()));
    },
  );
}
