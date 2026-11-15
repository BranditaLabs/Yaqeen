import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/platform/audio_recorder.dart';
import '../../../core/platform/recitation_engine.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../../quran/domain/passage.dart';
import '../../quran/domain/quran_data.dart';
import '../../recite/domain/recitation.dart';
import '../../recite/domain/recitation_follower.dart';
import '../data/recording_drafts.dart';
import '../data/recordings_repository.dart';
import '../domain/client_check.dart';
import '../domain/recording_models.dart';
import 'recordings_providers.dart';

/// The recorder's steps (APP_SPEC §5.24): the microphone question, 3-2-1, recording (≤ 30 s,
/// live follow or pacing guide), the clip being written, review (play, re-record, who hears it),
/// saving, done.
enum RecorderPhase { ready, denied, countIn, recording, encoding, review, saving, saved }

/// How the verse view moves while recording.
enum FollowMode {
  /// The on-device recogniser lights words as they are recited.
  live,

  /// No live follow (model not downloaded, slow phone): the view scrolls with elapsed time,
  /// labelled «دليل الإيقاع». A slow phone still checks the whole clip after the take.
  pacing,
}

/// Where the take ended up after «حفظ».
enum SaveOutcome { uploaded, queued, local }

class RecorderState {
  const RecorderState({
    this.phase = RecorderPhase.ready,
    this.countIn = 3,
    this.elapsed = Duration.zero,
    this.mode = FollowMode.pacing,
    this.marks = const [],
    this.frontier = 0,
    this.autoStopped = false,
    this.clip,
    this.check,
    this.checking = false,
    this.visibility = RecordingVisibility.private,
    this.commentsOn = true,
    this.error,
    this.encodeFailed = false,
    this.tooShort = false,
    this.outcome,
    this.modelOffer = false,
  });

  final RecorderPhase phase;
  final int countIn;
  final Duration elapsed;
  final FollowMode mode;

  /// Live marks per expected word (null: not reached).
  final List<WordMark?> marks;

  /// The next word the voice has not reached (live follow).
  final int frontier;

  /// The 30-second limit stopped the take.
  final bool autoStopped;
  final RecordedClip? clip;

  /// The on-device check of the whole take (null without the model, or while [checking]).
  final ClientCheck? check;
  final bool checking;
  final RecordingVisibility visibility;
  final bool commentsOn;

  /// The save was refused (shown inline; gate codes open the share sheets).
  final RecordingFailure? error;
  final bool encodeFailed;

  /// Stopped before a single ayah could have been recited.
  final bool tooShort;
  final SaveOutcome? outcome;

  /// The model can be downloaded for live follow (shown as a quiet row before recording).
  final bool modelOffer;

  Duration get left {
    final l = const Duration(milliseconds: kRecordingMaxMs) - elapsed;
    return l.isNegative ? Duration.zero : l;
  }

  RecorderState copyWith({
    RecorderPhase? phase,
    int? countIn,
    Duration? elapsed,
    FollowMode? mode,
    List<WordMark?>? marks,
    int? frontier,
    bool? autoStopped,
    RecordedClip? Function()? clip,
    ClientCheck? Function()? check,
    bool? checking,
    RecordingVisibility? visibility,
    bool? commentsOn,
    RecordingFailure? Function()? error,
    bool? encodeFailed,
    bool? tooShort,
    SaveOutcome? Function()? outcome,
    bool? modelOffer,
  }) =>
      RecorderState(
        phase: phase ?? this.phase,
        countIn: countIn ?? this.countIn,
        elapsed: elapsed ?? this.elapsed,
        mode: mode ?? this.mode,
        marks: marks ?? this.marks,
        frontier: frontier ?? this.frontier,
        autoStopped: autoStopped ?? this.autoStopped,
        clip: clip == null ? this.clip : clip(),
        check: check == null ? this.check : check(),
        checking: checking ?? this.checking,
        visibility: visibility ?? this.visibility,
        commentsOn: commentsOn ?? this.commentsOn,
        error: error == null ? this.error : error(),
        encodeFailed: encodeFailed ?? this.encodeFailed,
        tooShort: tooShort ?? this.tooShort,
        outcome: outcome == null ? this.outcome : outcome(),
        modelOffer: modelOffer ?? this.modelOffer,
      );
}

