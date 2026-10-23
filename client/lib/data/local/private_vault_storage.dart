import 'workspace_archive.dart';

/// Only ciphertext and nonsecret retry metadata cross this persistence API.
class PrivateVaultStoredState {
  const PrivateVaultStoredState({
    required this.envelope,
    this.failedAttempts = 0,
    this.retryAfter,
  });
  final String envelope;
  final int failedAttempts;
  final DateTime? retryAfter;
}

class PrivateTransferBundle {
  const PrivateTransferBundle({
    required this.documents,
    required this.removedKeys,
    required this.snapshot,
  });
  final List<ArchiveDocument> documents;
  final Set<String> removedKeys;
  final String snapshot;
}

abstract interface class PrivateVaultStorage {
  Future<PrivateVaultStoredState?> readPrivateVault(String accountId);

  /// Compare-and-swap. A null expected value means the vault must not exist.
  Future<void> writePrivateVault(
    String accountId,
    String envelope, {
    required String? expectedEnvelope,
    bool ownsFocusRuntime = false,
  });

  Future<PrivateVaultStoredState> recordPrivateVaultFailure(String accountId);
  Future<void> resetPrivateVaultFailures(String accountId);

  /// Restores to a new, offline workspace and preserves every existing row.
  Future<void> restorePrivateVault(String accountId, String envelope);

  Future<PrivateTransferBundle> readPrivateImportCandidate(
    String accountId,
    String taskId,
  );

  /// Rechecks the candidate and queue before atomically replacing the vault
  /// and removing the ordinary documents and every related outbox entry.
  Future<void> commitPrivateImport(
    String accountId, {
    required String expectedEnvelope,
    required String envelope,
    required String taskId,
    required String expectedSnapshot,
  });

  Future<void> commitPrivateExport(
    String accountId, {
    required String expectedEnvelope,
    required String envelope,
    required List<ArchiveDocument> documents,
  });
}
