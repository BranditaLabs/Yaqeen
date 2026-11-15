import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/ndef_record.dart' as rec;
import 'package:nfc_manager/nfc_manager.dart' as nfc;
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

/// NFC for Yaqeen key medals and cards (spec §5.26): read the chip's NDEF URI record (activate a
/// medal by holding it to the phone) and, for staff encoding, write `/t/<code>` onto a blank chip.
///
/// Nothing here starts on app start-up: a session opens only when the user taps a button, and only
/// one at a time. [PluginNfcService] wraps `nfc_manager`; tests use a fake; other platforms use
/// [NoopNfcService].
abstract interface class NfcService {
  /// Whether this phone has NFC and it is switched on.
  Future<NfcState> availability();

  /// Hold a chip to the phone and return its first URI record (+ the chip UID when known).
  /// [prompt] is the iOS system sheet's message. Throws [NfcException].
  Future<NfcRead> readUri({String? prompt, String? failure});

  /// Hold a chip to the phone, write one NDEF URI record [uri], read it back, and — only when
  /// [lock] — make the chip read-only for good. Throws [NfcException].
  Future<NfcWrite> writeUri(String uri, {bool lock = false, String? prompt, String? success, String? failure});

  /// Stop a waiting session (the user cancelled, the screen closed).
  Future<void> cancel();
}

enum NfcState { enabled, disabled, unsupported }

/// What went wrong with a chip — each one has its own message on screen.
enum NfcError {
  /// No NFC on this phone, or it is switched off.
  unavailable,

  /// The user closed the system sheet, or the screen stopped waiting.
  cancelled,

  /// Nothing came near the phone in time.
  timeout,

  /// The chip has no NDEF / can't be formatted for it (wrong tag type).
  notNdef,

  /// The chip is locked (read-only) — it can't be rewritten.
  readOnly,

  /// The URL doesn't fit on the chip.
  tooSmall,

  /// The chip carries no URI record.
  empty,

  /// Writing failed (moved away too early, a radio error).
  writeFailed,

  /// It was written but reads back differently.
  verifyFailed,

  /// Locking was asked for but this chip can't be made read-only.
  lockFailed,
}

class NfcException implements Exception {
  const NfcException(this.error, [this.detail]);
  final NfcError error;
  final String? detail;
  @override
  String toString() => 'NfcException(${error.name}${detail == null ? '' : ': $detail'})';
}

class NfcRead {
  const NfcRead({required this.uri, this.uid});

  /// The first URI record on the chip.
  final String uri;

  /// The chip UID in upper-case hex, when the platform exposes it.
  final String? uid;
}

class NfcWrite {
  const NfcWrite({this.uid, required this.verified, required this.locked});
  final String? uid;

  /// Read back and matched. False only when the chip had to be formatted first (Android): then the
  /// screen asks for one more tap to verify.
  final bool verified;
  final bool locked;
}

/* ------------------------------------------------------------------ NDEF URI records */

/// NFC Forum URI RTD abbreviations (index = prefix byte).
const _uriPrefixes = [
  '', 'http://www.', 'https://www.', 'http://', 'https://', 'tel:', 'mailto:', 'ftp://anonymous:anonymous@', 'ftp://ftp.', 'ftps://', //
  'sftp://', 'smb://', 'nfs://', 'ftp://', 'dav://', 'news:', 'telnet://', 'imap:', 'rtsp://', 'urn:', //
  'pop:', 'sip:', 'sips:', 'tftp:', 'btspp://', 'btl2cap://', 'btgoep://', 'tcpobex://', 'irdaobex://', 'file://', //
  'urn:epc:id:', 'urn:epc:tag:', 'urn:epc:pat:', 'urn:epc:raw:', 'urn:epc:', 'urn:nfc:',
];

/// The payload of a well-known `U` record for [uri] (shortest prefix abbreviation that applies).
Uint8List encodeUriPayload(String uri) {
  var code = 0;
  for (var i = 1; i < _uriPrefixes.length; i++) {
    final p = _uriPrefixes[i];
    if (uri.startsWith(p) && p.length > _uriPrefixes[code].length) code = i;
  }
  return Uint8List.fromList([code, ...utf8.encode(uri.substring(_uriPrefixes[code].length))]);
}

/// The URI in a well-known `U` record payload; null when it isn't one.
String? decodeUriPayload(List<int> payload) {
  if (payload.isEmpty || payload.first >= _uriPrefixes.length) return null;
  try {
    return _uriPrefixes[payload.first] + utf8.decode(payload.sublist(1));
  } on FormatException {
    return null;
  }
}

