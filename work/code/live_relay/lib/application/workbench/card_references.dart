import '../../core/domain/card_references.dart';
import '../../core/ports/vault_repository.dart';
export '../../core/domain/card_references.dart';

/// Compatibility wrapper for the existing internal call sites. The repository
/// reads current targets and applies domain rules inside one transaction.
class CardReferenceStore {
  const CardReferenceStore(this.repository);
  final VaultRepository repository;
  static const key = 'workbench.references.v1';
  Future<List<CardReference>> read() => repository.cardReferences();
  Future<void> replace(String from, List<String> targets) =>
      repository.setCardReferences(from, targets);
}
