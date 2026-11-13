/// A value or a typed failure — for calls whose failures the UI shows inline (e.g. joining a
/// competition: offline, attestation required, name problems).
sealed class Result<T, E> {
  const Result();

  bool get isOk => this is Ok<T, E>;

  /// The value, or null on failure.
  T? get valueOrNull => switch (this) {
        Ok<T, E>(:final value) => value,
        Err<T, E>() => null,
      };

  /// The failure, or null on success.
  E? get errorOrNull => switch (this) {
        Ok<T, E>() => null,
        Err<T, E>(:final error) => error,
      };
}

final class Ok<T, E> extends Result<T, E> {
  const Ok(this.value);
  final T value;
}

final class Err<T, E> extends Result<T, E> {
  const Err(this.error);
  final E error;
}
