import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pactick/core/models/update_models.dart';
import 'package:pactick/data/remote/api_client.dart';
import 'package:pactick/data/update/client_update_service.dart';

void main() {
  group('ClientUpdateInfo', () {
    test('parses an available required update', () {
      final update = ClientUpdateInfo.fromJson({
        'status': 'update_available',
        'update_available': true,
        'required': true,
        'version': '1.4.0',
        'build_number': 140,
        'download_url': 'https://downloads.example.test/app.apk',
        'sha256': 'a' * 64,
        'size_bytes': 7340032,
        'release_notes': '修复同步问题',
        'published_at': '2026-09-19T04:30:00Z',
      });

      expect(update.status, ClientUpdateStatus.updateAvailable);
      expect(update.updateAvailable, isTrue);
      expect(update.required, isTrue);
      expect(update.version, '1.4.0');
      expect(update.buildNumber, 140);
      expect(
        update.downloadUri,
        Uri.parse('https://downloads.example.test/app.apk'),
      );
      expect(update.sizeBytes, 7340032);
      expect(update.releaseNotes, '修复同步问题');
      expect(update.publishedAt, DateTime.utc(2026, 9, 19, 4, 30));
    });

    test('parses an up-to-date response with release metadata', () {
      final update = ClientUpdateInfo.fromJson(_configuredResult('up_to_date'));

      expect(update.status, ClientUpdateStatus.upToDate);
      expect(update.updateAvailable, isFalse);
      expect(update.version, '1.3.0');
      expect(update.downloadUri, isNotNull);
    });

    test('parses a not-configured response', () {
      final update = ClientUpdateInfo.fromJson(_emptyResult('not_configured'));

      expect(update.status, ClientUpdateStatus.notConfigured);
      expect(update.updateAvailable, isFalse);
      expect(update.required, isFalse);
    });

    test('rejects inconsistent update status and availability', () {
      expect(
        () => ClientUpdateInfo.fromJson({
          ..._configuredResult('up_to_date'),
          'update_available': true,
        }),
        throwsFormatException,
      );
    });
  });

  group('ClientUpdateService', () {
    test(
      'sends installed Android version without requiring authentication',
      () async {
        late http.Request capturedRequest;
        final httpClient = MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode(_configuredResult('up_to_date')),
            200,
            headers: const {'content-type': 'application/json'},
          );
        });
        final apiClient = ApiClient(
          baseUrl: 'https://api.example.test',
          client: httpClient,
        )..accessToken = 'must-not-be-sent';
        final service = ClientUpdateService(
          apiClient: apiClient,
          installedVersionLoader: () async => const InstalledClientVersion(
            appName: 'Pactick',
            version: '1.2.3',
            buildNumber: 42,
          ),
        );

        final result = await service.checkForUpdate();

        expect(result.status, ClientUpdateStatus.upToDate);
        expect(capturedRequest.url.path, '/v1/client-updates/check');
        expect(capturedRequest.url.queryParameters, {
          'platform': 'android',
          'channel': 'stable',
          'current_version': '1.2.3',
          'build_number': '42',
        });
        expect(capturedRequest.headers, isNot(contains('authorization')));
        apiClient.close();
      },
    );

    test('turns an invalid server payload into a safe update error', () async {
      final apiClient = ApiClient(
        baseUrl: 'https://api.example.test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              ..._emptyResult('update_available'),
              'update_available': true,
            }),
            200,
          ),
        ),
      );
      final service = ClientUpdateService(
        apiClient: apiClient,
        installedVersionLoader: _testInstalledVersion,
      );

      await expectLater(
        service.checkForUpdate(),
        throwsA(
          isA<ClientUpdateException>().having(
            (error) => error.message,
            'message',
            contains('无法识别'),
          ),
        ),
      );
      apiClient.close();
    });

    test('rejects malformed release integrity metadata', () {
      expect(
        () => ClientUpdateInfo.fromJson({
          ..._configuredResult('update_available'),
          'update_available': true,
          'sha256': 'abc123',
        }),
        throwsFormatException,
      );
      expect(
        () => ClientUpdateInfo.fromJson({
          ..._configuredResult('update_available'),
          'update_available': true,
          'download_url': 'https://user@example.test/app.apk#fragment',
        }),
        throwsFormatException,
      );
      expect(
        () => ClientUpdateInfo.fromJson({
          ..._configuredResult('update_available'),
          'update_available': true,
          'size_bytes': 0,
        }),
        throwsFormatException,
      );
    });

    test('opens only HTTPS download URLs', () async {
      final opened = <Uri>[];
      final service = ClientUpdateService(
        apiClient: ApiClient(
          baseUrl: 'https://api.example.test',
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
        installedVersionLoader: _testInstalledVersion,
        externalUrlLauncher: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      final secureUpdate = _downloadUpdate(
        'https://downloads.example.test/app.apk',
      );
      final localUpdate = _uncheckedDownloadUpdate(
        'http://127.0.0.1:8080/app.apk',
      );
      final insecureUpdate = _uncheckedDownloadUpdate(
        'http://downloads.example.test/app.apk',
      );
      final fragmentedUpdate = _uncheckedDownloadUpdate(
        'https://downloads.example.test/app.apk#untrusted',
      );

      await service.openDownload(secureUpdate);
      await expectLater(
        service.openDownload(localUpdate),
        throwsA(
          isA<ClientUpdateException>().having(
            (error) => error.message,
            'message',
            contains('不安全'),
          ),
        ),
      );
      await expectLater(
        service.openDownload(insecureUpdate),
        throwsA(
          isA<ClientUpdateException>().having(
            (error) => error.message,
            'message',
            contains('不安全'),
          ),
        ),
      );
      await expectLater(
        service.openDownload(fragmentedUpdate),
        throwsA(isA<ClientUpdateException>()),
      );

      expect(opened, [secureUpdate.downloadUri]);
    });
  });
}

Map<String, Object?> _emptyResult(String status) => {
  'status': status,
  'update_available': false,
  'required': false,
  'version': null,
  'build_number': null,
  'download_url': null,
  'sha256': null,
  'size_bytes': null,
  'release_notes': null,
  'published_at': null,
};

Map<String, Object?> _configuredResult(String status) => {
  'status': status,
  'update_available': false,
  'required': false,
  'version': '1.3.0',
  'build_number': 43,
  'download_url': 'https://downloads.example.test/app.apk',
  'sha256': 'a' * 64,
  'size_bytes': 7340032,
  'release_notes': '',
  'published_at': '2026-09-19T04:30:00Z',
};

Future<InstalledClientVersion> _testInstalledVersion() async {
  return const InstalledClientVersion(
    appName: 'Pactick',
    version: '1.2.3',
    buildNumber: 42,
  );
}

ClientUpdateInfo _downloadUpdate(String url) {
  return ClientUpdateInfo.fromJson({
    'status': 'update_available',
    'update_available': true,
    'required': false,
    'version': '1.3.0',
    'build_number': 43,
    'download_url': url,
    'sha256': 'a' * 64,
    'size_bytes': 7340032,
    'release_notes': '',
    'published_at': '2026-09-19T04:30:00Z',
  });
}

ClientUpdateInfo _uncheckedDownloadUpdate(String url) {
  return ClientUpdateInfo(
    status: ClientUpdateStatus.updateAvailable,
    updateAvailable: true,
    required: false,
    version: '1.3.0',
    buildNumber: 43,
    downloadUri: Uri.parse(url),
    sha256: 'a' * 64,
    sizeBytes: 7340032,
    releaseNotes: '',
    publishedAt: DateTime.utc(2026, 9, 19, 4, 30),
  );
}
