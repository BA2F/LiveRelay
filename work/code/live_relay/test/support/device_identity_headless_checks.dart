// Ordinary Dart. Real AES-GCM/HPKE/signatures; fast password KDF fixture only.
// Existing local_handoff/native delivery checks cover the production Argon2 KDF.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:live_relay/application/device_preferences_runtime.dart';
import 'package:live_relay/application/identity/recipient_runtime.dart';
import 'package:live_relay/core/device/device_preferences.dart';
import 'package:live_relay/core/identity/hpke.dart';
import 'package:live_relay/core/identity/local_identity.dart';
import 'package:live_relay/core/ports/device_preferences_repository.dart';
import 'package:live_relay/core/ports/recipient_store.dart';
import 'package:live_relay/core/security/header_encoding.dart';
import 'package:live_relay/core/security/owner_crypto.dart';

void check(bool v, String reason) {
  if (!v) throw StateError(reason);
}

Future<void> reject(Future<Object?> value, String message) async {
  Object? failure;
  try {
    await value;
  } on Object catch (e) {
    failure = e;
  }
  check(
    failure != null && '$failure'.contains(message),
    'Expected $message; got $failure',
  );
}

Future<SecretKey> fixtureKey(String password, List<int> salt) async =>
    SecretKey((await Sha256().hash([...utf8.encode(password), ...salt])).bytes);

class PreferencesStore implements DevicePreferencesRepository {
  Map<String, Object?>? data;
  bool fail = false;
  int writes = 0;
  Completer<void>? wait;
  Completer<void> entered = Completer();
  @override
  Future<Map<String, Object?>?> read() async => data;
  @override
  Future<void> write(Map<String, Object?> value) async {
    writes++;
    if (!entered.isCompleted) entered.complete();
    await wait?.future;
    if (fail) throw StateError('write denied');
    data = Map.of(value);
  }
}

class IdentityStore implements RecipientStore {
  Uint8List? data;
  Uint8List? lastRead, borrowedWrite;
  bool failWrite = false;
  int writes = 0;
  final packages = <String, Uint8List>{};
  Completer<void>? waitIdentity, waitPackage;
  Completer<void> identityEntered = Completer(), packageEntered = Completer();
  @override
  Future<void> initialize() async {}
  @override
  Future<Uint8List?> readIdentity() async =>
      lastRead = data == null ? null : Uint8List.fromList(data!);
  @override
  Future<void> writeIdentity(Uint8List value) async {
    borrowedWrite = value;
    writes++;
    if (!identityEntered.isCompleted) identityEntered.complete();
    await waitIdentity?.future;
    if (failWrite) throw StateError('write denied');
    data = Uint8List.fromList(value);
  }

  @override
  Future<void> writePackage(String id, Uint8List bytes) async {
    if (!packageEntered.isCompleted) packageEntered.complete();
    await waitPackage?.future;
    packages[id] = Uint8List.fromList(bytes);
  }

  @override
  Future<List<SavedRecipientPackage>> savedPackages() async => packages.keys
      .map((id) => SavedRecipientPackage('/fixture/$id.lrshare'))
      .toList();
}

class Fixture {
  final store = IdentityStore();
  late final recipient = RecipientRuntime(store, derivePasswordKey: fixtureKey);
  LocalIdentity? owner;
  Future<void> initialize() async {
    await recipient.initialize();
    await recipient.create('Public recipient', 'public-fixture-password');
    owner = await LocalIdentity.create('Public owner');
  }

  Future<String> get ownerFingerprint => owner!.fingerprint();
  Future<Uint8List> package({int sequence = 1}) async {
    final clear = LocalIdentity.encodeJson({
      'version': 1,
      'records': [
        {
          'type': 'card',
          'id': 'public-card',
          'level': 'full',
          'title': 'Public fixture',
          'body': 'Public text',
          'history': [],
          'originalIds': [],
        },
      ],
      'originals': <String, Object?>{},
    });
    try {
      final header = <String, Object?>{
        'version': 1,
        'kind': 'scoped-delivery',
        'packageId': sequence.toRadixString(16).padLeft(32, '0'),
        'owner': await owner!.publicData(),
        'recipient': await recipient.identity!.fingerprint(),
        'scopeEpoch': 1,
        'sequence': sequence,
        'createdAt': DateTime.utc(2026).toIso8601String(),
        'scopeDigest': HeaderEncoding.hex((await Sha256().hash(clear)).bytes),
      };
      final unsigned = {
        ...header,
        'box': await LocalHpke.seal(
          clear,
          (await recipient.identity!.dh.extractPublicKey()).bytes,
          HeaderEncoding.encode(header),
        ),
      };
      return HeaderEncoding.encode({
        ...unsigned,
        'signature': await owner!.sign(HeaderEncoding.encode(unsigned)),
      });
    } finally {
      OwnerCrypto.wipe(clear);
    }
  }

