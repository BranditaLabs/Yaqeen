import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/widgets/controls.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/storage/local_store.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/backup/data/backup_adapters.dart';
import 'package:yaqeen/features/backup/data/backup_engine.dart';
import 'package:yaqeen/features/backup/data/backup_repository.dart';
import 'package:yaqeen/features/backup/domain/backup_merge.dart';
import 'package:yaqeen/features/backup/presentation/backup_sync.dart';
import 'package:yaqeen/features/backup/presentation/backup_widgets.dart';
import 'package:yaqeen/features/listen/data/listen_store.dart';
import 'package:yaqeen/features/onboarding/data/auth_repository.dart';
import 'package:yaqeen/features/onboarding/data/consent_repository.dart';
import 'package:yaqeen/features/quran/data/reading_repository.dart';
import 'package:yaqeen/features/quran/domain/annotations.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/ramadan/data/ramadan_repository.dart';
import 'package:yaqeen/l10n/gen/app_localizations.dart';

import '../helpers/harness.dart';

final _t0 = DateTime.utc(2026, 10, 20, 8);
final _t1 = DateTime.utc(2026, 10, 20, 9);

/// The API's /v1/me/backup and /v1/me/consents, in memory, with its version rule.
class FakeBackupServer {
  final docs = <String, Map<String, dynamic>>{};
  final calls = <String>[];
  bool consent = false;
  bool offline = false;
  DateTime clock = DateTime.utc(2026, 10, 20, 10);

  static http.Response _json(Object? body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

  http.Client client() => MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (offline) throw http.ClientException('offline');
        final path = req.url.path;
        if (path == '/v1/me/consents') {
          if (req.method == 'GET') return _json({'cloud_backup': consent});
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          if (b['kind'] == 'cloud_backup') {
            consent = b['granted'] == true;
            if (!consent) docs.clear();
          }
          return _json({'ok': true});
        }
        if (!consent) {
          return _json(
            {
              'error': {'code': 'backup_off'},
            },
            403,
          );
        }
        if (path == '/v1/me/backup') {
          return _json({
            'kinds': [
              for (final e in docs.entries) {'kind': e.key, 'version': e.value['version'], 'updatedAt': e.value['updatedAt']},
            ],
          });
        }
        final kind = path.split('/').last;
        if (req.method == 'GET') {
          return docs[kind] == null
              ? _json(
                  {
                    'error': {'code': 'not_found'},
                  },
                  404,
                )
              : _json({'kind': kind, ...docs[kind]!});
        }
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final have = (docs[kind]?['version'] as int?) ?? 0;
        if (body['baseVersion'] != have) {
          return _json(
            {
              'error': {
                'code': 'backup_conflict',
                'details': have == 0 ? null : {'kind': kind, ...docs[kind]!},
              },
            },
            409,
          );
        }
        docs[kind] = {'version': have + 1, 'updatedAt': clock.toIso8601String(), 'data': body['data']};
        return _json({'version': have + 1, 'updatedAt': clock.toIso8601String()});
      });

  Map<String, dynamic>? data(String kind) => (docs[kind]?['data'] as Map?)?.cast<String, dynamic>();
}

/// One phone: its own stores and session, the shared fake server.
class Phone {
  Phone(this.server, {bool guest = false, Duration debounce = const Duration(milliseconds: 20)}) : kv = ObservableKvStore(MemoryKvStore()) {
    container = ProviderContainer(
      overrides: [
        kvStoreProvider.overrideWithValue(kv),
        secureStoreProvider.overrideWithValue(MemoryKvStore()),
        apiClientProvider.overrideWithValue(ApiClient(baseUrl: 'http://api', tokens: TokenStore(MemoryKvStore()), client: server.client())),
        initialSessionProvider.overrideWithValue(
          guest
              ? const Session(provider: SignInProvider.guest, userId: 'g1')
              : const Session(provider: SignInProvider.google, userId: 'u1', displayName: 'A'),
        ),
        backupDebounceProvider.overrideWithValue((_) => debounce),
      ],
    );
  }

  final FakeBackupServer server;
  final ObservableKvStore kv;
  late final ProviderContainer container;

  ReadingRepository get reading => container.read(readingRepositoryProvider);
  BackupSync get sync => container.read(backupSyncProvider.notifier);
  BackupStatus get status => container.read(backupSyncProvider);
  BackupEngine get engine => container.read(backupEngineProvider);
  ConsentRepository get consents => container.read(consentRepositoryProvider);
}

