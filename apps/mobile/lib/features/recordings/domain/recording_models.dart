import '../../community/domain/community_models.dart';

/// «تلاواتي» — members' own recorded recitations (design doc §16, APP_SPEC §5.24 / §5.31). Mirrors
/// `packages/contracts/src/recordings.ts`; shapes are checked against shared fixtures
/// (test/fixtures/recordings, also parsed by zod in services/api/test/recordings-fixtures.test.ts).
///
/// A recording is the owner's own voice reciting verses they chose — user content, not Yaqeen's
/// religious content. Private recordings never leave for the server's AI check; shared ones
/// (members/public) are verified there. Nothing here is ever sent to analytics or ad sinks.

/* ------------------------------------------------------------------ limits */

/// contracts `RECORDING_MAX_MS`: the recorder stops here.
const kRecordingMaxMs = 30000;

/// contracts `RECORDING_MAX_BYTES`.
const kRecordingMaxBytes = 200000;

/// contracts `PROFILE_RECORDINGS_MAX`.
const kProfileRecordingsMax = 3;

/// contracts `RECORDING_UPLOADS_PER_DAY` (uploads + share-verifications per Cairo day).
const kRecordingUploadsPerDay = 10;

/// contracts `COMMENT_MAX` / `COMMENT_MIN`.
const kCommentMax = 280;
const kCommentMin = 2;

/// contracts `RECORDING_FORMAT`: what the recorder must produce — AAC-LC in .m4a, mono, 16 kHz, ~32 kbps.
abstract final class RecordingFormat {
  static const container = 'm4a';
  static const codec = 'aac-lc';
  static const channels = 1;
  static const sampleRate = 16000;
  static const bitrate = 32000;
  static const mime = 'audio/mp4';
}

/// contracts `RECITATION_MATCH`: the server's verdict thresholds; the app's advisory pre-check
/// (`ClientCheck`) uses the same coverage lines.
abstract final class RecitationMatch {
  static const approveCoverage = 0.75;
  static const approveSpeech = 0.4;
  static const silenceSpeech = 0.15;
  static const rejectCoverage = 0.35;
  static const maxExtraRatio = 0.5;
  static const fuzzyMinLetters = 4;
}

/// contracts `COMMENTS_PAGE_SIZE`.
const kCommentsPageSize = 20;

/* ------------------------------------------------------------------- enums */

enum RecordingStatus {
  processing('processing'),
  privateReady('private_ready'),
  approved('approved'),
  needsReview('needs_review'),
  rejected('rejected'),
  removed('removed');

  const RecordingStatus(this.code);
  final String code;
  static RecordingStatus fromCode(Object? c) => values.firstWhere((v) => v.code == c, orElse: () => processing);
}

enum RejectReason {
  notMatching('not_matching'),
  unclear('unclear'),
  silence('silence'),
  tooLong('too_long'),
  removedByModerator('removed_by_moderator');

  const RejectReason(this.code);
  final String code;
  static RejectReason? fromCode(Object? c) => c == null ? null : values.where((v) => v.code == c).firstOrNull;
}

/// `public` = members + the owner's web card.
enum RecordingVisibility {
  private('private'),
  members('members'),
  public('public');

  const RecordingVisibility(this.code);
  final String code;
  static RecordingVisibility fromCode(Object? c) => values.firstWhere((v) => v.code == c, orElse: () => private);
}

/// contracts `REACTION_KINDS` (copy in the ARB files: «ما شاء الله» · «بارك الله فيك» · «أحسنت»).
enum ReactionKind {
  mashallah('mashallah'),
  barakallah('barakallah'),
  ahsant('ahsant');

  const ReactionKind(this.code);
  final String code;
  static ReactionKind? fromCode(Object? c) => c == null ? null : values.where((v) => v.code == c).firstOrNull;
}

enum RecordingReportReason {
  notRecitation('not_recitation'),
  inappropriate('inappropriate'),
  spam('spam'),
  other('other');

