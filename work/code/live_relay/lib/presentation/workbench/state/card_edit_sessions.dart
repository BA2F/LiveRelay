import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../application/workbench/card_edit_runtime.dart';
import '../../../core/domain/entities.dart';
export '../../../application/workbench/card_edit_runtime.dart'
    show CardSaveState, CardEditSession;

class CardEditSessions extends ChangeNotifier {
  CardEditSessions({
    required Future<void> Function(String id, CardDraft draft) save,
    required bool Function() canSave,
    Duration debounce = const Duration(milliseconds: 650),
  }) : runtime = CardEditRuntime(
         save: save,
         canSave: canSave,
         debounce: debounce,
       ) {
    _subscription = runtime.changes.listen((_) => notifyListeners());
  }
  final CardEditRuntime runtime;
  late final StreamSubscription<void> _subscription;
  Iterable<CardEditSession> get values => runtime.values;
  bool get hasUnsaved => runtime.hasUnsaved;
  CardEditSession session(LifeCard card) => runtime.session(card);
  void synchronize(List<LifeCard> cards) => runtime.synchronize(cards);
  void edit(
    CardEditSession s, {
    String? title,
    String? content,
    String? tags,
  }) => runtime.edit(s, title: title, content: content, tags: tags);
  Future<void> flush() => runtime.flush();
  void clear() => runtime.clear();
  @override
  void dispose() {
    unawaited(_subscription.cancel());
    runtime.dispose();
    super.dispose();
  }
}
