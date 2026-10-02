class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.timeZone,
    required this.locale,
    required this.weekStartsOn,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String displayName;
  final String timeZone;
  final String locale;
  final int weekStartsOn;
  final DateTime createdAt;

  String get initials {
    final name = displayName.trim();
    if (name.isNotEmpty) return name.substring(0, 1).toUpperCase();
    return email.substring(0, 1).toUpperCase();
  }

  factory AuthUser.fromJson(Map<String, Object?> json) {
    return AuthUser(
      id: _requiredString(json, 'id'),
      email: _requiredString(json, 'email'),
      displayName: _requiredString(json, 'display_name'),
      timeZone: _requiredString(json, 'time_zone'),
      locale: _requiredString(json, 'locale'),
      weekStartsOn: _requiredInt(json, 'week_starts_on'),
      createdAt: _requiredDateTime(json, 'created_at'),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'email': email,
    'display_name': displayName,
    'time_zone': timeZone,
    'locale': locale,
    'week_starts_on': weekStartsOn,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}

class AuthDevice {
  const AuthDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.appVersion,
  });

  final String id;
  final String name;
  final String platform;
  final String appVersion;

  factory AuthDevice.fromJson(Map<String, Object?> json) {
    return AuthDevice(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      platform: _requiredString(json, 'platform'),
      appVersion: _requiredString(json, 'app_version'),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'app_version': appVersion,
  };
}

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
    required this.tokenType,
  });

  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;
  final DateTime refreshExpiresAt;
  final String tokenType;

  factory AuthTokens.fromJson(Map<String, Object?> json) {
    final tokenType = _requiredString(json, 'token_type');
    if (tokenType.toLowerCase() != 'bearer') {
      throw const FormatException('Unsupported token type.');
    }
    return AuthTokens(
      accessToken: _requiredString(json, 'access_token'),
      accessExpiresAt: _requiredDateTime(json, 'access_expires_at'),
      refreshToken: _requiredString(json, 'refresh_token'),
      refreshExpiresAt: _requiredDateTime(json, 'refresh_expires_at'),
      tokenType: tokenType,
    );
  }

  Map<String, Object?> toJson() => {
    'access_token': accessToken,
    'access_expires_at': accessExpiresAt.toUtc().toIso8601String(),
    'refresh_token': refreshToken,
    'refresh_expires_at': refreshExpiresAt.toUtc().toIso8601String(),
    'token_type': tokenType,
  };
}

class AuthSession {
  const AuthSession({
    required this.user,
    required this.device,
    required this.tokens,
  });

  final AuthUser user;
  final AuthDevice device;
  final AuthTokens tokens;

  factory AuthSession.fromJson(Map<String, Object?> json) {
    return AuthSession(
      user: AuthUser.fromJson(_requiredMap(json, 'user')),
      device: AuthDevice.fromJson(_requiredMap(json, 'device')),
      tokens: AuthTokens.fromJson(_requiredMap(json, 'tokens')),
    );
  }

  Map<String, Object?> toJson() => {
    'user': user.toJson(),
    'device': device.toJson(),
    'tokens': tokens.toJson(),
  };
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing or invalid "$key".');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('Missing or invalid "$key".');
  return value;
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('Missing or invalid "$key".');
  return parsed.toUtc();
}

Map<String, Object?> _requiredMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) throw FormatException('Missing or invalid "$key".');
  return value.map((key, value) => MapEntry(key.toString(), value));
}
