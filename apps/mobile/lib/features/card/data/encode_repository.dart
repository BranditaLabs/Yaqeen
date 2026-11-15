import '../../../core/network/api_client.dart';
import '../domain/medal_nfc.dart';

enum EncodeProblem { gone, notInBatch, network }

class EncodeException implements Exception {
  const EncodeException(this.problem);
  final EncodeProblem problem;
}

/// Staff encoding (`/v1/encode/:token`). The token is the capability: it is passed in on each call
/// and never stored.
class EncodeRepository {
  EncodeRepository(this.api);
  final ApiClient api;

  Future<EncodeSession> session(String token) async {
    if (!encodeTokenPattern.hasMatch(token)) throw const EncodeException(EncodeProblem.gone);
    try {
      return EncodeSession.fromJson((await api.get('/v1/encode/$token') as Map).cast<String, dynamic>());
    } on ApiException catch (e) {
      throw EncodeException(e.status == 404 ? EncodeProblem.gone : EncodeProblem.network);
    } on Exception {
      throw const EncodeException(EncodeProblem.network);
    }
  }

  /// Report a chip written + verified. Returns the batch's encoded count.
  Future<int> written(String token, {required String code, String? uid, required bool locked}) async {
    try {
      final res = await api.post('/v1/encode/$token/written', {'code': code, if (uid != null) 'uid': uid, 'locked': locked}) as Map;
      return (res['encoded'] as num?)?.toInt() ?? 0;
    } on ApiException catch (e) {
      throw EncodeException(
        switch (e.status) {
          404 => EncodeProblem.gone,
          409 => EncodeProblem.notInBatch,
          _ => EncodeProblem.network,
        },
      );
    } on Exception {
      throw const EncodeException(EncodeProblem.network);
    }
  }
}
