import 'package:flutter/foundation.dart';

/// The API is hosted at an origin, never below an arbitrary URL path.
String normalizeServerAddress(String value, {bool? allowDevelopmentHttp}) {
  if (value.trim().isEmpty) return '';
  final uri = Uri.tryParse(value.trim());
  final allowHttp =
      allowDevelopmentHttp ??
      (kDebugMode && const bool.fromEnvironment('ALLOW_INSECURE_LOCAL_SERVER'));
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      (uri.scheme != 'https' &&
          !(allowHttp &&
              uri.scheme == 'http' &&
              [
                'localhost',
                '127.0.0.1',
                '::1',
                '10.0.2.2',
              ].contains(uri.host)))) {
    throw const FormatException('请输入 HTTPS 服务器地址，不含路径、账号或查询参数。');
  }
  return Uri(
    scheme: uri.scheme.toLowerCase(),
    host: uri.host.toLowerCase(),
    port: uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80)
        ? uri.port
        : null,
  ).toString();
}

String serverWorkspaceId(Uri server, String userId) =>
    'server:${Uri.encodeComponent(server.toString())}:$userId';