/// One NDEF URI record for [uri].
rec.NdefRecord uriRecord(String uri) => rec.NdefRecord(
      typeNameFormat: rec.TypeNameFormat.wellKnown,
      type: Uint8List.fromList([0x55]), // 'U'
      identifier: Uint8List(0),
      payload: encodeUriPayload(uri),
    );

/// The first URI in [records]: a well-known `U` record, or an absolute-URI record.
String? firstUri(Iterable<rec.NdefRecord> records) {
  for (final r in records) {
    if (r.typeNameFormat == rec.TypeNameFormat.wellKnown && r.type.length == 1 && r.type.first == 0x55) {
      final u = decodeUriPayload(r.payload);
      if (u != null) return u;
    }
    if (r.typeNameFormat == rec.TypeNameFormat.absoluteUri) {
      try {
        return utf8.decode(r.type);
      } on FormatException {
        continue;
      }
    }
  }
  return null;
}

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

/* ------------------------------------------------------------------ implementations */

/// Tests, desktop and web: no NFC.
class NoopNfcService implements NfcService {
  const NoopNfcService();
  @override
  Future<NfcState> availability() async => NfcState.unsupported;
  @override
  Future<NfcRead> readUri({String? prompt, String? failure}) async => throw const NfcException(NfcError.unavailable);
  @override
  Future<NfcWrite> writeUri(String uri, {bool lock = false, String? prompt, String? success, String? failure}) async =>
      throw const NfcException(NfcError.unavailable);
  @override
  Future<void> cancel() async {}
}

/// `nfc_manager` 4.x: Android reader mode / iOS Core NFC (NDEF entitlement, see Runner.entitlements).
class PluginNfcService implements NfcService {
  PluginNfcService({this.timeout = const Duration(seconds: 60)});

  /// Android has no system sheet: stop waiting after this long.
  final Duration timeout;
  Completer<Object>? _pending;

  nfc.NfcManager get _m => nfc.NfcManager.instance;
  bool get _supportedPlatform =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<NfcState> availability() async {
    if (!_supportedPlatform) return NfcState.unsupported;
    try {
      return switch (await _m.checkAvailability()) {
        nfc.NfcAvailability.enabled => NfcState.enabled,
        nfc.NfcAvailability.disabled => NfcState.disabled,
        nfc.NfcAvailability.unsupported => NfcState.unsupported,
      };
    } on Object {
      return NfcState.unsupported;
    }
  }

