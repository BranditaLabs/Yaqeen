import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/network/resumable_download.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/storage/local_store.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/core/widgets/yq_ring.dart';
import 'package:yaqeen/features/content/data/pack_repository.dart';
import 'package:yaqeen/features/content/domain/content_pack.dart';
import 'package:yaqeen/features/content/presentation/pack_row.dart';

import '../helpers/harness.dart';

/// Install reports half the bytes, then waits until the test lets it finish.
class _SlowPackRepository extends PackRepository {
  _SlowPackRepository()
      : super(
          api: ApiClient(
            baseUrl: 'https://api.test',
            tokens: TokenStore(MemoryKvStore()),
            client: MockClient((_) async => http.Response('[]', 200)),
          ),
          cache: MemoryKvStore(),
          store: LocalStore(MemoryKvStore()),
          root: () async => Directory.systemTemp,
          isUnmetered: () async => true,
        );

  final finish = Completer<void>();

  @override
  Future<Map<String, dynamic>> installed() async => {};

  @override
  Future<void> install(
    ContentPack pack, {
    CancelToken? cancel,
    bool allowMetered = false,
    void Function(int received, int? total)? onProgress,
  }) async {
    onProgress?.call(pack.sizeBytes ~/ 2, pack.sizeBytes);
    await finish.future;
  }
}

const _pack = ContentPack(
  id: 'tafsir-test',
  kind: PackKind.tafsir,
  titleAr: 'التفسير الميسر',
  titleEn: 'Al-Muyassar',
  version: 1,
  url: 'https://cdn.test/tafsir-test.json',
  sha256: '0000000000000000000000000000000000000000000000000000000000000000',
  sizeBytes: 4 * 1024 * 1024,
);

void main() {
  setUp(() => YqGlassConfig.enableBlur = false);

  testWidgets('a busy pack row shows a YqRing with its percentage, never a spinner', (tester) async {
    final semantics = tester.ensureSemantics();
    final repo = _SlowPackRepository();
    await tester.pumpWidget(
      harness(
        const Scaffold(body: PackRow(pack: _pack)),
        overrides: [packRepositoryProvider.overrideWithValue(repo)],
      ),
    );
    await tester.pump();
    expect(find.byType(YqRing), findsNothing);

    await tester.tap(find.byIcon(Icons.download_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(YqRing), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('جارٍ التحميل…'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(YqRing)),
      isSemantics(value: '50%'),
    );

    repo.finish.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(YqRing), findsNothing);
    semantics.dispose();
  });
}
