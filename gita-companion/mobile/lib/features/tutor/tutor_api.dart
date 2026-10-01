import '../../core/api/api_client.dart';
import 'tutor_models.dart';

typedef Exchange = ({TutorMessage question, TutorMessage answer});

/// Typed wrapper over the server's /v1/tutor endpoints.
class TutorApi {
  TutorApi(this._client);

  final ApiClient _client;

  bool get isConfigured => _client.isConfigured;

  Future<TutorStatus> status() async =>
      TutorStatus.fromJson(await _client.get('/v1/tutor/status') as Map<String, dynamic>);

  Future<Conversation> createConversation({
    String? pinnedVerseId,
    required TutorMode mode,
    required String language,
  }) async => Conversation.fromJson(
    await _client.post('/v1/tutor/conversations', {
      'pinned_verse_id': ?pinnedVerseId,
      'mode': mode.wire,
      'language': language,
    }) as Map<String, dynamic>,
  );

  Future<List<Conversation>> conversations() async => [
    for (final c in await _client.get('/v1/tutor/conversations') as List)
      Conversation.fromJson(c as Map<String, dynamic>),
  ];

  Future<(Conversation, List<TutorMessage>)> conversation(String id) async {
    final j = await _client.get('/v1/tutor/conversations/$id') as Map<String, dynamic>;
    return (
      Conversation.fromJson(j),
      [for (final m in j['messages'] as List) TutorMessage.fromJson(m as Map<String, dynamic>)],
    );
  }

  Future<void> deleteConversation(String id) => _client.delete('/v1/tutor/conversations/$id');

  Future<Exchange> ask(
    String conversationId,
    String question, {
    required TutorMode mode,
    required String language,
  }) async => _exchange(
    await _client.post('/v1/tutor/conversations/$conversationId/messages', {
      'question': question,
      'mode': mode.wire,
      'language': language,
    }),
  );

  Future<Exchange> explain(
    String conversationId, {
    required TutorMode mode,
    required String language,
  }) async => _exchange(
    await _client.post('/v1/tutor/conversations/$conversationId/explain', {
      'mode': mode == TutorMode.free ? TutorMode.simple.wire : mode.wire,
      'language': language,
    }),
  );

  Future<void> deleteAllData() => _client.deleteAccount();

  Exchange _exchange(Object? json) {
    final j = json as Map<String, dynamic>;
    return (
      question: TutorMessage.fromJson(j['question'] as Map<String, dynamic>),
      answer: TutorMessage.fromJson(j['answer'] as Map<String, dynamic>),
    );
  }
}
