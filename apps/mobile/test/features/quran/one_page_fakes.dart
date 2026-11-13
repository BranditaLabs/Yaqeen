import 'dart:convert';
import 'dart:io';

import 'package:yaqeen/features/listen/domain/audio_models.dart';
import 'package:yaqeen/features/listen/presentation/listen_controller.dart';
import 'package:yaqeen/features/quran/domain/mushaf_layout.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';

/// The mushaf as the app loads it: the printed layout sets the page boundaries.
QuranData loadQuran() {
  final layout = MushafLayout.fromJson(jsonDecode(File('assets/quran/layout_v2.json').readAsStringSync()) as Map<String, dynamic>);
  return QuranData.fromJson(
    jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>,
    pageStarts: layout.starts,
  );
}

/// A player the test drives by hand: no engine, no files. [open] records where it was asked to start.
class FakeListen extends ListenController {
  FakeListen([this.initial = const ListenState()]);
  final ListenState initial;
  final opened = <AyahRef>[];
  final passages = <(int, int, int, int)>[];
  int pauses = 0;

  @override
  ListenState build() => initial;

  void set(ListenState s) => state = s;

  @override
  Future<void> open(int surah, {int? ayah, int? to, int? times, bool autoplay = true, Reciter? reciter, bool reload = false}) async {
    opened.add(AyahRef(surah, ayah ?? 1));
    if (ayah != null && to != null) passages.add((surah, ayah, to, times ?? 0));
    state = state.copyWith(
      status: ListenStatus.ready,
      surah: surah,
      ayah: ayah ?? 1,
      playing: autoplay,
      synced: true,
      repeat: to != null ? ListenRepeat.range : null,
      repeatTimes: times,
      rangeFrom: ayah,
      rangeTo: to,
      roundsDone: 0,
      loopEnded: false,
    );
  }

  @override
  Future<void> pause() async {
    pauses++;
    state = state.copyWith(playing: false);
  }

  @override
  Future<void> toggle() async => state = state.copyWith(playing: !state.playing);
}
