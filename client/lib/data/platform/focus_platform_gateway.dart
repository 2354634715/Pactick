import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/models/domain_models.dart';

class InstalledApplication {
  const InstalledApplication({required this.packageName, required this.label});

  final String packageName;
  final String label;

  factory InstalledApplication.fromPlatform(Object? value) {
    final map = Map<Object?, Object?>.from(value! as Map);
    return InstalledApplication(
      packageName: map['packageName']! as String,
      label: map['label']! as String,
    );
  }
}

class GuardActivityStats {
  const GuardActivityStats({
    required this.appExitCount,
    required this.interruptionCount,
    this.sessionId,
  });

  final int appExitCount;
  final int interruptionCount;
  final String? sessionId;

  factory GuardActivityStats.fromPlatform(Object? value) {
    final map = Map<Object?, Object?>.from(value! as Map);
    return GuardActivityStats(
      appExitCount: (map['appExitCount'] as num?)?.toInt() ?? 0,
      interruptionCount: (map['interruptionCount'] as num?)?.toInt() ?? 0,
      sessionId: map['sessionId'] as String?,
    );
  }
}

class FocusTimerState {
  const FocusTimerState({this.sessionId, this.isActive = false});

  final String? sessionId;
  final bool isActive;
}

class FocusPlatformGateway {
  const FocusPlatformGateway();

  static const _channel = MethodChannel('pactick/focus');

  Future<FocusTimerState> getTimerState() async {
    if (!Platform.isAndroid) return const FocusTimerState();
    final result = await _channel.invokeMapMethod<String, Object?>(
      'getTimerState',
    );
    return FocusTimerState(
      sessionId: result?['sessionId'] as String?,
      isActive: result?['active'] == true,
    );
  }

  Future<void> startTimer({
    String? sessionId,
    required String title,
    required DateTime endsAt,
    required FocusPolicyMode mode,
    List<String> allowedPackageNames = const [],
    String taskTypeName = '收集箱',
    int? maxAppExits,
    bool paused = false,
    int appExitCount = 0,
    int interruptionCount = 0,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('startTimer', {
      'sessionId': sessionId,
      'title': title,
      'endsAtEpochMillis': endsAt.millisecondsSinceEpoch,
      'mode': mode.name,
      'allowedPackageNames': allowedPackageNames,
      'taskTypeName': taskTypeName,
      'maxAppExits': maxAppExits,
      'paused': paused,
      'appExitCount': appExitCount,
      'interruptionCount': interruptionCount,
    });
  }

  Future<void> pauseTimer() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('pauseTimer');
  }

  Future<void> resumeTimer(DateTime endsAt) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('resumeTimer', {
      'endsAtEpochMillis': endsAt.millisecondsSinceEpoch,
    });
  }

  Future<void> stopTimer() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('stopTimer');
  }

  Future<bool> hasUsageAccess() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('hasUsageAccess') ?? false;
  }

  Future<void> openUsageAccessSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openUsageAccessSettings');
  }

  Future<bool> hasOverlayPermission() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;
  }

  Future<void> openOverlayPermissionSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openOverlayPermissionSettings');
  }

  Future<List<InstalledApplication>> getInstalledApplications() async {
    if (!Platform.isAndroid) return const [];
    final result =
        await _channel.invokeListMethod<Object?>('getInstalledApplications') ??
        const [];
    return result
        .map(InstalledApplication.fromPlatform)
        .toList(growable: false);
  }

  Future<GuardActivityStats> getGuardActivityStats() async {
    if (!Platform.isAndroid) {
      return const GuardActivityStats(appExitCount: 0, interruptionCount: 0);
    }
    final result = await _channel.invokeMethod<Object?>(
      'getGuardActivityStats',
    );
    return GuardActivityStats.fromPlatform(result);
  }

  Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('requestNotificationPermission') ??
        false;
  }
}
