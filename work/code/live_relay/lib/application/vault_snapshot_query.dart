import 'dart:async';
import 'dart:convert';

import '../core/domain/card_references.dart';
import '../core/domain/entities.dart';
import '../core/ports/unlocked_vault.dart';
import '../core/ports/vault_repository.dart';

/// A typed application query result. Collection structure is immutable; UI
/// filters operate on this complete snapshot, never overwrite another view.
class VaultSnapshot {
  VaultSnapshot({
    required this.sessionGeneration,
    required List<LifeCard> cards,
    required List<CardReference> references,
    required List<VaultBlob> blobs,
    required Set<String> recycledBlobIds,
    required List<CredentialEntry> credentials,
    required List<ReleasePolicy> policies,
    required List<LifeStateEvent> lifeStateHistory,
    required this.lifeState,
    required this.insights,
    required List<LifeCard> recycledCards,
    required List<CredentialEntry> recycledCredentials,
    required this.lastBackupExport,
    required Map<String, Object?> ownerProfile,
  }) : cards = List.unmodifiable(cards),
       references = List.unmodifiable(references),
       blobs = List.unmodifiable(blobs),
       recycledBlobIds = Set.unmodifiable(recycledBlobIds),
       credentials = List.unmodifiable(credentials),
       policies = List.unmodifiable(policies),
       lifeStateHistory = List.unmodifiable(lifeStateHistory),
       recycledCards = List.unmodifiable(recycledCards),
       recycledCredentials = List.unmodifiable(recycledCredentials),
       ownerProfile = Map.unmodifiable(ownerProfile);
  final int sessionGeneration;
  final List<LifeCard> cards, recycledCards;
  final List<CardReference> references;
  final List<VaultBlob> blobs;
  final Set<String> recycledBlobIds;
  final List<CredentialEntry> credentials, recycledCredentials;
  final List<ReleasePolicy> policies;
  final List<LifeStateEvent> lifeStateHistory;
  final LifeState lifeState;
  final VaultInsights insights;
  final DateTime? lastBackupExport;
  final Map<String, Object?> ownerProfile;
}

class VaultSnapshotQuery {
  const VaultSnapshotQuery(this.vault);
  final UnlockedVault vault;
  static const defaultProfile = <String, Object?>{
    'name': '本人',
    'contact': '',
    'note': '',
  };

  Future<VaultSnapshot> load({bool includeOwnerProfile = true}) async {
    if (!vault.isUnlocked) throw StateError('请先解锁资料库');
    final generation = vault.sessionGeneration;
    final snapshot = await inspectRepository(
      vault.repository,
      sessionGeneration: generation,
      includeOwnerProfile: includeOwnerProfile,
    );
    if (!vault.isUnlocked || generation != vault.sessionGeneration) {
      throw StateError('资料库已关闭或重开，本次查询已丢弃');
    }
    return snapshot;
  }

  /// Trusted installation validation before exposing a restored session. The
  /// caller already owns an authenticated repository; no UI/session is unlocked.
  static Future<VaultSnapshot> inspectRepository(
    VaultRepository repository, {
    required int sessionGeneration,
    bool includeOwnerProfile = true,
  }) async {
    final values = await Future.wait<Object?>([
      repository.listCards(),
      repository.listBlobs(),
      repository.listCredentials(),
      repository.listReleasePolicies(),
      repository.lifeStateHistory(),
      repository.currentLifeState(),
      repository.insights(),
      repository.listCards(recycled: true),
      repository.listCredentials(recycled: true),
      CardReferenceStore(repository).read(),
      repository.recycledOriginalIds(),
      repository.lastBackupExport(),
      includeOwnerProfile
          ? repository.readLocalValue('identity.profile')
          : Future<String?>.value(),
    ]);
    return VaultSnapshot(
      sessionGeneration: sessionGeneration,
      cards: values[0] as List<LifeCard>,
      blobs: values[1] as List<VaultBlob>,
      credentials: values[2] as List<CredentialEntry>,
      policies: values[3] as List<ReleasePolicy>,
      lifeStateHistory: values[4] as List<LifeStateEvent>,
      lifeState: values[5] as LifeState,
      insights: values[6] as VaultInsights,
      recycledCards: values[7] as List<LifeCard>,
      recycledCredentials: values[8] as List<CredentialEntry>,
      references: values[9] as List<CardReference>,
      recycledBlobIds: (values[10] as List<String>).toSet(),
      lastBackupExport: values[11] as DateTime?,
      ownerProfile: values[12] == null
          ? defaultProfile
          : Map<String, Object?>.from(jsonDecode(values[12] as String) as Map),
    );
  }
}
