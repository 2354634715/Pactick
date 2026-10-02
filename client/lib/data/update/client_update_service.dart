import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/update_models.dart';
import '../remote/api_client.dart';

typedef InstalledVersionLoader = Future<InstalledClientVersion> Function();
typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

class ClientUpdateException implements Exception {
  const ClientUpdateException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class ClientUpdateService {
  ClientUpdateService({
    ApiClient? apiClient,
    InstalledVersionLoader? installedVersionLoader,
    ExternalUrlLauncher? externalUrlLauncher,
    this.platform = 'android',
    this.channel = 'stable',
  }) : _apiClient = apiClient ?? ApiClient(),
       _ownsApiClient = apiClient == null,
       _installedVersionLoader =
           installedVersionLoader ?? _loadInstalledVersionFromPlatform,
       _externalUrlLauncher = externalUrlLauncher ?? _launchExternalUrl;

  final ApiClient _apiClient;
  final bool _ownsApiClient;
  final InstalledVersionLoader _installedVersionLoader;
  final ExternalUrlLauncher _externalUrlLauncher;
  final String platform;
  final String channel;

  Future<InstalledClientVersion> installedVersion() {
    return _installedVersionLoader();
  }

  Future<ClientUpdateInfo> checkForUpdate() async {
    final installed = await installedVersion();
    final route = Uri(
      path: '/v1/client-updates/check',
      queryParameters: {
        'platform': platform,
        'channel': channel,
        'current_version': installed.version,
        'build_number': installed.buildNumber.toString(),
      },
    );
    final response = await _apiClient.get(
      route.toString(),
      authenticated: false,
    );
    try {
      return ClientUpdateInfo.fromJson(response);
    } on FormatException catch (error) {
      throw ClientUpdateException('服务器返回了无法识别的更新信息', error);
    }
  }

  Future<void> openDownload(ClientUpdateInfo update) async {
    final uri = update.downloadUri;
    if (uri == null) {
      throw const ClientUpdateException('服务器没有提供下载地址');
    }
    if (!isSafeDownloadUri(uri)) {
      throw const ClientUpdateException('下载地址不安全，已阻止打开');
    }
    try {
      final launched = await _externalUrlLauncher(uri);
      if (!launched) {
        throw const ClientUpdateException('无法打开系统浏览器');
      }
    } on ClientUpdateException {
      rethrow;
    } catch (error) {
      throw ClientUpdateException('无法打开系统浏览器', error);
    }
  }

  static bool isSafeDownloadUri(Uri uri) {
    return uri.scheme.toLowerCase() == 'https' &&
        uri.hasAuthority &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.fragment.isEmpty;
  }

  void close() {
    if (_ownsApiClient) _apiClient.close();
  }

  static Future<InstalledClientVersion>
  _loadInstalledVersionFromPlatform() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final buildNumber = int.tryParse(packageInfo.buildNumber);
    if (packageInfo.version.trim().isEmpty ||
        buildNumber == null ||
        buildNumber < 1) {
      throw const ClientUpdateException('无法读取当前应用版本');
    }
    return InstalledClientVersion(
      appName: packageInfo.appName,
      version: packageInfo.version.trim(),
      buildNumber: buildNumber,
    );
  }

  static Future<bool> _launchExternalUrl(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