  const RecordingReportReason(this.code);
  final String code;
}

/// Stable server error codes (contracts `RECORDING_ERROR_CODES`) plus the client-side cases.
enum RecordingFailure {
  tooLong('recording_too_long'),
  tooLarge('recording_too_large'),
  badFormat('recording_bad_format'),
  invalidRange('recording_invalid_range'),
  limit('recordings_limit'),
  dailyLimit('recording_daily_limit'),
  notPublic('recording_not_public'),
  attestationRequired('attestation_required'),
  communityRequired('community_required'),
  communityBanned('community_banned'),
  accountRequired('account_required'),
  commentsOff('comments_off'),
  commentRejected('comment_rejected'),
  commentRateLimited('comment_rate_limited'),
  blocked('blocked'),

  /// Reacting to one's own recording (others react; the owner's would inflate the counts).
  ownRecording('own_recording'),
  rateLimited('rate_limited'),
  featureOff('feature_off'),
  notFound('not_found'),
  offline('offline'),
  unknown('unknown');

  const RecordingFailure(this.code);
  final String code;

  static Iterable<RecordingFailure> get serverCodes => values.where((f) => f != offline && f != unknown);

  static RecordingFailure fromCode(String code) {
    for (final f in serverCodes) {
      if (f.code == code) return f;
    }
    return unknown;
  }
}

/* ------------------------------------------------------------------ shapes */

int _int(Object? v) => (v as num).toInt();

/// A verified word for karaoke playback (`index` counts the ayah's words as `RecitationAligner.words` splits them).
class RecordingWord {
  const RecordingWord({required this.ayah, required this.index, required this.startMs, required this.endMs});
  final int ayah;
  final int index;
  final int startMs;
  final int endMs;

  factory RecordingWord.fromJson(Map<String, dynamic> j) =>
      RecordingWord(ayah: _int(j['ayah']), index: _int(j['index']), startMs: _int(j['startMs']), endMs: _int(j['endMs']));
  Map<String, dynamic> toJson() => {'ayah': ayah, 'index': index, 'startMs': startMs, 'endMs': endMs};

  static List<RecordingWord>? listFrom(Object? json) =>
      json is List ? [for (final e in json) RecordingWord.fromJson((e as Map).cast<String, dynamic>())] : null;
}

class ReactionCounts {
  const ReactionCounts({this.mashallah = 0, this.barakallah = 0, this.ahsant = 0});
  final int mashallah;
  final int barakallah;
  final int ahsant;

  int of(ReactionKind k) => switch (k) {
        ReactionKind.mashallah => mashallah,
        ReactionKind.barakallah => barakallah,
        ReactionKind.ahsant => ahsant,
      };
  int get total => mashallah + barakallah + ahsant;

  factory ReactionCounts.fromJson(Map<String, dynamic> j) =>
      ReactionCounts(mashallah: _int(j['mashallah']), barakallah: _int(j['barakallah']), ahsant: _int(j['ahsant']));
  Map<String, dynamic> toJson() => {'mashallah': mashallah, 'barakallah': barakallah, 'ahsant': ahsant};
}

/// The caller's own recording (`GET /v1/me/recordings`).
class Recording {
  const Recording({
    required this.id,
    required this.surah,
    required this.fromAyah,
    required this.toAyah,
    required this.durationMs,
    required this.status,
    required this.rejectReason,
    required this.visibility,
    required this.commentsOn,
    required this.position,
    required this.reactions,
    required this.myReaction,
    required this.commentCount,
    required this.createdAt,
    required this.audioPath,
    required this.words,
  });
  final String id;
  final int surah;
  final int fromAyah;
  final int toAyah;
  final int durationMs;
  final RecordingStatus status;
  final RejectReason? rejectReason;
  final RecordingVisibility visibility;
  final bool commentsOn;
  final int position;
  final ReactionCounts reactions;
  final ReactionKind? myReaction;
  final int commentCount;
  final DateTime createdAt;

  /// Authed API path, loaded with `ApiClient.getBytes`.
  final String audioPath;