/// Drives one recording of [passage] (family argument). The microphone opens only on «ابدأ»; one
/// session both writes the clip and feeds the on-device recogniser (`startFromPcm`), which lights
/// words through [RecitationFollower] — the same engine, model and aligner as «تسميع». The take
/// stops by itself at 30 s with a haptic. After the take, the recogniser's final pass over the whole
/// clip gives the advisory [ClientCheck] and the karaoke timings.
class RecorderController extends AutoDisposeFamilyNotifier<RecorderState, Passage> {
  /// One beat of the 3-2-1 count-in (shortened by tests).
  static Duration countInStep = const Duration(milliseconds: 800);
  static const tick = Duration(milliseconds: 100);

  /// How long the final on-device pass may take before review shows without it.
  static const checkTimeout = Duration(seconds: 25);

  /// Shorter than this cannot hold an ayah: «قصير جداً».
  static const minTake = Duration(milliseconds: 1500);

  VoiceTake? _take;
  Timer? _timer;
  Timer? _countdown;
  StreamSubscription<RecognitionUpdate>? _asr;
  RecognitionUpdate? _final;
  Completer<void>? _finalDone;
  RecitationFollower? _follower;
  List<(AyahRef, String)> _expected = const [];
  int _generation = 0;

  VoiceRecorder get _recorder => ref.read(voiceRecorderProvider);
  late RecitationEngine _engine;

  @override
  RecorderState build(Passage arg) {
    // Kept for the controller's life: onDispose may not read providers.
    final engine = _engine = ref.watch(recitationEngineProvider);
    ref.onDispose(() {
      _generation++;
      _timer?.cancel();
      _countdown?.cancel();
      _asr?.cancel();
      final take = _take;
      _take = null;
      if (take != null) take.cancel().ignore();
      engine.stop().ignore();
    });
    Future.microtask(_prepare);
    return const RecorderState();
  }

  /// The expected words (for the live view) and whether the model could follow.
  Future<void> _prepare() async {
    final q = await ref.read(quranDataProvider.future);
    // Only a range inside its surah is read (the screen sends anything else back to the picker).
    _expected = checkedPassage(q, arg) == arg ? arg.expected(q) : const [];
    _follower = RecitationFollower(ExpectedWord.of(_expected));
    final available = await _engine.isAvailable();
    final supported = !available && await _engine.isSupported();
    state = state.copyWith(marks: List<WordMark?>.filled(_follower!.words.length, null), modelOffer: supported);
  }

  List<ExpectedWord> get words => _follower?.words ?? const [];

  /// «ابدأ التسجيل»: asks for the microphone (explained on screen first), then 3-2-1.
  Future<void> begin() async {
    if (state.phase != RecorderPhase.ready && state.phase != RecorderPhase.review && state.phase != RecorderPhase.denied) return;
    await ref.read(recordingPlayerProvider.notifier).stop('take');
    if (await _recorder.permission() != MicPermission.granted) {
      state = state.copyWith(phase: RecorderPhase.denied);
      return;
    }
    if (_follower == null) await _prepare();
    final gen = ++_generation;
    _follower = RecitationFollower(ExpectedWord.of(_expected));
    state = RecorderState(
      phase: RecorderPhase.countIn,
      marks: List<WordMark?>.filled(words.length, null),
      visibility: state.visibility,
      commentsOn: state.commentsOn,
      modelOffer: state.modelOffer,
    );
    for (var n = 3; n >= 1; n--) {
      if (gen != _generation) return;
      state = state.copyWith(countIn: n);
      HapticFeedback.selectionClick().ignore();
      final step = Completer<void>();
      _countdown = Timer(countInStep, step.complete);
      await step.future;
    }
    if (gen != _generation) return;
    await _startTake(gen);
  }

