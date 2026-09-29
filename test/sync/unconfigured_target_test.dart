import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_toko/app/providers.dart';
import 'package:smart_toko/core/db/dao/pending_sync_dao.dart';
import 'package:smart_toko/core/sync/remote_target.dart';

void main() {
  test(
    'default target never acknowledges a transaction without a backend',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final now = DateTime(2026, 9, 29);
      final outcome = await container
          .read(remoteSyncTargetProvider)
          .push(
            PendingSyncEntry(
              id: 'pending-1',
              entityType: 'transaction',
              entityId: 'tx-1',
              op: SyncOp.create,
              payload: const {'total': 10000},
              attemptCount: 0,
              nextAttemptAt: now,
              status: SyncStatus.pending,
              createdAt: now,
            ),
          );
      expect(outcome, isA<SyncRetryable>());
      expect((outcome as SyncRetryable).message, contains('belum tersedia'));
    },
  );
}
