import '../../core/ports/vault_lifecycle.dart';
import '../../core/ports/vault_repository.dart';

/// Existing encrypted record keys; not a new public format or schema.
enum WorkspaceRecord {
  layout('desktop.workbench.v1'),
  extensions('workbench.extensions.v1');

  const WorkspaceRecord(this.key);
  final String key;
}

/// Frontend-independent persistence of local workbench state. Records retain
/// their current JSON versions; the repository owns physical chunking/storage.
class WorkspaceStateStore {
  WorkspaceStateStore(this.vault);
  final VaultLifecycle vault;
  Future<void> _writes = Future.value();
  VaultRepository get _repository {
    if (!vault.isUnlocked) throw StateError('请先解锁资料库');
    if (vault.isMaintaining) throw StateError('资料库维护正在进行');
    return vault.repository;
  }

  Future<String?> read(WorkspaceRecord record) async {
    final generation = vault.sessionGeneration;
    final value = await _repository.readLocalValue(record.key);
    _current(generation);
    return value;
  }

  Future<void> write(WorkspaceRecord record, String value) {
    final generation = vault.sessionGeneration;
    final next = _writes.then(
      (_) => vault.runMutation(() async {
        // A queued write from a revoked view must not target a re-opened vault.
        _current(generation);
        await _repository.writeLocalValue(record.key, value);
        _current(generation);
      }),
    );
    _writes = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  void _current(int generation) {
    if (!vault.isUnlocked || generation != vault.sessionGeneration) {
      throw StateError('资料库已关闭或重开');
    }
  }
}
