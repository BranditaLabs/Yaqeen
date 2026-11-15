import 'dart:convert';
import 'dart:io';

import 'push_service.dart';

/// Pushes that arrive while the app is in the background or closed. FCM delivers them to a
/// separate isolate, which can't reach the app's in-memory stores, so they are appended to a file
/// (one JSON line each) and the app takes them into the notification centre when it next runs.
class PushSpool {
  PushSpool(this._file);
  final Future<File> Function() _file;

  Future<void> append(PushMessage m) async {
    final f = await _file();
    await f.parent.create(recursive: true);
    await f.writeAsString('${jsonEncode(m.toJson())}\n', mode: FileMode.append, flush: true);
  }

  /// Everything spooled so far, once. The file is renamed before it is read, so a push appended
  /// meanwhile starts a new file and is taken next time instead of being lost.
  Future<List<PushMessage>> take() async {
    final f = await _file();
    if (!await f.exists()) return const [];
    final taken = await f.rename('${f.path}.taking');
    try {
      final out = <PushMessage>[];
      for (final line in await taken.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          out.add(PushMessage.fromJson((jsonDecode(line) as Map).cast<String, dynamic>()));
        } on Object {
          // A torn line (killed mid-write) loses that one push, never the rest.
        }
      }
      return out;
    } finally {
      await taken.delete();
    }
  }
}