Future<void> settle([int ms = 120]) => Future<void>.delayed(Duration(milliseconds: ms));

/// Waits (up to 5 s) for a debounced upload to land — the suite runs files in parallel.
Future<void> eventually(bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue);
}

Set<Object?> serverPages(FakeBackupServer s) =>
    {for (final m in (s.data('quran_reading')?['bookmarks'] as List?) ?? const []) (m as Map)['p']};

Bookmark page(int p, DateTime at) => Bookmark(kind: BookmarkKind.page, page: p, at: at);

void main() {
  group('merge rules', () {
    test('keyed: union, a side that changed wins, deletions stay deleted, both changed → newer', () {
      DateTime? at(Map<String, Object?> v) => DateTime.parse(v['at']! as String);
      final base = {
        'a': {'at': '2026-01-01T00:00:00Z', 'c': 'gold'},
        'b': {'at': '2026-01-01T00:00:00Z'},
        'c': {'at': '2026-01-01T00:00:00Z', 'c': 'gold'},
      };
      final local = {
        'a': {'at': '2026-01-03T00:00:00Z', 'c': 'blue'}, // both edited, local newer
        // 'b' deleted here
        'c': {'at': '2026-01-01T00:00:00Z', 'c': 'gold'},
        'n': {'at': '2026-01-05T00:00:00Z'}, // new here
      };
      final remote = {
        'a': {'at': '2026-01-02T00:00:00Z', 'c': 'green'},
        'b': {'at': '2026-01-01T00:00:00Z'},
        'c': {'at': '2026-01-04T00:00:00Z', 'c': 'rose'}, // edited there only
        'r': {'at': '2026-01-05T00:00:00Z'}, // new there
      };
      final out = BackupMerge.keyed<Map<String, Object?>>(local, remote, base, at: at);
      expect(out.keys.toSet(), {'a', 'c', 'n', 'r'});
      expect(out['a']!['c'], 'blue');
      expect(out['c']!['c'], 'rose');
      // Without a base (a new phone) nothing is treated as deleted.
      expect(BackupMerge.keyed<Map<String, Object?>>(local, remote, null, at: at).keys.toSet(), {'a', 'b', 'c', 'n', 'r'});
    });

    test('set, last-writer-wins, per-day max and the later day', () {
      expect(BackupMerge.set({'1', '2', '9'}, {'1', '3'}, {'1', '2', '3'}), {'1', '9'});
      expect(BackupMerge.lww(5, 7, hasBase: true, base: 5, localAt: _t1, remoteAt: _t0), 7, reason: 'only remote changed');
      expect(BackupMerge.lww(6, 7, hasBase: true, base: 5, localAt: _t1, remoteAt: _t0), 6, reason: 'both changed, local later');
      expect(BackupMerge.lww(6, 7, hasBase: false, localAt: _t0, remoteAt: _t1), 7);
      expect(
        BackupMerge.dailyMax({
          'd1': [3, 60],
          'd2': [1, 10],
        }, {
          'd1': [2, 90],
          'd3': [4, 4],
        }),
        {
          'd1': [3, 90],
          'd2': [1, 10],
          'd3': [4, 4],
        },
      );
      expect(
        BackupMerge.dailyMax(
          {
            'a': [1],
            'b': [1],
            'c': [1],
          },
          {},
          keepDays: 2,
        ).keys,
        ['b', 'c'],
      );
      Map<String, dynamic> same(Map<String, dynamic> l, Map<String, dynamic> r) => {'date': l['date'], 'n': 'both'};
      expect(BackupMerge.day({'date': '2026-10-19'}, {'date': '2026-10-20'}, same), {'date': '2026-10-20'});
      expect(BackupMerge.day({'date': '2026-10-20'}, {'date': '2026-10-20'}, same)!['n'], 'both');
      expect(BackupMerge.countsMax({'a': 3, 'b': 1}, {'a': 2, 'c': 5}), {'a': 3, 'b': 1, 'c': 5});
      expect(sameJson({'a': 1, 'b': 2}, {'b': 2, 'a': 1}), isTrue);
    });
  });

  test('BackupDocument parses the contracts shape and refuses unknown kinds', () {
    final d = BackupDocument.tryParse({
      'kind': 'quran_notes',
      'version': 3,
      'updatedAt': '2026-10-20T10:00:00.000Z',
      'data': {'notes': []},
    });
    expect(d!.kind, BackupKind.quranNotes);
    expect(d.version, 3);
    expect(d.updatedAt, DateTime.utc(2026, 10, 20, 10));
    expect(BackupDocument.tryParse({'kind': 'consents', 'version': 1, 'data': {}}), isNull);
    expect(
      BackupDocument.tryParse({
        'kind': 'tasbeeh',
        'version': 1,
        'data': [1],
      }),
      isNull,
    );
    expect(
      BackupKind.values.map((k) => k.wire),
      ['quran_reading', 'quran_notes', 'khatma', 'hifz', 'azkar', 'listen', 'routine', 'ramadan', 'tasbeeh'],
    );
  });

  group('adapters round-trip and merge per kind', () {
    late MemoryKvStore kv;
    late LocalStore store;
    setUp(() {
      kv = MemoryKvStore();
      store = LocalStore(kv);
    });

    Future<void> roundTrip(BackupAdapter Function(MemoryKvStore kv) make, Future<void> Function(MemoryKvStore kv) fill) async {
      final a = MemoryKvStore();
      await fill(a);
      final doc = await make(a).export();
      final b = MemoryKvStore();
      await make(b).import(jsonCopy(doc));
      expect(canonicalJson(await make(b).export()), canonicalJson(doc));
    }

    test('quran reading: last page, bookmarks, wird and stats', () async {
      await roundTrip((kv) => QuranReadingBackup(ReadingRepository(LocalStore(kv))), (kv) async {
        final r = ReadingRepository(LocalStore(kv));
        await r.saveLastRead(255, 2, _t0);
        await r.toggle(page(10, _t0));
        await r.addStats('2026-10-20', pages: 3, seconds: 120);
      });
      final a = QuranReadingBackup(ReadingRepository(store));
      final merged = a.merge(
        {
          'lastRead': {'page': 5, 'surah': 1, 'at': '2026-10-20T08:00:00.000Z'},
          'bookmarks': [page(1, _t0).toJson()],
          'wird': {
            'date': '2026-10-20',
            'pages': [1, 2],
            'ticked': false,
          },
          'stats': {
            '2026-10-20': [2, 100],
          },
        },
        {
          'lastRead': {'page': 9, 'surah': 2, 'at': '2026-10-20T09:00:00.000Z'},
          'bookmarks': [page(2, _t1).toJson()],
          'wird': {
            'date': '2026-10-20',
            'pages': [2, 3],
            'ticked': true,
          },
          'stats': {
            '2026-10-20': [3, 50],
            '2026-10-19': [1, 1],
          },
        },
        localAt: _t0,
        remoteAt: _t1,
      );
      expect((merged['lastRead'] as Map)['page'], 9);
      expect([for (final b in merged['bookmarks'] as List) (b as Map)['p']], [2, 1]);
      expect(merged['wird'], {
        'date': '2026-10-20',
        'pages': [1, 2, 3],
        'ticked': true,
      });
      expect(merged['stats'], {
        '2026-10-20': [3, 100],
        '2026-10-19': [1, 1],
      });
    });

    test('quran notes: highlights and notes by ayah, newer note wins', () async {
      await roundTrip((kv) => QuranNotesBackup(ReadingRepository(LocalStore(kv))), (kv) async {
        final r = ReadingRepository(LocalStore(kv));
        await r.setHighlight(const AyahRef(2, 255), MarkColor.lapis);
        await r.setNote(const AyahRef(1, 1), 'note', _t0);
      });
      final m = QuranNotesBackup(ReadingRepository(store)).merge(
        {
          'highlights': {'2:255': 'gold'},
          'notes': [
            {'s': 1, 'a': 1, 't': 'old', 'at': _t0.toIso8601String()},
          ],
        },
        {
          'highlights': {'3:1': 'rose'},
          'notes': [
            {'s': 1, 'a': 1, 't': 'new', 'at': _t1.toIso8601String()},
          ],
        },
        localAt: _t0,
        remoteAt: _t1,
      );
      expect(m['highlights'], {'2:255': 'gold', '3:1': 'rose'});
      expect(((m['notes'] as List).single as Map)['t'], 'new');
    });

    test('khatma: plan last-writer-wins, history union', () async {
      final a = KhatmaBackup(ReadingRepository(store));
      final m = a.merge(
        {
          'khatma': {'plan': 'local'},
          'khatmaHistory': [
            {'startedOn': '2026-01-01', 'finishedOn': '2026-02-01'},
          ],
        },
        {
          'khatma': {'plan': 'remote'},
          'khatmaHistory': [
            {'startedOn': '2026-03-01', 'finishedOn': '2026-04-01'},
          ],
        },
        localAt: _t1,
        remoteAt: _t0,
      );
      expect(m['khatma'], {'plan': 'local'});
      expect([for (final h in m['khatmaHistory'] as List) (h as Map)['finishedOn']], ['2026-04-01', '2026-02-01']);
    });

    test('hifz: whole plan, a cleared phone never beats a real plan', () async {
      await roundTrip((kv) => HifzBackup(LocalStore(kv)), (kv) => LocalStore(kv).write('hifz', {'goal': 'amma', 'perDay': 3}));
      final a = HifzBackup(store);
      expect(
        a.merge(
          {
            'plan': <String, Object>{},
          },
          {
            'plan': {'goal': 'amma'},
          },
          localAt: _t1,
          remoteAt: _t0,
        )['plan'],
        {'goal': 'amma'},
      );
    });

    test('azkar: same-day counts take the max, favourites union', () async {
      await roundTrip((kv) => AzkarBackup(LocalStore(kv)), (kv) async {
        await LocalStore(kv).write('azkar', {
          'date': '2026-10-20',
          'counts': {'z1': 3},
          'ticked': <String>[],
        });
        await LocalStore(kv).write('favourites', ['d1']);
      });
      final m = AzkarBackup(store).merge(
        {
          'day': {
            'date': '2026-10-20',
            'counts': {'z1': 3, 'z2': 1},
            'ticked': <String>[],
          },
          'favourites': ['d1'],
        },
        {
          'day': {
            'date': '2026-10-20',
            'counts': {'z1': 2, 'z3': 7},
            'ticked': ['morning'],
          },
          'favourites': ['d2'],
        },
        localAt: _t0,
        remoteAt: _t1,
      );
      expect(m['day'], {
        'date': '2026-10-20',
        'counts': {'z1': 3, 'z2': 1, 'z3': 7},
        'ticked': ['morning'],
      });
      expect(m['favourites'], ['d1', 'd2']);
    });

    test('listen: reciter and position follow, downloads and the metered switch never do', () async {
      final ls = ListenStore(store);
      await ls.setReciter('husary');
      await ls.setAllowMetered(true);
      await ls.setDownloading('husary', true);
      final doc = await ListenBackup(ls).export();
      expect(doc.keys.toSet(), {'reciter', 'snapshot', 'day'});
      final other = ListenStore(LocalStore(MemoryKvStore()));
      await ListenBackup(other).import(doc);
      expect(await other.reciterId(), 'husary');
      expect(await other.allowMetered(), isFalse);
      expect(await other.downloading(), isEmpty);
      final m = ListenBackup(ls).merge(
        {
          'reciter': 'a',
          'day': {'date': '2026-10-20', 'sec': 30, 'ticked': false},
        },
        {
          'reciter': 'b',
          'day': {'date': '2026-10-20', 'sec': 90, 'ticked': true},
        },
        localAt: _t0,
        remoteAt: _t1,
      );
      expect(m['reciter'], 'b');
      expect(m['day'], {'date': '2026-10-20', 'sec': 90, 'ticked': true});
    });

    test('routine: the three slots only (never the place)', () async {
      var settings = const AppSettings(quranSlot: RoutineSlot.at(7 * 60));
      final a = RoutineBackup(
        load: () async => settings,
        apply: (q, h, d) async => settings = settings.copyWith(quranSlot: q, hifzSlot: h, dhikrSlot: d),
      );
      final doc = await a.export();
      expect(doc.keys.toSet(), {'quranSlot', 'hifzSlot', 'dhikrSlot'});
      settings = const AppSettings();
      await a.import(doc);
      expect(settings.quranSlot, const RoutineSlot.at(7 * 60));
    });

    test('ramadan: every year, days as sets', () async {
      await roundTrip(RamadanBackup.new, (kv) async {
        await kv.write(
          RamadanRepository.logKey(1447),
          jsonEncode({
            'fasted': [1, 2],
            'taraweeh': [1],
            'juz': <int>[],
          }),
        );
        await kv.write(
          RamadanRepository.logKey(1446),
          jsonEncode({
            'fasted': [30],
            'taraweeh': <int>[],
            'juz': [3],
          }),
        );
      });
      final m = RamadanBackup(kv).merge(
        {
          'years': {
            '1447': {
              'fasted': [1, 2],
              'taraweeh': <int>[],
              'juz': <int>[],
            },
          },
        },
        {
          'years': {
            '1447': {
              'fasted': [2, 3],
              'taraweeh': [1],
              'juz': <int>[],
            },
          },
        },
        localAt: _t0,
        remoteAt: _t1,
      );
      expect(m['years'], {
        '1447': {
          'fasted': [1, 2, 3],
          'taraweeh': [1],
          'juz': <int>[],
        },
      });
    });

    test('tasbeeh: last writer wins', () async {
      await roundTrip(TasbeehBackup.new, (kv) => kv.write(TasbeehBackup.key, '99'));
      final a = TasbeehBackup(kv);
      expect(a.merge({'count': 4}, {'count': 33}, base: {'count': 4}, localAt: _t1, remoteAt: _t0)['count'], 33);
      expect(a.isEmpty({'count': 0}), isTrue);
    });
  });

  group('BackupSync', () {
    late FakeBackupServer server;
    setUp(() => server = FakeBackupServer());

    test('off by default: nothing reaches the server until the switch is turned on', () async {
      final a = Phone(server);
      addTearDown(a.container.dispose);
      a.status;
      await a.reading.toggle(page(10, _t0));
      await settle();
      expect(a.status.enabled, isFalse);
      expect(server.calls.where((c) => c.contains('/backup')), isEmpty);
    });

    test('guests cannot turn it on', () async {
      final g = Phone(server, guest: true);
      addTearDown(g.container.dispose);
      expect(g.status.available, isFalse);
      await g.sync.enable();
      expect(g.status.enabled, isFalse);
      expect(g.consents.granted(ConsentKind.cloudBackup), isFalse);
      expect(server.calls, isEmpty);
    });

    test('enable uploads; a new phone restores; changes push after the debounce; a conflict merges and retries', () async {
      final a = Phone(server);
      addTearDown(a.container.dispose);
      await a.reading.toggle(page(10, _t0));
      await a.reading.setNote(const AyahRef(2, 255), 'note', _t0);
      await a.sync.enable();
      expect(server.consent, isTrue);
      expect(a.status.enabled, isTrue);
      expect(a.status.lastBackupAt, isNotNull);
      expect(server.data('quran_reading')!['bookmarks'], hasLength(1));
      expect(server.data('quran_notes')!['notes'], hasLength(1));
      expect(server.docs.containsKey('tasbeeh'), isFalse, reason: 'an empty counter is not uploaded');

      // A second phone signs in: the account has a backup → offer, then restore.
      final b = Phone(server);
      addTearDown(b.container.dispose);
      await b.reading.toggle(page(20, _t1)); // something already on the new phone
      await b.sync.start();
      expect(b.status.restoreOffer, isNotNull);
      await b.sync.restore();
      expect(b.status.restoreOffer, isNull);
      expect({for (final m in await b.reading.bookmarks()) m.page}, {10, 20});
      expect((await b.reading.annotations()).notes.keys, [const AyahRef(2, 255)]);
      expect({for (final m in server.data('quran_reading')!['bookmarks'] as List) (m as Map)['p']}, {10, 20});

      // Phone A, still on the old version, adds a bookmark: the debounced push gets a 409, merges, retries.
      server.calls.clear();
      await a.reading.toggle(page(30, _t1));
      await eventually(() => serverPages(server).contains(30));
      expect(server.calls.where((c) => c == 'PUT /v1/me/backup/quran_reading').length, 2);
      expect({for (final m in await a.reading.bookmarks()) m.page}, {10, 20, 30});
      expect({for (final m in server.data('quran_reading')!['bookmarks'] as List) (m as Map)['p']}, {10, 20, 30});

      // A deletion on B reaches A instead of coming back.
      await b.sync.backUpNow(); // B catches up to the latest version first
      await b.reading.toggle(page(10, _t0)); // remove
      await eventually(() => !serverPages(server).contains(10));
      await a.sync.backUpNow();
      expect({for (final m in await a.reading.bookmarks()) m.page}, {20, 30});
    });

    test('offline: the change waits on the phone and goes out on the next attempt', () async {
      final a = Phone(server);
      addTearDown(a.container.dispose);
      await a.sync.enable();
      server.offline = true;
      await a.reading.toggle(page(7, _t0));
      await eventually(() => a.status.offline);
      expect(await a.engine.hasPending(), isTrue);
      server.offline = false;
      await a.sync.backUpNow();
      expect(a.status.offline, isFalse);
      expect(await a.engine.hasPending(), isFalse);
      expect(server.data('quran_reading')!['bookmarks'], hasLength(1));
    });

    test('turning it off withdraws the consent (server copy deleted) and keeps the phone data', () async {
      final a = Phone(server);
      addTearDown(a.container.dispose);
      await a.reading.toggle(page(7, _t0));
      await a.sync.enable();
      expect(server.docs, isNotEmpty);
      await a.sync.disable();
      expect(server.consent, isFalse);
      expect(server.docs, isEmpty);
      expect(a.status.enabled, isFalse);
      expect(await a.kv.read(BackupEngine.metaKey), isNull);
      expect(await a.reading.bookmarks(), hasLength(1));
      server.calls.clear();
      await a.reading.toggle(page(8, _t0));
      await settle();
      expect(server.calls, isEmpty);
    });

    test('the server switched it off elsewhere: this phone follows', () async {
      final a = Phone(server);
      addTearDown(a.container.dispose);
      await a.sync.enable();
      server.consent = false;
      await a.sync.backUpNow();
      expect(a.status.enabled, isFalse);
      expect(a.consents.granted(ConsentKind.cloudBackup), isFalse);
    });

    test('"not now" keeps this phone off and does not ask again for that account', () async {
      final a = Phone(server);
      addTearDown(a.container.dispose);
      await a.reading.toggle(page(7, _t0));
      await a.sync.enable();
      final b = Phone(server);
      addTearDown(b.container.dispose);
      await b.sync.start();
      expect(b.status.restoreOffer, isNotNull);
      await b.sync.dismissOffer();
      await b.sync.start();
      expect(b.status.restoreOffer, isNull);
      expect(b.status.enabled, isFalse);
      expect(await b.reading.bookmarks(), isEmpty);
    });
  });

  group('Privacy › cloud backup section', () {
    setUp(() => YqGlassConfig.enableBlur = false);

    Widget section(FakeBackupServer server, {required bool guest, bool on = false}) {
      final kv = MemoryKvStore();
      final api = ApiClient(baseUrl: 'http://api', tokens: TokenStore(MemoryKvStore()), client: server.client());
      final consents = ConsentRepository(api: api, store: kv);
      if (on) consents.adopt(ConsentKind.cloudBackup, true);
      return harness(
        const Scaffold(body: SingleChildScrollView(child: BackupSection())),
        locale: 'en',
        kv: kv,
        overrides: [
          apiClientProvider.overrideWithValue(api),
          consentRepositoryProvider.overrideWithValue(consents),
          initialSessionProvider.overrideWithValue(
            guest
                ? const Session(provider: SignInProvider.guest, userId: 'g1')
                : const Session(provider: SignInProvider.google, userId: 'u1'),
          ),
        ],
      );
    }

    testWidgets('guests see it disabled with "sign in to enable"', (tester) async {
      final server = FakeBackupServer();
      await tester.pumpWidget(section(server, guest: true));
      await tester.pumpAndSettle();
      final t = lookupAppLocalizations(const Locale('en'));
      expect(find.text(t.backupTitle), findsWidgets);
      expect(find.text(t.backupGuest), findsOneWidget);
      await tester.tap(find.byType(YqSwitch), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(server.consent, isFalse);
    });

    testWidgets('turning it off asks first; cancel keeps it on', (tester) async {
      final server = FakeBackupServer()..consent = true;
      await tester.pumpWidget(section(server, guest: false, on: true));
      await tester.pumpAndSettle();
      final t = lookupAppLocalizations(const Locale('en'));
      expect(find.text(t.backupGuest), findsNothing);
      expect(find.text(t.backupNow), findsOneWidget);
      await tester.tap(find.byType(YqSwitch));
      await tester.pumpAndSettle();
      expect(find.text(t.backupOffTitle), findsOneWidget);
      expect(find.text(t.backupOffBody), findsOneWidget);
      await tester.tap(find.text(t.cancel));
      await tester.pumpAndSettle();
      expect(server.consent, isTrue);
      expect(find.text(t.backupNow), findsOneWidget);
    });
  });
}
