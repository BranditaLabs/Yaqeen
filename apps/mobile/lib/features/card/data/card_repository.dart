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
}
