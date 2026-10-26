import '../../../core/network/api_client.dart';
import '../domain/public_card.dart';

/// The user's public card. Online by nature (it is a published page); the editor keeps the
/// draft in memory and saves explicitly.
class CardRepository {
  CardRepository(this.api);
  final ApiClient api;

  Future<PublicCard> mine() async => PublicCard.fromJson((await api.get('/v1/me/public-profile') as Map).cast<String, dynamic>());

  Future<PublicCard> save(PublicCard card) async =>
      PublicCard.fromJson((await api.put('/v1/me/public-profile', card.toUpdateJson()) as Map).cast<String, dynamic>());

  Future<bool> available(String handle) async =>
      ((await api.get('/v1/me/public-profile/available', query: {'handle': handle.trim().toLowerCase()}) as Map)['available'] as bool?) ?? false;

  /// What scanners see right now (level, streak, badges computed by the server).
  Future<CardView?> publicView(String handle) async {
    try {
      return CardView.fromJson((await api.get('/v1/public/profiles/${handle.trim().toLowerCase()}') as Map).cast<String, dynamic>());
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  /// The owner's private journey: level, lifetime points and every dated milestone.
  Future<MyJourney> journey() async => MyJourney.fromJson((await api.get('/v1/me/journey') as Map).cast<String, dynamic>());

  /// The owner's activated key medals / cards.
  Future<List<CardTag>> tags() async =>
      [for (final t in (await api.get('/v1/me/tags') as List)) CardTag.fromJson((t as Map).cast<String, dynamic>())];

  /// Activate a tag by its printed code. Throws [TagException] with what went wrong.
  Future<CardTag> claimTag(String raw) async {
    final code = normalizeTagCode(raw);
    if (!isTagCode(code)) throw const TagException(TagProblem.format);
    try {
      return CardTag.fromJson((await api.post('/v1/me/tags', {'code': code}) as Map).cast<String, dynamic>());
    } on ApiException catch (e) {
      throw TagException(switch (e.status) {
        404 => TagProblem.notFound,
        409 => TagProblem.limit,
        400 => TagProblem.format,
        _ => TagProblem.network,
      },);
    } on Exception {
      throw const TagException(TagProblem.network);
    }
  }

  /// Switch a lost tag off for good (support can re-issue it).
  Future<void> disableTag(String code) => api.delete('/v1/me/tags/$code');
}

class TagException implements Exception {
  const TagException(this.problem);
  final TagProblem problem;
}