  Future<void> _startTake(int gen) async {
    final VoiceTake take;
    try {
      take = await _recorder.start();
    } on MicDeniedException {
      state = state.copyWith(phase: RecorderPhase.denied);
      return;
    }
    if (gen != _generation) {
      take.cancel().ignore();
      return;
    }
    _take = take;
    _final = null;
    _finalDone = Completer<void>();
    var mode = FollowMode.pacing;
    var asr = false;
    if (await _engine.isAvailable()) {
      final support = await _engine.liveSupport();
      mode = support.live ? FollowMode.live : FollowMode.pacing;
      asr = true;
      _asr = _engine.startFromPcm(take.pcm, live: support.live).listen(
            _onUpdate,
            onError: (Object _) => _endAsr(),
            onDone: _endAsr,
          );
    }
    if (!asr) {
      // Nothing listens to the samples: drain them so the take never buffers.
      take.pcm.listen((_) {}).onError((Object _) {});
      _endAsr();
    }
    state = state.copyWith(phase: RecorderPhase.recording, mode: mode, elapsed: Duration.zero);
    _timer = Timer.periodic(tick, (_) {
      final e = take.elapsed;
      if (e.inMilliseconds >= kRecordingMaxMs) {
        state = state.copyWith(elapsed: const Duration(milliseconds: kRecordingMaxMs));
        HapticFeedback.mediumImpact().ignore();
        stop(auto: true).ignore();
      } else if (e != state.elapsed) {
        state = state.copyWith(elapsed: e);
      }
    });
  }

  void _endAsr() {
    final d = _finalDone;
    if (d != null && !d.isCompleted) d.complete();
  }

  void _onUpdate(RecognitionUpdate u) {
    // The latest update holds everything heard so far; the final one (after the clip's PCM closed)
    // is the whole take.
    _final = u;
    final f = _follower;
    if (f == null || state.phase != RecorderPhase.recording) return;
    final changed = f.update([for (final w in u.committed) w.text], [for (final w in u.tentative) w.text]);
    if (changed) state = state.copyWith(marks: List.of(f.marks), frontier: f.frontier);
  }

  /// Level 0…1 of the open microphone (for `YqLiveLevel`).
  Stream<double> get level => _take?.level ?? const Stream.empty();

  /// Stops the take (a tap, or the limit) and writes the clip; review follows.
  Future<void> stop({bool auto = false}) async {
    final take = _take;
    if (take == null || state.phase != RecorderPhase.recording) return;
    _take = null;
    _timer?.cancel();
    final elapsed = take.elapsed;
    state = state.copyWith(phase: RecorderPhase.encoding, autoStopped: auto, checking: true);
    if (elapsed < minTake) {
      await take.cancel();
      _asr?.cancel();
      await _engine.stop();
      state = state.copyWith(phase: RecorderPhase.ready, tooShort: true, checking: false);
      return;
    }
    final RecordedClip clip;
    try {
      clip = await take.stop(await _takePath());
    } on Object {
      _asr?.cancel();
      await _engine.stop();
      state = state.copyWith(phase: RecorderPhase.ready, encodeFailed: true, checking: false);
      return;
    }
    state = state.copyWith(phase: RecorderPhase.review, clip: () => clip);
    // The recogniser finishes the whole clip once its PCM stream closed.
    final done = _finalDone;
    if (done != null) await done.future.timeout(checkTimeout, onTimeout: () {});
    _asr?.cancel();
    _asr = null;
    final heard = _final;
    final check = heard == null ? null : ClientCheck.of(_expected, heard.words);
    if (state.clip == clip) state = state.copyWith(check: () => check, checking: false);
  }