  void dispose() {
    recipient.dispose();
    owner?.dispose();
  }
}

Map<String, Future<void> Function()> deviceIdentityChecks() => {
  'headless preferences serialize choices and preserve old vault onboarding':
      () async {
        final store = PreferencesStore(),
            runtime = DevicePreferencesRuntime(PreferencesStore());
        final prefs = DevicePreferencesRuntime(store);
        try {
          await prefs.load(hasExistingVault: false);
          await Future.wait([
            prefs.setAppearance(mode: AppearanceMode.dark),
            prefs.setAppearance(size: ReadingSize.large),
            prefs.beginOnboarding(),
            prefs.setDesktopPreset('library'),
          ]);
          final reopened = DevicePreferencesRuntime(store);
          try {
            await reopened.load(hasExistingVault: true);
            check(
              reopened.state.appearance == AppearanceMode.dark &&
                  reopened.state.readingSize == ReadingSize.large &&
                  reopened.state.onboardingStarted &&
                  !reopened.state.onboardingComplete &&
                  reopened.state.desktopPreset == 'library',
              'Choices lost',
            );
            store.data = {'version': 999};
            await reopened.load(hasExistingVault: true);
            check(
              reopened.state.onboardingComplete &&
                  reopened.state.appearance == AppearanceMode.system,
              'Broken settings initiated onboarding',
            );
            await reject(reopened.setDesktopPreset('unsupported'), '不支持');
          } finally {
            reopened.dispose();
          }
          await runtime.load(hasExistingVault: false);
          check(!runtime.state.onboardingComplete, 'Fresh onboarding lost');
        } finally {
          prefs.dispose();
          runtime.dispose();
        }
      },
  'headless preferences retain last persisted state and queue recovers from failure':
      () async {
        final store = PreferencesStore(),
            prefs = DevicePreferencesRuntime(PreferencesStore());
        final runtime = DevicePreferencesRuntime(store);
        try {
          await runtime.setAppearance(mode: AppearanceMode.light);
          store.fail = true;
          await reject(runtime.finishOnboarding(), 'write denied');
          check(
            runtime.state.appearance == AppearanceMode.light &&
                !runtime.state.onboardingComplete,
            'Failed write applied',
          );
          store.fail = false;
          await runtime.finishOnboarding();
          check(runtime.state.onboardingComplete, 'Queue stayed rejected');
        } finally {
          runtime.dispose();
          prefs.dispose();
        }
      },
  'disposed preferences discard late write and never start queued writes':
      () async {
        final store = PreferencesStore()..wait = Completer<void>();
        final runtime = DevicePreferencesRuntime(store);
        int events = 0;
        final subscription = runtime.changes.listen((_) => events++);
        final first = reject(
          runtime.setAppearance(mode: AppearanceMode.dark),
          '已关闭',
        );
        final second = reject(runtime.finishOnboarding(), '已关闭');
        await store.entered.future;
        runtime.dispose();
        store.wait!.complete();
        await Future.wait([first, second]);
        check(
          store.writes == 1 &&
              events == 0 &&
              runtime.state.appearance == AppearanceMode.system,
          'Late write revived state',
        );
        await subscription.cancel();
      },
  'headless recipient encrypted restore retains replay receipts and immutable view':
      () async {
        final f = Fixture();
        final restored = RecipientRuntime(
          IdentityStore(),
          derivePasswordKey: fixtureKey,
        );
        try {
          await f.initialize();
          final bytes = await f.package(), fp = await f.ownerFingerprint;
          await reject(f.recipient.receive(bytes, 'wrong owner'), '不匹配');
          await f.recipient.receive(bytes, fp);
          check(
            f.recipient.snapshot!['ownerName'] == 'Public owner',
            'Verified snapshot missing',
          );
          bool immutable = false;
          try {
            (f.recipient.snapshot!['records'] as List).clear();
          } on UnsupportedError {
            immutable = true;
          }
          check(immutable, 'Shared view mutated');
          await reject(f.recipient.receive(bytes, fp), '重复');
          final backup = await f.recipient.exportProtectedIdentity();
          await restored.initialize();
          await restored.importProtectedIdentity(
            backup,
            'public-fixture-password',
          );
          check(
            await restored.identity!.fingerprint() ==
                await f.recipient.identity!.fingerprint(),
            'Imported wrong identity',
          );
          await reject(restored.receive(bytes, fp), '重复');
          f.recipient.lock();
          check(
            f.recipient.snapshot == null && f.recipient.identity == null,
            'Lock retained private view',
          );
          await f.recipient.unlock('public-fixture-password');
          await f.recipient.receive(bytes, fp, saved: true);
          check(
            (await f.recipient.savedPackages()).length == 1,
            'Saved package lost',
          );
        } finally {
          f.dispose();
          restored.dispose();
        }
      },
  'locking during recipient creation retains committed identity without late unlock':
      () async {
        final store = IdentityStore()..waitIdentity = Completer<void>();
        final runtime = RecipientRuntime(store, derivePasswordKey: fixtureKey);
        try {
          await runtime.initialize();
          final rejected = reject(
            runtime.create('Public recipient', 'public-fixture-password'),
            '取消',
          );
          await store.identityEntered.future;
          await reject(
            runtime.create('Other recipient', 'public-fixture-password'),
            '等待',
          );
          runtime.lock();
          store.waitIdentity!.complete();
          await rejected;
          check(
            runtime.identity == null &&
                runtime.exists &&
                !runtime.busy &&
                store.borrowedWrite!.every((b) => b == 0),
            'Late creation reopened',
          );
          store.waitIdentity = null;
          await runtime.unlock('public-fixture-password');
          check(
            runtime.identity!.name == 'Public recipient',
            'Durable identity inaccessible',
          );
        } finally {
          runtime.dispose();
        }
      },
  'disposed recipient discards pending password key and read buffer': () async {
    final f = Fixture();
    final gate = Completer<SecretKey>(), entered = Completer<void>();
    Uint8List? borrowedSalt;
    try {
      await f.initialize();
      final runtime = RecipientRuntime(
        f.store,
        derivePasswordKey: (p, s) async {
          borrowedSalt = s as Uint8List;
          entered.complete();
          return gate.future;
        },
      );
      await runtime.initialize();
      final rejected = reject(runtime.unlock('public-fixture-password'), '已关闭');
      await entered.future;
      runtime.dispose();
      final key = SecretKey(List.filled(32, 4));
      gate.complete(key);
      await rejected;
      check(
        key.isDestroyed &&
            borrowedSalt!.every((b) => b == 0) &&
            f.store.lastRead!.every((b) => b == 0) &&
            runtime.identity == null &&
            !runtime.busy,
        'Disposed unlock retained key or identity',
      );
    } finally {
      f.dispose();
    }
  },
  'lock during recipient package commit never rewrites identity or publishes plaintext':
      () async {
        final f = Fixture();
        try {
          await f.initialize();
          final bytes = await f.package(),
              fp = await f.ownerFingerprint,
              previous = f.store.writes;
          f.store.waitPackage = Completer<void>();
          final rejected = reject(f.recipient.receive(bytes, fp), '取消');
          await f.store.packageEntered.future;
          f.recipient.lock();
          f.store.waitPackage!.complete();
          await rejected;
          check(
            f.store.writes == previous &&
                f.recipient.snapshot == null &&
                f.recipient.identity == null,
            'Lock revived state or receipt',
          );
          f.store.waitPackage = null;
          await f.recipient.unlock('public-fixture-password');
          await f.recipient.receive(bytes, fp);
          check(
            f.recipient.snapshot != null,
            'Interrupted receive could not retry',
          );
        } finally {
          f.dispose();
        }
      },
  'failed recipient receipt save remains retryable and rejects concurrent replay':
      () async {
        final f = Fixture();
        try {
          await f.initialize();
          final bytes = await f.package(), fp = await f.ownerFingerprint;
          f.store.failWrite = true;
          await reject(f.recipient.receive(bytes, fp), 'write denied');
          check(
            f.recipient.snapshot == null && f.recipient.identity != null,
            'Failed write claimed snapshot',
          );
          f.store.failWrite = false;
          f.store.waitIdentity = Completer<void>();
          f.store.identityEntered = Completer<void>();
          final accepted = f.recipient.receive(bytes, fp);
          await f.store.identityEntered.future;
          await reject(f.recipient.receive(bytes, fp), '等待');
          f.store.waitIdentity!.complete();
          await accepted;
          await reject(f.recipient.receive(bytes, fp), '重复');
        } finally {
          f.dispose();
        }
      },
};
Future<void> main() async {
  for (final entry in deviceIdentityChecks().entries) {
    await entry.value();
    stdout.writeln('PASS ${entry.key}');
  }
}
