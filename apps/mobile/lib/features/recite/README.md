# features/recite — «تسميع» and voice-aware «تحفيظ»

On-device recitation recognition (spec §5.12, §6.8; model card `docs/MODELS.md`). Everything heard
stays on the phone: audio lives in memory only, results are never uploaded, never in the cloud
backup, the export, the profile, competitions, admin, product analytics or ads. The only thing that
leaves a session is a hifz grade the user confirms (hifz state, as before).

## Layers

| Layer | Where | What |
| --- | --- | --- |
| Engine | `core/platform/recitation_engine.dart` | `RecitationEngine`: `listen({live})`, word-timed `RecognitionUpdate`s (committed / tentative), `level`, `startFromPcm`, `transcribeFile`, `liveSupport`, `modelInfo`. `UnavailableRecitationEngine` (default), `ScriptedRecitationEngine` (tests). |
| Runtime | `core/platform/asr/sherpa_recitation_engine.dart` | `record` → 16 kHz PCM → Silero VAD (this isolate) → Whisper int8 (sherpa-onnx, its own isolate). Set in `main.dart`. |
| Live loop | `core/platform/asr/live_transcriber.dart` | Pure Dart. Running segment: its last 12 s decoded every 1.2 s → *tentative* words (reveal only). Segment end (0.6 s pause, or 25 s): decoded whole → *committed* (judged). `live: false` = «سمّع ثم تحقّق». |
| Model | `core/platform/asr/asr_model*.dart` | Pinned manifest (name, bytes, SHA-256), download through the app-wide `DownloadQueue`, verify, delete. `ASR_MODEL_BASE_URL` picks our hosted copy. |
| Speed | `core/platform/asr/live_support.dart` | Real-time factor of a 3 s clip, once per model; > 0.8 → «سمّع ثم تحقّق». |
| Alignment | `domain/recitation.dart`, `domain/recitation_follower.dart` | `RecitationAligner.align` (whole transcript) and `RecitationFollower` (moving cursor: marks frozen up to the last match; isti'adha / Basmala skipped). |
| Attempt | `domain/recite_progress.dart` | Marks, help (first letter at 4 s, the word at 8 s = one «مساعدة»), per-ayah progress, flagged words, results. |
| UI | `presentation/` | `ReciteController` (phases idle → listening ⇄ paused → checking → done), `ReciteLayer` (pills on the printed page), strip (`quran/presentation/session/recite_strip.dart`), end card, download sheet, Settings row. |
| Hifz | `hifz/presentation/voice_rehearsal.dart` | «تكرار ×10» counts full recitations (≤ 1 note); «ردّد بعد القارئ» echo. |

## Rules

- Entry points show with the `recite` flag (the ship gate, remote) **and** a phone that runs the
  model (`reciteEntryProvider`). Before the download, the first entry opens the calm sheet; the
  hifz test offers it once by itself. Never on mobile data without the user's tap.
- Copy: «تنبيه», never «خطأ»; it checks the words, not tajweed — said in the sheet, the strip, the card.
- The microphone stops when the app leaves the foreground; «متابعة» resumes.
- Reduce motion: words appear without the rise, the glow jumps, no stagger.
