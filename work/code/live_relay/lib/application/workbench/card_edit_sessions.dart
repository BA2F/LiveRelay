import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/domain/entities.dart';

enum CardSaveState { saved, pending, saving, failed }

class CardEditSession {
  CardEditSession(this.card)
    : title = card.title,
      content = card.content,
      tags = card.tags.join(', ');
  LifeCard card;
  String title, content, tags;
  int generation = 0;
  CardSaveState state = CardSaveState.saved;
  String? error;
  CardDraft get draft => CardDraft(
    title: title,
    content: content,
    kind: card.kind,
    status: card.status,
    tags: tags
        .split(RegExp('[,，]'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(),
  );
}

/// One edit buffer per object, independent of view lifetime. No plaintext disk.
class CardEditSessions extends ChangeNotifier {
  CardEditSessions({
    required this.save,
    required this.canSave,
    this.debounce = const Duration(milliseconds: 650),
  });
  final Future<void> Function(String id, CardDraft draft) save;
  final bool Function() canSave;
  final Duration debounce;
  final _sessions = <String, CardEditSession>{};
  Timer? _timer;
  Future<void>? _saving;
  bool _disposed = false;
  Iterable<CardEditSession> get values => _sessions.values;
  bool get hasUnsaved => values.any((s) => s.state != CardSaveState.saved);
  CardEditSession session(LifeCard card) =>
      _sessions.putIfAbsent(card.id, () => CardEditSession(card));
  void synchronize(List<LifeCard> cards) {
    final current = {for (final c in cards) c.id: c};
    for (final s in values) {
      final next = current[s.card.id];
      if (next == null) continue;
      s.card = next;
      if (s.state == CardSaveState.saved) {
        s.title = next.title;
        s.content = next.content;
        s.tags = next.tags.join(', ');
      }
    }
    notifyListeners();
    if (values.any((s) => s.state == CardSaveState.pending) && canSave()) {
      _schedule();
    }
  }

  void edit(CardEditSession s, {String? title, String? content, String? tags}) {
    s.title = title ?? s.title;
    s.content = content ?? s.content;
    s.tags = tags ?? s.tags;
    s.generation++;
    s.state = CardSaveState.pending;
    s.error = null;
    notifyListeners();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(flush()));
  }

  Future<void> flush() async {
    _timer?.cancel();
    if (_saving != null) {
      await _saving;
      if (!_disposed && hasUnsaved) await flush();
      return;
    }
    if (_disposed || !canSave()) return;
    final future = _drain();
    _saving = future;
    try {
      await future;
    } finally {
      _saving = null;
    }
  }

  Future<void> _drain() async {
    for (final s in List.of(values)) {
      if (_disposed || !canSave()) return;
      if (s.state == CardSaveState.saved) continue;
      final generation = s.generation;
      final snapshot = s.draft;
      s.state = CardSaveState.saving;
      s.error = null;
      notifyListeners();
      try {
        await save(s.card.id, snapshot);
        if (_disposed) return;
        s.state = generation == s.generation
            ? CardSaveState.saved
            : CardSaveState.pending;
      } on Object catch (e) {
        if (_disposed) return;
        s.state = CardSaveState.failed;
        s.error = e is FormatException ? e.message : '保存失败，请重试';
      }
      notifyListeners();
    }
    if (values.any((s) => s.state == CardSaveState.pending)) _schedule();
  }

  void clear() {
    _timer?.cancel();
    _sessions.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _sessions.clear();
    super.dispose();
  }
}
