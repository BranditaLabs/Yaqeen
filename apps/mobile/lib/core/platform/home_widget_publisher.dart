import 'package:home_widget/home_widget.dart';

/// Hands the home-screen widgets (Android «NextPrayerWidget», iOS «YaqeenWidget») their data:
/// one JSON snapshot written to storage the widget can read (Android SharedPreferences, iOS App
/// Group). The widgets never call the network — everything they show is computed here, on device.
abstract interface class HomeWidgetPublisher {
  Future<void> publish(String json);
}

/// Tests and platforms without widgets.
class NoopHomeWidgetPublisher implements HomeWidgetPublisher {
  String? last;

  @override
  Future<void> publish(String json) async => last = json;
}

class PluginHomeWidgetPublisher implements HomeWidgetPublisher {
  /// Shared with the iOS widget extension (Runner + YaqeenWidget entitlements).
  static const appGroup = 'group.com.yaqinbrand.yaqeen';
  static const key = 'yq.widget.v1';
  static const androidName = 'NextPrayerWidget';
  static const iOSName = 'YaqeenWidget';

  bool _ready = false;

  @override
  Future<void> publish(String json) async {
    if (!_ready) {
      await HomeWidget.setAppGroupId(appGroup);
      _ready = true;
    }
    await HomeWidget.saveWidgetData<String>(key, json);
    await HomeWidget.updateWidget(androidName: androidName, iOSName: iOSName);
  }
}
