import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/models/auth_models.dart';

abstract interface class SessionStore {
  Future<void> selectServer(String server);
  Future<void> selectIdentity(String identity);
  Future<AuthSession?> readSession();

  Future<void> writeSession(AuthSession session);

  Future<void> clearSession();

  Future<String?> readDeviceId();

  Future<void> writeDeviceId(String deviceId);
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorage();

  String _server = '';
  String _identity = '';
  String get _prefix => 'pactick.v2.${Uri.encodeComponent(_server)}';
  String get _sessionKey =>
      '$_prefix.session.${Uri.encodeComponent(_identity)}';
  String get _deviceIdKey =>
      '$_prefix.device.${Uri.encodeComponent(_identity)}';

  @override
  Future<void> selectServer(String server) async {
    _server = server;
    _identity = await _storage.read(key: '$_prefix.active_user') ?? '';
  }

  @override
  Future<void> selectIdentity(String identity) async {
    _identity = identity;
  }

  final FlutterSecureStorage _storage;

  @override
  Future<AuthSession?> readSession() async {
    final encoded = await _storage.read(key: _sessionKey);
    if (encoded == null || encoded.isEmpty) return null;
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) throw const FormatException('Invalid saved session.');
    return AuthSession.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  @override
  Future<void> writeSession(AuthSession session) async {
    _identity = session.user.id;
    await _storage.write(key: '$_prefix.active_user', value: _identity);
    await _storage.write(key: _deviceIdKey, value: session.device.id);
    await _storage.write(key: _sessionKey, value: jsonEncode(session.toJson()));
  }

  @override
  Future<void> clearSession() => _storage.delete(key: _sessionKey);

  @override
  Future<String?> readDeviceId() => _storage.read(key: _deviceIdKey);

  @override
  Future<void> writeDeviceId(String deviceId) {
    return _storage.write(key: _deviceIdKey, value: deviceId);
  }
}

class MemorySessionStore implements SessionStore {
  MemorySessionStore({this.session, this.deviceId});

  AuthSession? session;
  String? deviceId;
  String? _scope;
  String _server = '';
  final _sessions = <String, AuthSession?>{};
  final _devices = <String, String?>{};
  final _active = <String, String>{};

  void _select(String scope) {
    if (_scope == scope) return;
    if (_scope != null) {
      _sessions[_scope!] = session;
      _devices[_scope!] = deviceId;
      session = _sessions[scope];
      deviceId = _devices[scope];
    }
    _scope = scope;
  }

  @override
  Future<void> selectServer(String server) async {
    _server = server;
    _select('$server|${_active[server] ?? ''}');
  }

  @override
  Future<void> selectIdentity(String identity) async {
    _select('$_server|$identity');
  }

  @override
  Future<AuthSession?> readSession() async => session;

  @override
  Future<void> writeSession(AuthSession session) async {
    _active[_server] = session.user.id;
    _select('$_server|${session.user.id}');
    deviceId = session.device.id;
    this.session = session;
  }

  @override
  Future<void> clearSession() async {
    session = null;
  }

  @override
  Future<String?> readDeviceId() async => deviceId;

  @override
  Future<void> writeDeviceId(String deviceId) async {
    this.deviceId = deviceId;
  }
}
