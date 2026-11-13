import 'dart:typed_data';

/// Where a profile photo comes from.
enum PhotoSource { camera, gallery }

/// A picked photo, already downscaled on the device (≤ 1024 px, JPEG quality 85, no metadata kept
/// by the picker). The server re-encodes it again and strips EXIF (APP_SPEC §5.24).
class PickedPhoto {
  const PickedPhoto({required this.bytes, this.mime = 'image/jpeg'});
  final Uint8List bytes;

  /// `image/jpeg` | `image/png` | `image/webp` (contracts `AVATAR_PHOTO.mimes`).
  final String mime;
}

/// Profile photo picker behind an interface (CLAUDE.md › mobile layering): [NoopPhotoPicker] by
/// default (tests, unsupported platforms), the `image_picker` one is set in `main.dart`.
abstract interface class PhotoPicker {
  /// Whether picking can be offered at all (hide «التقاط صورة» / «من الألبوم» when false).
  bool get available;

  /// The picked photo, or null when the user cancelled.
  Future<PickedPhoto?> pick(PhotoSource source);
}

class NoopPhotoPicker implements PhotoPicker {
  const NoopPhotoPicker();

  @override
  bool get available => false;

  @override
  Future<PickedPhoto?> pick(PhotoSource source) async => null;
}