  Future<String> _takePath() async {
    final dir = await ref.read(recordingsRepositoryProvider).draftsDir();
    return '${dir.path}${Platform.pathSeparator}${RecordingDrafts.newId()}.m4a';
  }

  /// «أعد التسجيل»: drops the clip and starts again.
  Future<void> again() async {
    await discard(keepScreen: true);
    await begin();
  }

  /// Drops the take (leaving the screen, or before recording again).
  Future<void> discard({bool keepScreen = false}) async {
    _generation++;
    _timer?.cancel();
    _countdown?.cancel();
    _asr?.cancel();
    final take = _take;
    _take = null;
    if (take != null) await take.cancel();
    await ref.read(recordingPlayerProvider.notifier).stop('take');
    final clip = state.clip;
    if (clip != null) _deleteFile(clip.path);
    if (keepScreen) state = state.copyWith(phase: RecorderPhase.ready, clip: () => null, check: () => null, autoStopped: false);
  }

  void _deleteFile(String path) {
    final f = File(path);
    if (f.existsSync()) {
      try {
        f.deleteSync();
      } on FileSystemException {
        // best effort
      }
    }
  }

  void setVisibility(RecordingVisibility v) => state = state.copyWith(visibility: v, error: () => null);
  void setComments(bool on) => state = state.copyWith(commentsOn: on);

  /// «حفظ»: a guest keeps the take on this phone; an account uploads it now (offline → queued for
  /// later, quietly). A refusal stays on the review with its message.
  Future<SaveOutcome?> save() async {
    final clip = state.clip;
    if (clip == null || state.phase != RecorderPhase.review) return null;
    state = state.copyWith(phase: RecorderPhase.saving, error: () => null);
    final check = state.check;
    final draft = RecordingDraft(
      id: RecordingDrafts.newId(),
      surah: arg.surah,
      fromAyah: arg.from,
      toAyah: arg.to,
      durationMs: clip.duration.inMilliseconds.clamp(1, kRecordingMaxMs + 250),
      path: clip.path,
      visibility: state.visibility,
      commentsOn: state.commentsOn,
      createdAt: ref.read(clockProvider)(),
      state: DraftState.local,
      clientScore: check?.score,
      clientWords: check?.words,
    );
    final drafts = ref.read(recordingDraftsProvider);
    await ref.read(recordingPlayerProvider.notifier).stop('take');
    if (!ref.read(sessionProvider).canEarnPoints) {
      await drafts.add(draft.copyWith(visibility: RecordingVisibility.private));
      return _saved(SaveOutcome.local);
    }
    final repo = ref.read(recordingsRepositoryProvider);
    try {
      final r = await repo.upload(
        surah: draft.surah,
        fromAyah: draft.fromAyah,
        toAyah: draft.toAyah,
        durationMs: draft.durationMs,
        audio: await File(clip.path).readAsBytes(),
        visibility: draft.visibility,
        commentsOn: draft.commentsOn,
        clientScore: draft.clientScore,
        clientWords: draft.clientWords,
      );
      if (check != null) await repo.saveLocalWords(r.id, check.words);
      _deleteFile(clip.path);
      if (ref.exists(myRecordingsProvider)) ref.read(myRecordingsProvider.notifier).added(r);
      return _saved(SaveOutcome.uploaded);
    } on RecordingException catch (e) {
      if (e.transient) {
        await drafts.add(draft.copyWith(state: DraftState.queued));
        return _saved(SaveOutcome.queued);
      }
      state = state.copyWith(phase: RecorderPhase.review, error: () => e.failure);
      return null;
    }
  }

  SaveOutcome _saved(SaveOutcome o) {
    state = state.copyWith(phase: RecorderPhase.saved, outcome: () => o, clip: () => null);
    return o;
  }
}

final recorderProvider = NotifierProvider.autoDispose.family<RecorderController, RecorderState, Passage>(RecorderController.new);
