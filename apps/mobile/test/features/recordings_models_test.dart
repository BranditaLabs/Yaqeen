import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/config/remote_config.dart';
import 'package:yaqeen/features/profile/domain/avatar.dart';
import 'package:yaqeen/features/recordings/domain/recording_models.dart';

/// Shared fixtures (also parsed by zod in services/api/test/recordings-fixtures.test.ts) and the
/// generated constants (tools/contracts/gen_recordings_fixtures.mjs) keep the Dart mirrors in step.
Map<String, dynamic> obj(String name) =>
    (jsonDecode(File('test/fixtures/recordings/$name').readAsStringSync()) as Map).cast<String, dynamic>();

void main() {
  final constants = obj('constants.json');

  group('fixtures parse', () {
    test('my_recordings.json', () {
      final m = MyRecordings.fromJson(obj('my_recordings.json'));
      expect(m.leftToday, 7);
      expect(m.items, hasLength(3));
      final a = m.items[0];
      expect(a.status, RecordingStatus.approved);
      expect(a.visibility, RecordingVisibility.public);
      expect(a.shared, isTrue);
      expect(a.reactions.of(ReactionKind.mashallah), 4);
      expect(a.reactions.total, 7);
      expect(a.words!.first.ayah, 1);
      expect(a.audioPath, '/v1/me/recordings/${a.id}/audio');
      expect(m.items[1].status, RecordingStatus.processing);
      expect(m.items[1].words, isNull);
      expect(m.items[2].rejectReason, RejectReason.notMatching);
      expect(m.items[2].shared, isFalse);
      // Round-trips (the device cache).
      expect(Recording.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>).toJson(), a.toJson());
    });

    test('member_recordings.json', () {
      final m = MemberRecordings.fromJson(obj('member_recordings.json'));
      expect(m.owner.handle, 'ahmed-4821');
      expect(m.owner.avatar, const PresetAvatar('m03'));
      expect(m.owner.points, isNull);
      expect(m.items.single.myReaction, ReactionKind.mashallah);
      expect(m.items.single.mine, isFalse);
    });

    test('comments.json', () {
      final p = RecordingCommentsPage.fromJson(obj('comments.json'));
      expect(p.commentsOn, isTrue);
      expect(p.nextCursor, isNotNull);
      final c = p.items.single;
      expect(c.author.name, isNull); // hidden by support → «عضو يقين»
      expect(c.mine && c.canDelete, isTrue);
    });

    test('reaction_state.json', () {
      final s = ReactionState.fromJson(obj('reaction_state.json'));
      expect(s.reactions.mashallah, 5);
      expect(s.myReaction, ReactionKind.mashallah);
    });
  });

  group('constants match the contracts', () {
    test('limits and format', () {
      expect(kRecordingMaxMs, constants['RECORDING_MAX_MS']);
      expect(kRecordingMaxBytes, constants['RECORDING_MAX_BYTES']);
      expect(kProfileRecordingsMax, constants['PROFILE_RECORDINGS_MAX']);
      expect(kRecordingUploadsPerDay, constants['RECORDING_UPLOADS_PER_DAY']);
      expect(kCommentMax, constants['COMMENT_MAX']);
      expect(kCommentMin, constants['COMMENT_MIN']);
      final f = (constants['RECORDING_FORMAT'] as Map).cast<String, dynamic>();
      expect(RecordingFormat.container, f['container']);
      expect(RecordingFormat.codec, f['codec']);
      expect(RecordingFormat.channels, f['channels']);
      expect(RecordingFormat.sampleRate, f['sampleRate']);
      expect(RecordingFormat.bitrate, f['bitrate']);
      expect(RecordingFormat.mime, (f['mimes'] as List).first);
    });

    test('enums', () {
      expect(RecordingStatus.values.map((v) => v.code), constants['RECORDING_STATUSES']);
      expect(RejectReason.values.map((v) => v.code), constants['REJECT_REASONS']);
      expect(RecordingVisibility.values.map((v) => v.code), constants['RECORDING_VISIBILITIES']);
      expect(ReactionKind.values.map((v) => v.code), constants['REACTION_KINDS']);
      expect(RecordingReportReason.values.map((v) => v.code), constants['RECORDING_REPORT_REASONS']);
      expect(RecordingFailure.serverCodes.map((v) => v.code), constants['RECORDING_ERROR_CODES']);
      expect(RecordingFailure.fromCode('recording_too_long'), RecordingFailure.tooLong);
      expect(RecordingFailure.fromCode('nope'), RecordingFailure.unknown);
    });

    test('the feature flag is off by default', () {
      expect(RemoteConfig.defaultFeatures[Flags.recordings], isFalse);
    });
  });
}
