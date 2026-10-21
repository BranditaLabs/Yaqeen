import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Small device capabilities used across features. Tests use [FakeDeviceServices].
abstract interface class DeviceServices {
  bool get isIOS;
  Future<String> appVersion();
  Future<void> keepAwake(bool on);
  Future<void> shareText(String text);
  Future<void> sharePng(Uint8List png, {required String fileName, String? text});
  Future<bool> openUrl(Uri url);

  /// iOS App Tracking Transparency prompt (only after `ads_measurement` is granted, spec §5.6).
  /// Denied keeps ad SDKs in limited mode; the consent itself stays as the user chose.
  Future<void> requestTracking();
}

class PluginDeviceServices implements DeviceServices {
  @override
  bool get isIOS => Platform.isIOS;

  @override
  Future<String> appVersion() async => (await PackageInfo.fromPlatform()).version;

  @override
  Future<void> keepAwake(bool on) => on ? WakelockPlus.enable() : WakelockPlus.disable();

  @override
  Future<void> shareText(String text) async => SharePlus.instance.share(ShareParams(text: text));

  @override
  Future<void> sharePng(Uint8List png, {required String fileName, String? text}) async => SharePlus.instance.share(
        ShareParams(files: [XFile.fromData(png, mimeType: 'image/png', name: fileName)], text: text),
      );

  @override
  Future<bool> openUrl(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);

  @override
  Future<void> requestTracking() async {
    if (!Platform.isIOS) return;
    if (await AppTrackingTransparency.trackingAuthorizationStatus == TrackingStatus.notDetermined) {
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
  }
}

/// Records calls; used as the default in tests.
class FakeDeviceServices implements DeviceServices {
  FakeDeviceServices({this.isIOS = false, this.version = '1.0.0'});

  @override
  final bool isIOS;
  final String version;
  bool awake = false;
  final List<String> shared = [];
  final List<Uri> opened = [];

  @override
  Future<String> appVersion() async => version;
  @override
  Future<void> keepAwake(bool on) async => awake = on;
  @override
  Future<void> shareText(String text) async => shared.add(text);
  @override
  Future<void> sharePng(Uint8List png, {required String fileName, String? text}) async => shared.add('png:$fileName');
  @override
  Future<bool> openUrl(Uri url) async {
    opened.add(url);
    return true;
  }

  int trackingRequests = 0;
  @override
  Future<void> requestTracking() async => trackingRequests++;
}