  /// Null until verified.
  final List<RecordingWord>? words;

  bool get shared => visibility != RecordingVisibility.private;

  /// Waiting for the AI check (the app polls while one is on screen).
  bool get pending => status == RecordingStatus.processing;

  /// Can be shared with members (a rejected or removed recording cannot: `recording_not_public`).
  bool get shareable => status != RecordingStatus.rejected && status != RecordingStatus.removed;

  /// Members can hear it now.
  bool get live => shared && status == RecordingStatus.approved;

  Recording copyWith({
    RecordingStatus? status,
    RecordingVisibility? visibility,
    bool? commentsOn,
    int? position,
  }) =>
      Recording(
        id: id,
        surah: surah,
        fromAyah: fromAyah,
        toAyah: toAyah,
        durationMs: durationMs,
        status: status ?? this.status,
        rejectReason: rejectReason,
        visibility: visibility ?? this.visibility,
        commentsOn: commentsOn ?? this.commentsOn,
        position: position ?? this.position,
        reactions: reactions,
        myReaction: myReaction,
        commentCount: commentCount,
        createdAt: createdAt,
        audioPath: audioPath,
        words: words,
      );

  factory Recording.fromJson(Map<String, dynamic> j) => Recording(
        id: j['id'] as String,
        surah: _int(j['surah']),
        fromAyah: _int(j['fromAyah']),
        toAyah: _int(j['toAyah']),
        durationMs: _int(j['durationMs']),
        status: RecordingStatus.fromCode(j['status']),
        rejectReason: RejectReason.fromCode(j['rejectReason']),
        visibility: RecordingVisibility.fromCode(j['visibility']),
        commentsOn: j['commentsOn'] == true,
        position: _int(j['position']),
        reactions: ReactionCounts.fromJson((j['reactions'] as Map).cast<String, dynamic>()),
        myReaction: ReactionKind.fromCode(j['myReaction']),
        commentCount: _int(j['commentCount']),
        createdAt: DateTime.parse(j['createdAt'] as String),
        audioPath: j['audioPath'] as String,
        words: RecordingWord.listFrom(j['words']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'surah': surah,
        'fromAyah': fromAyah,
        'toAyah': toAyah,
        'durationMs': durationMs,
        'status': status.code,
        'rejectReason': rejectReason?.code,
        'visibility': visibility.code,
        'commentsOn': commentsOn,
        'position': position,
        'reactions': reactions.toJson(),
        'myReaction': myReaction?.code,
        'commentCount': commentCount,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'audioPath': audioPath,
        'words': words?.map((w) => w.toJson()).toList(),
      };
}

class MyRecordings {
  const MyRecordings({required this.items, required this.leftToday});
  final List<Recording> items;
  final int leftToday;

  static const empty = MyRecordings(items: [], leftToday: kRecordingUploadsPerDay);

  Map<String, dynamic> toJson() => {'items': [for (final r in items) r.toJson()], 'leftToday': leftToday};

  factory MyRecordings.fromJson(Map<String, dynamic> j) => MyRecordings(
        items: [for (final e in j['items'] as List) Recording.fromJson((e as Map).cast<String, dynamic>())],
        leftToday: _int(j['leftToday']),
      );
}

/// A shared, approved recording as members see it.
class PublicRecording {
  const PublicRecording({
    required this.id,
    required this.surah,
    required this.fromAyah,
    required this.toAyah,
    required this.durationMs,
    required this.visibility,
    required this.commentsOn,
    required this.position,
    required this.reactions,
    required this.myReaction,
    required this.commentCount,
    required this.createdAt,
    required this.audioPath,
    required this.words,
    required this.owner,
    required this.mine,
  });
  final String id;
  final int surah;
  final int fromAyah;
  final int toAyah;
  final int durationMs;
  final RecordingVisibility visibility;
  final bool commentsOn;
  final int position;
  final ReactionCounts reactions;
  final ReactionKind? myReaction;
  final int commentCount;
  final DateTime createdAt;
  final String audioPath;
  final List<RecordingWord>? words;

