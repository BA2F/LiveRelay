import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/security/vault_archive_identity.dart';

void main() {
  test('stable snapshot id is deterministic and epoch sensitive', () async {
    const vaultId = '0123456789abcdef0123456789abcdef';
    final first = await stableArchiveSnapshotId(vaultId: vaultId, epoch: 1);
    final again = await stableArchiveSnapshotId(vaultId: vaultId, epoch: 1);
    final rotated = await stableArchiveSnapshotId(vaultId: vaultId, epoch: 2);
    final other = await stableArchiveSnapshotId(
      vaultId: 'fedcba9876543210fedcba9876543210',
      epoch: 1,
    );
    expect(first, again);
    expect(first, isNot(rotated));
    expect(first, isNot(other));
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(first), isTrue);
  });
}
