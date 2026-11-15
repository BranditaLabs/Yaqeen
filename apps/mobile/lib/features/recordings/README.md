# features/recordings — «تلاواتي» (APP_SPEC §5.24 / §5.26 / §5.31.6, design doc §16)

Members record their **own voice** reciting verses they choose (≤ 30 s, up to 3 on a profile),
keep them private or share them with members / on the public card; others react and comment.
User content, not Yaqeen's religious content (CLAUDE.md rules 4/9 unaffected). Flag `recordings`,
off by default.

## Rules this code keeps

- **Nothing to analytics or ads** (rule 1): no product or ad event anywhere in this feature.
- **The on-device check is advisory.** The phone's Quran recogniser follows the words live and
  checks the whole take (`ClientCheck`), but the server never trusts it: private recordings are
  never verified, shared ones are re-verified by our own AI check. `clientScore` / `clientWords`
  travel only with a shared upload, as a reviewer's diagnostics.
- **One microphone session.** `VoiceRecorder` (core/platform) streams 16 kHz mono PCM; the same
  PCM feeds `RecitationEngine.startFromPcm` (the «تسميع» engine, model and aligner — no second
  engine) and, at stop, is encoded once by the platform's AAC encoder to contracts
  `RECORDING_FORMAT` (AAC-LC .m4a, mono, 16 kHz, 32 kbps). Nothing is written before the take ends.
- **Gentle.** Lapis is the only accent; never red, never «خطأ»; a word not heard gets a quiet ink
  underline. Gold is not used (achievement only). The destructive delete confirm is the one place
  the error colour appears.
- **Gates are the server's.** Sharing, reacting, commenting and reporting need an account, the 18+
  attestation and the community opt-in. The app asks for sign-in up front and answers
  `attestation_required` / `community_required` with the competitions' own join sheets
  (`share_gate.dart`). Every `RECORDING_ERROR_CODES` value has its copy (`failureText`).
- **Guests keep drafts on the phone.** A guest's take is a local draft (private), uploaded only when
  they tap «ارفعها» after signing in. A signed-in take saved offline is queued and uploaded by
  itself (`RecordingDrafts`, backoff 30 s → 15 min, jittered — the JSON Outbox cannot carry audio).
- **Wiped with the account.** `RecordingsRepository.wipedKeys` + `recordings/` files go on
  sign-out, session expiry and erasure (`SessionController._forgetProfile`).
- **No spinners.** Shaped skeletons (`RecordingsSkeleton`), `YqButton(loading:)`, `YqFadeSwap`.
- **One player.** Clips play through the app's single player (`ListenController.playClip`, like a
  reciter sample: the surah pauses and comes back paused; listening time is not counted).

## Layout

| File | What |
| --- | --- |
| `domain/recording_models.dart` | Contract mirrors (constants, enums, `Recording`, `PublicRecording`, comments, `RecitationMatch`). |
| `domain/verse_selection.dart` | `VerseSelection` (one surah, drag anchor/edge, handles, trim), `kRecitationWordsPerSecond` = 2.2, `RangeFit` (ok · near ≥ 80 % · over > 30 s · blocked > 120 %). |
| `domain/client_check.dart` | `ClientCheck.of(expected, heard)`: the `RecitationAligner` rules over the whole take → marks, coverage, flagged ayat, karaoke `RecordingWord`s, `ClientVerdict`. Generic (expected words in, aligned words out) so «تسميع» can reuse it. |
| `data/recordings_repository.dart` | The API (`/v1/me/recordings…`, members, reactions, comments, reports), cached list `recordings.mine.v1`, on-device timings `recordings.words.v1`, authed audio cache `recordings/cache/<id>.m4a`, `RecordingException`. |
| `data/recording_drafts.dart` | Takes not on the server yet (`recordings.drafts.v1`, `recordings/drafts/`): local / queued / failed. |
| `presentation/recordings_providers.dart` | `voiceRecorderProvider`, `myRecordingsProvider` (cache first, poll every 20 s while a check runs, optimistic move/comments), `memberRecordingsProvider`, `commentsProvider`, `recordingPlayerProvider`. |
| `presentation/recorder_controller.dart` | The recorder's state machine (ready · denied · 3-2-1 · recording · encoding · review · saving · saved), auto-stop at 30 s with a haptic, live follow or pacing guide, save outcomes. |
| `presentation/verse_picker_screen.dart` | `/profile/recordings/new`: the printed page (Madani fonts or the text page; ayah hit-testing added to both), swipe-to-select, lapis tint + passage rail, handles, estimate, «انتقل إلى». |
| `presentation/recorder_screen.dart` | `/profile/recordings/record`: the live stage and the review. |
| `presentation/verse_words_view.dart` | The chosen ayat word by word in the mushaf font (live highlight, karaoke `Karaoke.lookAt`). |
| `presentation/recordings_section.dart` | Profile «تلاواتي»: cards, drafts, menu, delete confirm. |
| `presentation/listener_sheet.dart` | Listener: karaoke, `YqPlayRing`, `ReactionsBar`, `CommentsSliver`, `CommentComposer`, report/block. |
| `presentation/member_recordings_sheet.dart` | A member's recordings from league / tournament / board rows (`CompetitorRow` taps). |
| `presentation/card_recordings.dart` | The card editor's «تلاواتي على البطاقة» and the preview block. |
| `presentation/share_gate.dart` | Sign-in up front; the join sheets after a gate refusal. |

Routes: `lib/app/routes/recordings_routes.dart`. Native: `AacEncoder.kt` (+ `openAppSettings` in
`MainActivity.kt`), the encoder in `AppDelegate.swift`; microphone strings in `Info.plist` and
`{ar,en}.lproj/InfoPlist.strings`; Android `RECORD_AUDIO` (already declared for «تسميع»).

## Not wired here

«تسميع» (recite) keeps its own controller; it could adopt `ClientCheck` for a whole-take grade,
and `VoiceRecorder` if it ever needs to keep the audio — left for that feature's owner.

## Tests

`test/features/recordings/`: domain, repository + drafts, recorder controller (fake microphone and
recogniser), screens (picker swipe, listener karaoke, reactions, comments, profile section,
gate, reduce motion). Shared contract vectors: `test/features/recitation_match_fixtures_test.dart`.