  /// The community's public competitor shape (`points`/`rank` null).
  final PublicCompetitor owner;
  final bool mine;

  PublicRecording withReactions(ReactionState r) => PublicRecording(
        id: id,
        surah: surah,
        fromAyah: fromAyah,
        toAyah: toAyah,
        durationMs: durationMs,
        visibility: visibility,
        commentsOn: commentsOn,
        position: position,
        reactions: r.reactions,
        myReaction: r.myReaction,
        commentCount: commentCount,
        createdAt: createdAt,
        audioPath: audioPath,
        words: words,
        owner: owner,
        mine: mine,
      );

  factory PublicRecording.fromJson(Map<String, dynamic> j) => PublicRecording(
        id: j['id'] as String,
        surah: _int(j['surah']),
        fromAyah: _int(j['fromAyah']),
        toAyah: _int(j['toAyah']),
        durationMs: _int(j['durationMs']),
        visibility: RecordingVisibility.fromCode(j['visibility']),
        commentsOn: j['commentsOn'] == true,
        position: _int(j['position']),
        reactions: ReactionCounts.fromJson((j['reactions'] as Map).cast<String, dynamic>()),
        myReaction: ReactionKind.fromCode(j['myReaction']),
        commentCount: _int(j['commentCount']),
        createdAt: DateTime.parse(j['createdAt'] as String),
        audioPath: j['audioPath'] as String,
        words: RecordingWord.listFrom(j['words']),
        owner: PublicCompetitor.fromJson((j['owner'] as Map).cast<String, dynamic>()),
        mine: j['mine'] == true,
      );
}

/// `GET /v1/community/members/:handle/recordings`.
class MemberRecordings {
  const MemberRecordings({required this.owner, required this.items});
  final PublicCompetitor owner;
  final List<PublicRecording> items;

  factory MemberRecordings.fromJson(Map<String, dynamic> j) => MemberRecordings(
        owner: PublicCompetitor.fromJson((j['owner'] as Map).cast<String, dynamic>()),
        items: [for (final e in j['items'] as List) PublicRecording.fromJson((e as Map).cast<String, dynamic>())],
      );
}

class ReactionState {
  const ReactionState({required this.reactions, required this.myReaction});
  final ReactionCounts reactions;
  final ReactionKind? myReaction;

  factory ReactionState.fromJson(Map<String, dynamic> j) => ReactionState(
        reactions: ReactionCounts.fromJson((j['reactions'] as Map).cast<String, dynamic>()),
        myReaction: ReactionKind.fromCode(j['myReaction']),
      );
}

class RecordingComment {
  const RecordingComment({
    required this.id,
    required this.author,
    required this.text,
    required this.createdAt,
    required this.mine,
    required this.canDelete,
  });
  final String id;
  final PublicCompetitor author;
  final String text;
  final DateTime createdAt;
  final bool mine;

  /// The author or the recording's owner.
  final bool canDelete;

  factory RecordingComment.fromJson(Map<String, dynamic> j) => RecordingComment(
        id: j['id'] as String,
        author: PublicCompetitor.fromJson((j['author'] as Map).cast<String, dynamic>()),
        text: j['text'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        mine: j['mine'] == true,
        canDelete: j['canDelete'] == true,
      );
}

/// `GET /v1/recordings/:id/comments?cursor=` — newest first.
class RecordingCommentsPage {
  const RecordingCommentsPage({required this.items, required this.nextCursor, required this.commentsOn});
  final List<RecordingComment> items;
  final String? nextCursor;
  final bool commentsOn;

  factory RecordingCommentsPage.fromJson(Map<String, dynamic> j) => RecordingCommentsPage(
        items: [for (final e in j['items'] as List) RecordingComment.fromJson((e as Map).cast<String, dynamic>())],
        nextCursor: j['nextCursor'] as String?,
        commentsOn: j['commentsOn'] == true,
      );
}
