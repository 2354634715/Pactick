import 'dart:convert';

import '../sync/sync_entity_contract.dart';
import '../sync/sync_models.dart';
import 'domain_models.dart';

const defaultFocusPolicies = [
  FocusPolicyItem(
    id: '51111111-1111-4111-8111-111111111111',
    name: '灵活专注',
    mode: FocusPolicyMode.normal,
    allowPause: true,
    earlyExitMode: 'allow',
    notificationMode: 'vibrate',
  ),
  FocusPolicyItem(
    id: '52222222-2222-4222-8222-222222222222',
    name: '深度守护',
    mode: FocusPolicyMode.guard,
    allowPause: false,
    earlyExitMode: 'countdown',
    earlyExitWaitSeconds: 10,
    maxAppExits: 2,
    notificationMode: 'sound_and_vibrate',
  ),
];

bool isDuplicateDefaultFocusPolicyCreation(
  SyncOperation operation,
  String? errorCode,
) {
  if (errorCode != 'entity_exists' ||
      operation.entityType != SyncEntityType.focusPolicy ||
      operation.action != SyncAction.upsert ||
      operation.baseVersion != 0) {
    return false;
  }
  for (final policy in defaultFocusPolicies) {
    if (policy.id != operation.entityId) continue;
    final expected = SyncEntityContract.cloudPatch(
      SyncEntityType.focusPolicy,
      policy.toBody(),
    );
    final patch = operation.patch;
    return patch != null &&
        patch.length == expected.length &&
        operation.changedFields.length == expected.length &&
        operation.changedFields.toSet().containsAll(expected.keys) &&
        expected.entries.every(
          (entry) =>
              patch.containsKey(entry.key) &&
              jsonEncode(patch[entry.key]) == jsonEncode(entry.value),
        );
  }
  return false;
}
