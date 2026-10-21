import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/platform/location_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/city_repository.dart';

/// Detects the device location (when-in-use, asked only here) and names it after the nearest city.
/// Returns null when denied — the caller falls back to the city list, without nagging (spec §5.5).
Future<Place?> detectPlace(WidgetRef ref) async {
  final location = ref.read(locationServiceProvider);
  if (await location.requestPermission() != LocationStatus.granted) return null;
  final fix = await location.current();
  if (fix == null) return null;
  final nearest = await ref.read(cityRepositoryProvider).nearest(fix.lat, fix.lng);
  final tz = await location.deviceTimezone();
  final c = nearest?.$1;
  return Place(
    nameAr: c?.nameAr ?? c?.nameEn ?? '—',
    nameEn: c?.nameEn ?? '—',
    country: c?.country ?? '',
    lat: fix.lat,
    lng: fix.lng,
    timezone: tz.isNotEmpty ? tz : (c?.timezone ?? 'Africa/Cairo'),
    auto: true,
  );
}

/// «تغيير» → search the bundled city list or use the current location.
Future<Place?> showCityPicker(BuildContext context) => showYqSheet<Place>(context, builder: (_) => const _CityPicker());

class _CityPicker extends ConsumerStatefulWidget {
  const _CityPicker();

  @override
  ConsumerState<_CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends ConsumerState<_CityPicker> {
  final _query = TextEditingController();
  List<City> _results = const [];
  bool _locating = false;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final r = await ref.read(cityRepositoryProvider).search(q);
    if (mounted) setState(() => _results = r);
  }

  Future<void> _useLocation() async {
    setState(() => _locating = true);
    final place = await detectPlace(ref);
    if (!mounted) return;
    setState(() {
      _locating = false;
      _denied = place == null;
    });
    if (place != null) Navigator.of(context).pop(place);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final cities = ref.read(cityRepositoryProvider);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.locationTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: YqSpace.m),
          TextField(
            controller: _query,
            onChanged: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: t.locationSearch,
              prefixIcon: const Padding(padding: EdgeInsets.all(12), child: YqIcon(YqIcons.search, size: 20, tone: YqIconTone.idle)),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: t.clearSearch,
                      icon: const Icon(Icons.close_rounded, color: YqColors.muted),
                      onPressed: () {
                        _query.clear();
                        _search('');
                      },
                    ),
              filled: true,
              fillColor: const Color(0xCCFFFFFF),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(YqRadii.pill), borderSide: const BorderSide(color: YqColors.line)),
              enabledBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(YqRadii.pill), borderSide: const BorderSide(color: YqColors.line)),
            ),
          ),
          const SizedBox(height: YqSpace.m),
          YqButton.secondary(
            label: t.locationUseMine,
            loading: _locating,
            icon: const YqIcon(YqIcons.location, size: 18),
            onPressed: _useLocation,
          ),
          if (_denied) ...[
            const SizedBox(height: YqSpace.s),
            Text(t.locationDenied, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
          ],
          const SizedBox(height: YqSpace.m),
          Expanded(
            child: _results.isEmpty
                ? YqEmptyState(icon: YqIcons.location, title: t.locationNoResults)
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const YqDivider(),
                    itemBuilder: (context, i) {
                      final c = _results[i];
                      return YqListRow(
                        dense: true,
                        title: c.name(locale),
                        subtitle: cities.countryName(c.country, locale),
                        trailing: const SizedBox.shrink(),
                        onTap: () => Navigator.of(context).pop(c.toPlace()),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
