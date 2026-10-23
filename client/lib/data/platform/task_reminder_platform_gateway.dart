import 'dart:io';

import 'package:flutter/services.dart';

class TaskReminderPlatformGateway {
  const TaskReminderPlatformGateway();

  static const _channel = MethodChannel('pactick/task_reminders');

  bool get isSupported => Platform.isAndroid;

  Future<bool> update({
    required bool enabled,
    required int openTaskCount,
    required String workspaceId,
    bool requestPermission = false,
    bool automatic = true,
  }) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('update', {
          'enabled': enabled,
          'openTaskCount': openTaskCount,
          'workspaceId': workspaceId,
          'requestPermission': requestPermission,
          'automatic': automatic,
        }) ??
        false;
  }

  Future<void> openNotificationSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('openNotificationSettings');
  }

  Future<void> clearWorkspace() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('clearWorkspace');
  }

  Future<bool> updateSchedule({
    required bool enabled,
    required String workspaceId,
    required List<Map<String, Object>> reminders,
    bool requestPermission = false,
    bool automatic = true,
  }) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('updateSchedule', {
          'enabled': enabled,
          'workspaceId': workspaceId,
          'reminders': reminders,
          'requestPermission': requestPermission,
          'automatic': automatic,
        }) ??
        false;
  }

  Future<void> openScheduledNotificationSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('openNotificationSettings', {
      'scheduled': true,
    });
  }

  Future<bool> takeOpenTasksRequest() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('takeOpenTasksRequest') ?? false;
  }
}
