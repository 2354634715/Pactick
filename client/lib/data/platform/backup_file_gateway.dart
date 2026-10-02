import 'dart:convert';

import 'package:flutter/services.dart';

/// Android Storage Access Framework: the user chooses every file and location.
/// No broad storage permission or credential-bearing temporary file is needed.
class BackupFileGateway {
  const BackupFileGateway();

  static const _channel = MethodChannel('pactick/backup_files');
  static const maxBytes = 50 * 1024 * 1024;

  Future<bool> saveJson(
    String content, {
    String suggestedName = 'pactick-backup.json',
  }) async {
    _checkSize(content);
    return await _channel.invokeMethod<bool>('saveJson', {
          'contents': content,
          'suggestedName': suggestedName,
        }) ??
        false;
  }

  Future<String?> openJson() async {
    final content = await _channel.invokeMethod<String>('openJson');
    if (content != null) _checkSize(content);
    return content;
  }

  static void _checkSize(String content) {
    if (content.length > maxBytes || utf8.encode(content).length > maxBytes) {
      throw const FormatException('备份超过 50 MiB 限制。');
    }
  }
}
