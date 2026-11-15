import 'package:image_picker/image_picker.dart';

import 'photo_picker.dart';

/// `image_picker` (BSD-3, free). Android uses the system Photo Picker (no storage permission); iOS
/// uses PHPicker and the camera with the usage strings in `Info.plist` / `InfoPlist.strings`.
/// Downscaled on the device to `AVATAR_PHOTO.clientMaxPx` and re-encoded as JPEG without metadata.
class PluginPhotoPicker implements PhotoPicker {
  PluginPhotoPicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// contracts `AVATAR_PHOTO.clientMaxPx`.
  static const maxPx = 1024.0;

  @override
  bool get available => true;

  @override
  Future<PickedPhoto?> pick(PhotoSource source) async {
    final file = await _picker.pickImage(
      source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: maxPx,
      maxHeight: maxPx,
      imageQuality: 85,
      requestFullMetadata: false,
      preferredCameraDevice: CameraDevice.front,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    // With a quality below 100 image_picker re-encodes to JPEG; PNG/WebP pass through only when it
    // could not, so trust the magic bytes rather than the file name.
    return PickedPhoto(bytes: bytes, mime: _mime(bytes));
  }

  static String _mime(List<int> b) {
    if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
    if (b.length > 11 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }
}
