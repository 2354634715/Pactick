import '../../core/localization/app_localizations.dart';

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// The portable envelope contains no cleartext key or device-bound material.
class PrivateVaultEnvelope {
  const PrivateVaultEnvelope({
    required this.salt,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    this.runtime,
  });

  static const format = 'pactick-private-vault';
  static const version = 1;
  static const iterations = 600000;
  static const maxBytes = 50 * 1024 * 1024;
  final List<int> salt;
  final List<int> nonce;
  final List<int> ciphertext;
  final List<int> mac;

  /// Opaque session identifier and wall-clock times only, also authenticated.
  /// This permits a generic timer to survive locking and process restart.
  final Map<String, Object?>? runtime;

  Map<String, Object?> get _header => {
    'format': format,
    'version': version,
    'kdf': 'pbkdf2-hmac-sha256',
    'iterations': iterations,
    'salt': base64Encode(salt),
    'cipher': 'aes-256-gcm',
    'runtime': runtime,
  };
  List<int> get authenticatedData => utf8.encode(jsonEncode(_header));
  Map<String, Object?> toJson() => {
    ..._header,
    'nonce': base64Encode(nonce),
    'ciphertext': base64Encode(ciphertext),
    'mac': base64Encode(mac),
  };
  String encode() => jsonEncode(toJson());

  factory PrivateVaultEnvelope.decode(String encoded) {
    if (encoded.length > maxBytes || utf8.encode(encoded).length > maxBytes) {
      throw FormatException(tr('私密备份超过 50 MiB 限制。'));
    }
    final raw = jsonDecode(encoded);
    if (raw is! Map<String, dynamic> ||
        raw.length != 10 ||
        raw['format'] != format ||
        raw['version'] != version ||
        raw['kdf'] != 'pbkdf2-hmac-sha256' ||
        raw['iterations'] != iterations ||
        raw['cipher'] != 'aes-256-gcm' ||
        !raw.containsKey('runtime')) {
      throw FormatException(tr('不支持的私密备份格式或参数。'));
    }
    List<int> bytes(String key, [int? length]) {
      if (raw[key] is! String) {
        throw FormatException(tr('私密备份字段无效。'));
      }
      final value = base64Decode(raw[key] as String);
      if ((length != null && value.length != length) || value.isEmpty) {
        throw FormatException(tr('私密备份密文长度无效。'));
      }
      return value;
    }

    Map<String, Object?>? runtime;
    if (raw['runtime'] != null) {
      final timer = raw['runtime'];
      if (timer is! Map ||
          timer.length != 3 ||
          timer['session_id'] is! String ||
          !RegExp(r'^[a-zA-Z0-9-]{1,64}$')
              .hasMatch(timer['session_id'] as String) ||
          timer['started_at'] is! String ||
          timer['ends_at'] is! String) {
        throw FormatException(tr('私密计时数据无效。'));
      }
      final start = DateTime.tryParse(timer['started_at'] as String);
      final end = DateTime.tryParse(timer['ends_at'] as String);
      if (start == null ||
          end == null ||
          !end.isAfter(start) ||
          end.difference(start) > const Duration(hours: 24)) {
        throw FormatException(tr('私密计时时间无效。'));
      }
      runtime = {
        'session_id': timer['session_id'],
        'started_at': start.toUtc().toIso8601String(),
        'ends_at': end.toUtc().toIso8601String(),
      };
    }
    return PrivateVaultEnvelope(
      salt: bytes('salt', 32),
      nonce: bytes('nonce', 12),
      ciphertext: bytes('ciphertext'),
      mac: bytes('mac', 16),
      runtime: runtime,
    );
  }
}

class PrivateVaultCrypto {
  const PrivateVaultCrypto();

  static const ownershipSetting = 'private_focus_owned_runtime_v1';
  static Future<String> envelopeDigest(String envelope) async =>
      base64Encode((await Sha256().hash(utf8.encode(envelope))).bytes);

  static Future<String?> updateOwnership({
    required String accountId,
    required String? previous,
    required String? expectedEnvelope,
    required String envelope,
    bool claim = false,
  }) async {
    Map<String, Object?>? owner;
    try {
      if (previous != null) {
        owner = Map<String, Object?>.from(jsonDecode(previous) as Map);
      }
    } on Object {
      /* An invalid local marker never grants control. */
    }
    final runtime = PrivateVaultEnvelope.decode(envelope).runtime;
    if (runtime == null) {
      return owner?['account_id'] == accountId ? '{}' : previous;
    }
    final retained =
        owner?['account_id'] == accountId &&
        owner?['session_id'] == runtime['session_id'] &&
        expectedEnvelope != null &&
        owner?['envelope_digest'] == await envelopeDigest(expectedEnvelope);
    if (!claim && !retained) return previous;
    return jsonEncode({
      'account_id': accountId,
      'session_id': runtime['session_id'],
      'envelope_digest': await envelopeDigest(envelope),
    });
  }

  List<int> newSalt() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256));
  }

  Future<SecretKeyData> derive(String password, List<int> salt) async {
    // PBKDF2 runs off the UI isolate; the password is never persisted.
    final bytes = await Isolate.run(() => _derivePassword((password, salt)));
    return SecretKeyData(bytes, overwriteWhenDestroyed: true);
  }

  Future<PrivateVaultEnvelope> encrypt(
    String plaintext, {
    required SecretKey key,
    required List<int> salt,
    Map<String, Object?>? runtime,
  }) async {
    if (utf8.encode(plaintext).length > 35 * 1024 * 1024) {
      throw FormatException(tr('私密任务箱内容超过容量限制。'));
    }
    final header = PrivateVaultEnvelope(
      salt: salt,
      nonce: const [],
      ciphertext: const [],
      mac: const [],
      runtime: runtime,
    );
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      aad: header.authenticatedData,
    );
    return PrivateVaultEnvelope(
      salt: salt,
      nonce: box.nonce,
      ciphertext: box.cipherText,
      mac: box.mac.bytes,
      runtime: runtime,
    );
  }

  Future<String> decrypt(PrivateVaultEnvelope envelope, SecretKey key) async {
    final clear = await AesGcm.with256bits().decrypt(
      SecretBox(
        envelope.ciphertext,
        nonce: envelope.nonce,
        mac: Mac(envelope.mac),
      ),
      secretKey: key,
      aad: envelope.authenticatedData,
    );
    try {
      return utf8.decode(clear);
    } finally {
      // Managed strings may be retained by the VM; do not claim memory erasure.
      clear.fillRange(0, clear.length, 0);
    }
  }
}

Future<List<int>> _derivePassword((String, List<int>) input) async {
  final key = await Pbkdf2.hmacSha256(
    iterations: PrivateVaultEnvelope.iterations,
    bits: 256,
  ).deriveKeyFromPassword(password: input.$1, nonce: input.$2);
  try {
    return List<int>.of(await key.extractBytes());
  } finally {
    key.destroy();
  }
}
