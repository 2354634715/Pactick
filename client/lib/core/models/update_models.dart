enum ClientUpdateStatus {
  updateAvailable('update_available'),
  upToDate('up_to_date'),
  notConfigured('not_configured');

  const ClientUpdateStatus(this.wireValue);

  final String wireValue;

  static ClientUpdateStatus fromWireValue(String value) {
    for (final status in values) {
      if (status.wireValue == value) return status;
    }
    throw FormatException('Unsupported update status "$value".');
  }
}

class InstalledClientVersion {
  const InstalledClientVersion({
    required this.appName,
    required this.version,
    required this.buildNumber,
  });

  final String appName;
  final String version;
  final int buildNumber;

  String get displayVersion => '$version+$buildNumber';
}

class ClientUpdateInfo {
  const ClientUpdateInfo({
    required this.status,
    required this.updateAvailable,
    required this.required,
    this.version,
    this.buildNumber,
    this.downloadUri,
    this.sha256,
    this.sizeBytes,
    this.releaseNotes,
    this.publishedAt,
  });

  final ClientUpdateStatus status;
  final bool updateAvailable;
  final bool required;
  final String? version;
  final int? buildNumber;
  final Uri? downloadUri;
  final String? sha256;
  final int? sizeBytes;
  final String? releaseNotes;
  final DateTime? publishedAt;

  static final RegExp _semanticVersion = RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*)?$',
  );
  static final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _rfc3339 = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
  );
  static const _fields = {
    'status',
    'update_available',
    'required',
    'version',
    'build_number',
    'download_url',
    'sha256',
    'size_bytes',
    'release_notes',
    'published_at',
  };

  factory ClientUpdateInfo.fromJson(Map<String, Object?> json) {
    if (json.keys.any((key) => !_fields.contains(key)) ||
        _fields.any((key) => !json.containsKey(key))) {
      throw const FormatException('Unexpected client update fields.');
    }
    final status = ClientUpdateStatus.fromWireValue(
      _requiredString(json, 'status'),
    );
    final updateAvailable = _requiredBool(json, 'update_available');
    final required = _requiredBool(json, 'required');
    final version = _optionalString(json, 'version');
    final buildNumber = _optionalInt(json, 'build_number');
    final downloadUrl = _optionalString(json, 'download_url');
    final sha256 = _optionalString(json, 'sha256');
    final sizeBytes = _optionalInt(json, 'size_bytes');
    final rawReleaseNotes = json['release_notes'];
    if (rawReleaseNotes != null && rawReleaseNotes is! String) {
      throw const FormatException('Invalid "release_notes".');
    }
    final releaseNotes = rawReleaseNotes is String && rawReleaseNotes.isNotEmpty
        ? rawReleaseNotes
        : null;
    final publishedAt = _optionalDateTime(json, 'published_at');

    if (status == ClientUpdateStatus.updateAvailable && !updateAvailable) {
      throw const FormatException(
        'The update status and update_available flag disagree.',
      );
    }
    if (status != ClientUpdateStatus.updateAvailable && updateAvailable) {
      throw const FormatException(
        'The update status and update_available flag disagree.',
      );
    }
    if (required && !updateAvailable) {
      throw const FormatException('A required update must be available.');
    }
    if (version != null &&
        (version.length > 64 || !_semanticVersion.hasMatch(version))) {
      throw const FormatException('Invalid "version".');
    }
    if (buildNumber != null && buildNumber < 1) {
      throw const FormatException('Invalid "build_number".');
    }
    if (sha256 != null && !_sha256.hasMatch(sha256)) {
      throw const FormatException('Invalid "sha256".');
    }
    if (sizeBytes != null && sizeBytes < 1) {
      throw const FormatException('Invalid "size_bytes".');
    }
    if (rawReleaseNotes is String && rawReleaseNotes.runes.length > 20000) {
      throw const FormatException('Invalid "release_notes".');
    }

    Uri? downloadUri;
    if (downloadUrl != null) {
      downloadUri = Uri.tryParse(downloadUrl);
      if (downloadUrl.length > 2048 ||
          downloadUri == null ||
          !downloadUri.isAbsolute ||
          !downloadUri.hasAuthority ||
          downloadUri.scheme != 'https' ||
          downloadUri.host.isEmpty ||
          downloadUri.userInfo.isNotEmpty ||
          downloadUri.fragment.isNotEmpty) {
        throw const FormatException('Invalid "download_url".');
      }
    }

    final configured = status != ClientUpdateStatus.notConfigured;
    final hasCompleteRelease =
        version != null &&
        buildNumber != null &&
        downloadUri != null &&
        sha256 != null &&
        sizeBytes != null &&
        rawReleaseNotes is String &&
        publishedAt != null;
    final hasAnyReleaseField =
        version != null ||
        buildNumber != null ||
        downloadUri != null ||
        sha256 != null ||
        sizeBytes != null ||
        rawReleaseNotes != null ||
        publishedAt != null;
    if (configured && !hasCompleteRelease) {
      throw const FormatException(
        'A configured update response requires complete release metadata.',
      );
    }
    if (!configured && hasAnyReleaseField) {
      throw const FormatException(
        'A not-configured response cannot contain release metadata.',
      );
    }

    return ClientUpdateInfo(
      status: status,
      updateAvailable: updateAvailable,
      required: required,
      version: version,
      buildNumber: buildNumber,
      downloadUri: downloadUri,
      sha256: sha256,
      sizeBytes: sizeBytes,
      releaseNotes: releaseNotes,
      publishedAt: publishedAt,
    );
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing or invalid "$key".');
  }
  return value.trim();
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid "$key".');
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('Missing or invalid "$key".');
  return value;
}

int? _optionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int) throw FormatException('Invalid "$key".');
  return value;
}

DateTime? _optionalDateTime(Map<String, Object?> json, String key) {
  final value = _optionalString(json, key);
  if (value == null) return null;
  if (!ClientUpdateInfo._rfc3339.hasMatch(value)) {
    throw FormatException('Invalid "$key".');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('Invalid "$key".');
  return parsed.toUtc();
}
