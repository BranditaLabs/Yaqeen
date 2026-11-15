/// What a profile picture is (contracts `Avatar`): the person's initial, one of the 16 bundled
/// presets (offline, no network), or a photo. A photo's [PhotoAvatar.url] is an absolute public URL
/// in other people's rows, and the caller's own authed path (`/v1/me/avatar/photo/256`) in
/// `MeProfile`, loaded with `ApiClient.getBytes`. [PhotoAvatar.localPath] is this device's copy.
sealed class AvatarRef {
  const AvatarRef();

  /// Unknown or malformed values read as the initial (a newer server, a corrupt cache).
  factory AvatarRef.fromJson(Object? json) {
    if (json is! Map) return const InitialAvatar();
    final j = json.cast<String, dynamic>();
    switch (j['kind']) {
      case 'preset':
        final id = j['id'];
        return id is String ? PresetAvatar(id) : const InitialAvatar();
      case 'photo':
        final id = j['id'], url = j['url'], small = j['smallUrl'], local = j['localPath'];
        if (id is! String || url is! String) return const InitialAvatar();
        return PhotoAvatar(id: id, url: url, smallUrl: small is String ? small : url, localPath: local is String ? local : null);
      default:
        return const InitialAvatar();
    }
  }

  /// `initial` | `preset` | `photo`.
  String get kind;
  Map<String, dynamic> toJson();
}

final class InitialAvatar extends AvatarRef {
  const InitialAvatar();

  @override
  String get kind => 'initial';

  @override
  Map<String, dynamic> toJson() => const {'kind': 'initial'};

  @override
  bool operator ==(Object other) => other is InitialAvatar;

  @override
  int get hashCode => 0;
}

final class PresetAvatar extends AvatarRef {
  const PresetAvatar(this.id);

  /// `m01`…`m08`, `f01`…`f08` (contracts `AVATAR_PRESETS`).
  final String id;

  String get asset => 'assets/avatars/$id.webp';

  @override
  String get kind => 'preset';

  @override
  Map<String, dynamic> toJson() => {'kind': 'preset', 'id': id};

  @override
  bool operator ==(Object other) => other is PresetAvatar && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

final class PhotoAvatar extends AvatarRef {
  const PhotoAvatar({required this.id, required this.url, required this.smallUrl, this.localPath});

  /// Picked on this device and not uploaded yet (the server gives a new id per upload).
  static const localId = 'local';

  /// A photo that exists only on this device so far.
  const PhotoAvatar.local(String path)
      : id = localId,
        url = '',
        smallUrl = '',
        localPath = path;

  final String id;
  final String url;
  final String smallUrl;

  /// This device's copy (`<appDocs>/profile/avatar_<id>.webp`, or the not-yet-uploaded jpg).
  final String? localPath;

  /// The caller's own photo: an API path that needs the session (never a public URL).
  bool get isAuthedPath => url.startsWith('/v1/me/');

  bool get isLocalOnly => id == localId;

  PhotoAvatar withLocalPath(String? path) => PhotoAvatar(id: id, url: url, smallUrl: smallUrl, localPath: path);

  @override
  String get kind => 'photo';

  @override
  Map<String, dynamic> toJson() =>
      {'kind': 'photo', 'id': id, 'url': url, 'smallUrl': smallUrl, if (localPath != null) 'localPath': localPath};

  @override
  bool operator ==(Object other) =>
      other is PhotoAvatar && other.id == id && other.url == url && other.smallUrl == smallUrl && other.localPath == localPath;

  @override
  int get hashCode => Object.hash(id, url, smallUrl, localPath);
}
