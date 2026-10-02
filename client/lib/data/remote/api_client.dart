import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/sync/sync_models.dart';
import 'server_address.dart';

class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => '$code: $message';
}

class ApiNetworkException implements Exception {
  const ApiNetworkException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

abstract interface class SyncApi {
  Future<SyncPullResponse> pullChanges({required int cursor, int limit = 500});

  Future<SyncPushResponse> pushChanges(List<SyncOperation> operations);
}

class ApiClient implements SyncApi {
  ApiClient({
    String baseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: '',
    ),
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 15),
  }) : baseUri = Uri.parse(normalizeServerAddress(baseUrl)),
       _client = client ?? http.Client();

  Uri baseUri;
  bool get isConfigured => baseUri.host.isNotEmpty;

  void configureServer(String address) {
    baseUri = Uri.parse(normalizeServerAddress(address));
    accessToken = null;
  }

  Uri _resolve(String route) {
    if (!isConfigured) {
      throw const ApiException('server_not_configured', '请先配置同步服务器');
    }
    return baseUri.resolve(route);
  }

  final http.Client _client;
  final Duration requestTimeout;
  String? accessToken;

  Future<Map<String, Object?>> login({
    required String email,
    required String password,
    required Map<String, Object?> device,
  }) {
    return post('/v1/auth/login', {
      'email': email,
      'password': password,
      'device': device,
    }, authenticated: false);
  }

  Future<Map<String, Object?>> register({
    required String email,
    required String password,
    required String displayName,
    required String timeZone,
    required Map<String, Object?> device,
  }) {
    return post('/v1/auth/register', {
      'email': email,
      'password': password,
      'display_name': displayName,
      'time_zone': timeZone,
      'locale': 'zh-CN',
      'week_starts_on': 1,
      'device': device,
    }, authenticated: false);
  }

  Future<Map<String, Object?>> refresh(String refreshToken) {
    return post('/v1/auth/refresh', {
      'refresh_token': refreshToken,
    }, authenticated: false);
  }

  Future<void> logout(String refreshToken) async {
    await post('/v1/auth/logout', {
      'refresh_token': refreshToken,
    }, authenticated: false);
  }

  @override
  Future<SyncPullResponse> pullChanges({
    required int cursor,
    int limit = 500,
  }) async {
    final response = await get('/v1/sync/pull?cursor=$cursor&limit=$limit');
    return SyncPullResponse.fromJson(response);
  }

  @override
  Future<SyncPushResponse> pushChanges(List<SyncOperation> operations) async {
    final response = await post('/v1/sync/push', {
      'operations': operations.map((operation) => operation.toJson()).toList(),
    });
    return SyncPushResponse.fromJson(response);
  }

  Future<Map<String, Object?>> get(
    String route, {
    bool authenticated = true,
  }) async {
    try {
      final response = await _client
          .get(_resolve(route), headers: _headers(authenticated: authenticated))
          .timeout(requestTimeout);
      return _decode(response);
    } on TimeoutException catch (error) {
      throw ApiNetworkException('连接服务器超时', error);
    } on http.ClientException catch (error) {
      throw ApiNetworkException('无法连接服务器', error);
    } on HandshakeException catch (error) {
      throw ApiNetworkException('无法建立安全连接', error);
    } on SocketException catch (error) {
      throw ApiNetworkException('无法连接服务器', error);
    } on HttpException catch (error) {
      throw ApiNetworkException('服务器连接异常', error);
    }
  }

  Future<Map<String, Object?>> post(
    String route,
    Map<String, Object?> body, {
    bool authenticated = true,
  }) async {
    try {
      final response = await _client
          .post(
            _resolve(route),
            headers: _headers(authenticated: authenticated),
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);
      return _decode(response);
    } on TimeoutException catch (error) {
      throw ApiNetworkException('连接服务器超时', error);
    } on http.ClientException catch (error) {
      throw ApiNetworkException('无法连接服务器', error);
    } on HandshakeException catch (error) {
      throw ApiNetworkException('无法建立安全连接', error);
    } on SocketException catch (error) {
      throw ApiNetworkException('无法连接服务器', error);
    } on HttpException catch (error) {
      throw ApiNetworkException('服务器连接异常', error);
    }
  }

  Future<Map<String, Object?>> delete(
    String route, {
    bool authenticated = true,
    Map<String, Object?>? body,
  }) async {
    try {
      final response = await _client
          .delete(
            _resolve(route),
            headers: _headers(authenticated: authenticated),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(requestTimeout);
      return _decode(response);
    } on TimeoutException catch (error) {
      throw ApiNetworkException('连接服务器超时', error);
    } on http.ClientException catch (error) {
      throw ApiNetworkException('无法连接服务器', error);
    } on HandshakeException catch (error) {
      throw ApiNetworkException('无法建立安全连接', error);
    } on SocketException catch (error) {
      throw ApiNetworkException('无法连接服务器', error);
    } on HttpException catch (error) {
      throw ApiNetworkException('服务器连接异常', error);
    }
  }

  Map<String, String> _headers({bool authenticated = true}) {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (authenticated && accessToken != null)
        'Authorization': 'Bearer $accessToken',
    };
  }

  Map<String, Object?> _decode(http.Response response) {
    final Map<String, Object?> decoded;
    try {
      final value = response.body.isEmpty
          ? <String, Object?>{}
          : jsonDecode(response.body);
      if (value is! Map) throw const FormatException('Expected an object.');
      decoded = value.map((key, value) => MapEntry(key.toString(), value));
    } on FormatException {
      if (response.statusCode == 429) {
        throw const ApiException('rate_limited', '请求过于频繁', statusCode: 429);
      }
      if (response.statusCode >= 500) {
        throw ApiException(
          'server_unavailable',
          '服务器暂时不可用',
          statusCode: response.statusCode,
        );
      }
      throw ApiException(
        'invalid_response',
        '服务器返回了无法识别的响应',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    final error = decoded['error'];
    if (error is Map) {
      final values = error.map((key, value) => MapEntry(key.toString(), value));
      throw ApiException(
        values['code'] as String? ?? 'request_failed',
        values['message'] as String? ?? '请求失败',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode == 429) {
      throw const ApiException('rate_limited', '请求过于频繁', statusCode: 429);
    }
    if (response.statusCode >= 500) {
      throw ApiException(
        'server_unavailable',
        '服务器暂时不可用',
        statusCode: response.statusCode,
      );
    }
    throw ApiException(
      'request_failed',
      '请求失败（${response.statusCode}）',
      statusCode: response.statusCode,
    );
  }

  void close() => _client.close();
}
