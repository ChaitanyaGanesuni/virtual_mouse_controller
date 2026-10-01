import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import 'tutor_api.dart';
import 'tutor_models.dart';

/// State of one chat with the AI teacher. The conversation is created on the
/// server only when the first question is sent.
class TutorChat extends ChangeNotifier {
  TutorChat(
    this._api, {
    this.pinnedVerseId,
    this._conversationId,
    this.mode = TutorMode.free,
    this.language = 'en',
  });

  final TutorApi _api;
  final String? pinnedVerseId;
  TutorMode mode;
  String language;
  String? _conversationId;

  final List<TutorMessage> messages = [];

  /// The question being answered (shown immediately, before the server replies).
  String? pending;
  bool busy = false;
  bool loading = false;
  ApiException? error;

  /// What to repeat when the user taps "Try again".
  Future<void> Function()? _retry;

  String? get conversationId => _conversationId;

  Future<void> load() async {
    final id = _conversationId;
    if (id == null) return;
    loading = true;
    notifyListeners();
    try {
      final (conv, msgs) = await _api.conversation(id);
      mode = conv.mode;
      language = conv.language;
      messages
        ..clear()
        ..addAll(msgs);
      error = null;
    } on ApiException catch (e) {
      error = e;
      _retry = load;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void setMode(TutorMode m) {
    mode = m;
    notifyListeners();
  }

  void setLanguage(String l) {
    language = l;
    notifyListeners();
  }

  Future<void> ask(String question) {
    final q = question.trim();
    if (q.isEmpty || busy) return Future.value();
    return _run(q, () async => _api.ask(await _conversation(), q, mode: mode, language: language));
  }

  /// Explain the pinned verse in the current mode (cached on the server, so
  /// usually instant and free).
  Future<void> explain({required String label}) {
    if (busy || pinnedVerseId == null) return Future.value();
    return _run(label, () async => _api.explain(await _conversation(), mode: mode, language: language));
  }

  Future<void> retry() => _retry?.call() ?? Future.value();

  void dismissError() {
    error = null;
    notifyListeners();
  }

  Future<String> _conversation() async => _conversationId ??= (await _api.createConversation(
    pinnedVerseId: pinnedVerseId,
    mode: mode,
    language: language,
  )).id;

  Future<void> _run(String shown, Future<Exchange> Function() call) async {
    busy = true;
    pending = shown;
    error = null;
    _retry = () => _run(shown, call);
    notifyListeners();
    try {
      final ex = await call();
      messages.addAll([ex.question, ex.answer]);
      pending = null;
      _retry = null;
    } on ApiException catch (e) {
      error = e;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
