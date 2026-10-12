import 'dart:async';

import '../../core/ai/outbound_consent.dart';
import '../../core/ports/outbound_consent_repository.dart';

/// 前端无关的外发授权用例。授权写入成功后才在内存生效：
/// 存储失败时保持未授权，下一次发送仍然拦一次，不静默放行。
class OutboundConsentService {
  OutboundConsentService(this._repository);
  final OutboundConsentRepository _repository;
  final _changes = StreamController<void>.broadcast(sync: true);
  Map<String, Set<OutboundKind>> _grants = const {};
  bool _disposed = false;
  Stream<void> get changes => _changes.stream;

  Future<void> initialize() async {
    try {
      _grants = await _repository.read();
    } on Object {
      _grants = const {};
    }
    if (!_disposed) _changes.add(null);
  }

  bool granted(OutboundDestination destination, OutboundKind kind) =>
      _grants[destination.id]?.contains(kind) ?? false;

  Set<OutboundKind> grantedKinds(String destinationId) =>
      _grants[destinationId] ?? const {};

  Future<void> grant(OutboundDestination destination, OutboundKind kind) async {
    final next = {
      for (final entry in _grants.entries) entry.key: {...entry.value},
    };
    (next[destination.id] ??= <OutboundKind>{}).add(kind);
    await _persist(next);
  }

  /// 收回该服务的全部外发授权；下次发送重新按首次处理。
  Future<void> revoke(String destinationId) async {
    if (!_grants.containsKey(destinationId)) return;
    final next = {
      for (final entry in _grants.entries)
        if (entry.key != destinationId) entry.key: {...entry.value},
    };
    await _persist(next);
  }

  Future<void> _persist(Map<String, Set<OutboundKind>> next) async {
    if (_disposed) throw StateError('外发授权服务已关闭');
    await _repository.write(next);
    if (_disposed) return;
    _grants = {
      for (final entry in next.entries)
        entry.key: Set<OutboundKind>.unmodifiable(entry.value),
    };
    _changes.add(null);
  }

  void dispose() {
    _disposed = true;
    unawaited(_changes.close());
  }
}
