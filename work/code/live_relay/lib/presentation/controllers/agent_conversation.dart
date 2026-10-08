import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/agent/conversation_runtime.dart';
import '../../core/ai/conversation_attachment.dart';
import '../../core/ai/conversation_state.dart';
import '../../core/ai/review_actions.dart';
import '../../core/domain/entities.dart';
import 'app_controller.dart';

export '../../core/ai/conversation_state.dart';

/// Flutter lifetime/notification adapter. No network, review, persistence or
/// token processing happens in the adapter; those belong to ConversationRuntime.
class AgentConversation extends ChangeNotifier {
  AgentConversation(this.controller)
    : runtime = ConversationRuntime(controller.conversationApplication) {
    _subscription = runtime.changes.listen((_) => notifyListeners());
  }
  final AppController controller;
  final ConversationRuntime runtime;
  late final StreamSubscription<void> _subscription;
  List<ConversationMessage> get messages => runtime.messages;
  List<ConversationAttachment> get attachments => runtime.attachments;
  Map<int, SensitiveFieldKind> get marks => runtime.marks;
  String get draft => runtime.draft;
  bool get working => runtime.working;
  String? get error => runtime.error;
  String get attachmentStamp => runtime.attachmentStamp;
  String get disclosureHistory => runtime.disclosureHistory;
  PreparedConversationTurn prepare(String text, List<SensitiveMark> marks) =>
      runtime.prepare(text, marks);
  Future<void> addFilePaths(Iterable<String> paths) =>
      runtime.addFilePaths(paths);
  void attachCard(LifeCard card) => runtime.attachCard(card);
  Future<void> attachOriginal(VaultBlob blob) => runtime.attachOriginal(blob);
  void replaceVideoFrames(
    ConversationAttachment attachment,
    List<({int milliseconds, Uint8List bytes})> frames,
  ) => runtime.replaceVideoFrames(attachment, frames);
  void setAttachmentAudio(ConversationAttachment attachment, Uint8List? wav) =>
      runtime.setAttachmentAudio(attachment, wav);
  void setAttachmentTranscript(
    ConversationAttachment attachment,
    String? text,
  ) => runtime.setAttachmentTranscript(attachment, text);
  void removeAttachment(ConversationAttachment attachment) =>
      runtime.removeAttachment(attachment);
  Future<void> saveOriginal(ConversationAttachment attachment) =>
      runtime.saveOriginal(attachment);
  void updateDraft(String text) => runtime.updateDraft(text);
  void mark(int line, SensitiveFieldKind? kind) => runtime.mark(line, kind);
  void editSuggestion(
    ConversationMessage message,
    int index, {
    String? title,
    String? content,
    CardKind? kind,
    bool? isInference,
    List<String>? tags,
  }) => runtime.editSuggestion(
    message,
    index,
    title: title,
    content: content,
    kind: kind,
    isInference: isInference,
    tags: tags,
  );
  void editActions(
    ConversationMessage message,
    int index,
    ReviewActions actions,
  ) => runtime.editActions(message, index, actions);
  void adoptProposal(ConversationMessage message, int index) =>
      runtime.adoptProposal(message, index);
  Future<void> load() => runtime.load();
  Future<void> flush() => runtime.flush();
  Future<void> finishPendingSave() => runtime.finishPendingSave();
  Future<bool> send(PreparedConversationTurn turn) => runtime.send(turn);
  Future<void> retrySave() => runtime.retrySave();
  Future<void> accept(ConversationMessage message) => runtime.accept(message);
  Future<void> newConversation() => runtime.newConversation();
  void clear() => runtime.clear();
  @override
  void dispose() {
    unawaited(_subscription.cancel());
    runtime.dispose();
    super.dispose();
  }
}