  String? _uid(nfc.NfcTag tag) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final id = NfcTagAndroid.from(tag)?.id;
      return id == null || id.isEmpty ? null : _hex(id);
    }
    final id = MiFareIos.from(tag)?.identifier ?? Iso15693Ios.from(tag)?.identifier ?? Iso7816Ios.from(tag)?.identifier;
    return id == null || id.isEmpty ? null : _hex(id);
  }

  /// One session: wait for a chip, run [onTag] on it, close the session (iOS shows [success] or the
  /// error on its sheet).
  Future<T> _session<T extends Object>(Future<T> Function(nfc.NfcTag tag) onTag, {String? prompt, String? success, String? failure}) async {
    if ((await availability()) != NfcState.enabled) throw const NfcException(NfcError.unavailable);
    if (_pending != null) await cancel();
    final done = Completer<Object>();
    _pending = done;
    var handled = false;
    await _m.startSession(
      pollingOptions: {nfc.NfcPollingOption.iso14443, nfc.NfcPollingOption.iso15693},
      alertMessageIos: prompt,
      onSessionErrorIos: (e) {
        if (!done.isCompleted) done.complete(NfcException(NfcError.cancelled, e.message));
      },
      onDiscovered: (tag) async {
        if (handled) return;
        handled = true;
        try {
          final result = await onTag(tag);
          await _m.stopSession(alertMessageIos: success);
          if (!done.isCompleted) done.complete(result);
        } on NfcException catch (e) {
          await _m.stopSession(errorMessageIos: failure).catchError((Object _) {});
          if (!done.isCompleted) done.complete(e);
        } on Object catch (e) {
          await _m.stopSession(errorMessageIos: failure).catchError((Object _) {});
          if (!done.isCompleted) done.complete(NfcException(NfcError.writeFailed, '$e'));
        }
      },
    );
    final Object out;
    try {
      out = await done.future.timeout(
        timeout,
        onTimeout: () {
          _m.stopSession().catchError((Object _) {}).ignore();
          return const NfcException(NfcError.timeout);
        },
      );
    } finally {
      if (identical(_pending, done)) _pending = null;
    }
    if (out is NfcException) throw out;
    return out as T;
  }

  Future<List<rec.NdefRecord>?> _readRecords(nfc.NfcTag tag) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final ndef = NdefAndroid.from(tag);
      if (ndef == null) return null;
      return (await ndef.getNdefMessage() ?? ndef.cachedNdefMessage)?.records ?? const [];
    }
    final ndef = NdefIos.from(tag);
    if (ndef == null) return null;
    return (await ndef.readNdef())?.records ?? const [];
  }

  @override
  Future<NfcRead> readUri({String? prompt, String? failure}) => _session(
        (tag) async {
          final records = await _readRecords(tag);
          if (records == null) throw const NfcException(NfcError.notNdef);
          final uri = firstUri(records);
          if (uri == null) throw const NfcException(NfcError.empty);
          return NfcRead(uri: uri, uid: _uid(tag));
        },
        prompt: prompt,
        failure: failure,
      );

  @override
  Future<NfcWrite> writeUri(String uri, {bool lock = false, String? prompt, String? success, String? failure}) => _session(
        (tag) async {
          final message = rec.NdefMessage(records: [uriRecord(uri)]);
          final uid = _uid(tag);
          if (defaultTargetPlatform == TargetPlatform.android) return _writeAndroid(tag, message, uri, uid, lock);
          return _writeIos(tag, message, uri, uid, lock);
        },
        prompt: prompt,
        success: success,
        failure: failure,
      );

  Future<NfcWrite> _writeAndroid(nfc.NfcTag tag, rec.NdefMessage message, String uri, String? uid, bool lock) async {
    final ndef = NdefAndroid.from(tag);
    if (ndef == null) {
      // A factory-blank chip: format it with the record (read-only at once when locking).
      final formatable = NdefFormatableAndroid.from(tag);
      if (formatable == null) throw const NfcException(NfcError.notNdef);
      try {
        lock ? await formatable.formatReadOnly(message) : await formatable.format(message);
      } on Object catch (e) {
        throw NfcException(NfcError.writeFailed, '$e');
      }
      return NfcWrite(uid: uid, verified: false, locked: lock);
    }
    if (!ndef.isWritable) throw const NfcException(NfcError.readOnly);
    if (message.byteLength > ndef.maxSize) throw const NfcException(NfcError.tooSmall);
    if (lock && !ndef.canMakeReadOnly) throw const NfcException(NfcError.lockFailed);
    try {
      await ndef.writeNdefMessage(message);
    } on Object catch (e) {
      throw NfcException(NfcError.writeFailed, '$e');
    }
    final back = firstUri((await ndef.getNdefMessage())?.records ?? const []);
    if (back != uri) throw const NfcException(NfcError.verifyFailed);
    if (lock) {
      try {
        await ndef.makeReadOnly();
      } on Object catch (e) {
        throw NfcException(NfcError.lockFailed, '$e');
      }
    }
    return NfcWrite(uid: uid, verified: true, locked: lock);
  }

  Future<NfcWrite> _writeIos(nfc.NfcTag tag, rec.NdefMessage message, String uri, String? uid, bool lock) async {
    final ndef = NdefIos.from(tag);
    if (ndef == null) throw const NfcException(NfcError.notNdef);
    final status = await ndef.queryNdefStatus();
    if (status.status == NdefStatusIos.notSupported) throw const NfcException(NfcError.notNdef);
    if (status.status == NdefStatusIos.readOnly) throw const NfcException(NfcError.readOnly);
    if (message.byteLength > status.capacity) throw const NfcException(NfcError.tooSmall);
    try {
      await ndef.writeNdef(message);
    } on Object catch (e) {
      throw NfcException(NfcError.writeFailed, '$e');
    }
    final back = firstUri((await ndef.readNdef())?.records ?? const []);
    if (back != uri) throw const NfcException(NfcError.verifyFailed);
    if (lock) {
      try {
        await ndef.writeLock();
      } on Object catch (e) {
        throw NfcException(NfcError.lockFailed, '$e');
      }
    }
    return NfcWrite(uid: uid, verified: true, locked: lock);
  }

  @override
  Future<void> cancel() async {
    final p = _pending;
    _pending = null;
    if (p != null && !p.isCompleted) p.complete(const NfcException(NfcError.cancelled));
    try {
      await _m.stopSession();
    } on Object {
      // No session open.
    }
  }
}
