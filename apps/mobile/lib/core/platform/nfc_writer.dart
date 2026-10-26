import 'dart:async';
import 'dart:typed_data';

import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

import '../../features/card/domain/public_card.dart';

enum NfcWriteResult { written, notSupported, disabled, notWritable, tooSmall, cancelled, failed }

/// Writes the public card URL to an NFC tag as one NDEF URI record (any phone opens it in the
/// browser, no app needed). Behind an interface so tests and unsupported devices use [NoopNfcWriter].
abstract interface class NfcWriter {
  /// enabled / disabled (off in settings) / unsupported.
  Future<NfcAvailabilityState> availability();

  /// Waits for a tag and writes [url]. [prompt] is shown by iOS in its system sheet.
  Future<NfcWriteResult> writeUrl(String url, {required String prompt, required String done});

  Future<void> cancel();
}

enum NfcAvailabilityState { enabled, disabled, unsupported }

class NoopNfcWriter implements NfcWriter {
  const NoopNfcWriter();
  @override
  Future<NfcAvailabilityState> availability() async => NfcAvailabilityState.unsupported;
  @override
  Future<NfcWriteResult> writeUrl(String url, {required String prompt, required String done}) async => NfcWriteResult.notSupported;
  @override
  Future<void> cancel() async {}
}

class PluginNfcWriter implements NfcWriter {
  Completer<NfcWriteResult>? _pending;

  @override
  Future<NfcAvailabilityState> availability() async {
    try {
      return switch (await NfcManager.instance.checkAvailability()) {
        NfcAvailability.enabled => NfcAvailabilityState.enabled,
        NfcAvailability.disabled => NfcAvailabilityState.disabled,
        _ => NfcAvailabilityState.unsupported,
      };
    } on Object {
      return NfcAvailabilityState.unsupported;
    }
  }

  @override
  Future<NfcWriteResult> writeUrl(String url, {required String prompt, required String done}) async {
    final state = await availability();
    if (state == NfcAvailabilityState.unsupported) return NfcWriteResult.notSupported;
    if (state == NfcAvailabilityState.disabled) return NfcWriteResult.disabled;
    final completer = _pending = Completer<NfcWriteResult>();
    final message = NdefMessage(
      records: [
        NdefRecord(
          typeNameFormat: TypeNameFormat.wellKnown,
          type: Uint8List.fromList([0x55]), // 'U'
          identifier: Uint8List(0),
          payload: uriRecordPayload(url),
        ),
      ],
    );
    await NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
      alertMessageIos: prompt,
      onSessionErrorIos: (_) {
        if (!completer.isCompleted) completer.complete(NfcWriteResult.cancelled);
      },
      onDiscovered: (tag) async {
        final ndef = Ndef.from(tag);
        NfcWriteResult result;
        if (ndef == null || !ndef.isWritable) {
          result = NfcWriteResult.notWritable;
        } else if (message.byteLength > ndef.maxSize) {
          result = NfcWriteResult.tooSmall;
        } else {
          try {
            await ndef.write(message: message);
            result = NfcWriteResult.written;
          } on Object {
            result = NfcWriteResult.failed;
          }
        }
        await NfcManager.instance.stopSession(
          alertMessageIos: result == NfcWriteResult.written ? done : null,
          errorMessageIos: result == NfcWriteResult.written ? null : prompt,
        );
        if (!completer.isCompleted) completer.complete(result);
      },
    );
    return completer.future;
  }

  @override
  Future<void> cancel() async {
    final p = _pending;
    if (p != null && !p.isCompleted) p.complete(NfcWriteResult.cancelled);
    try {
      await NfcManager.instance.stopSession();
    } on Object {
      // no session
    }
  }
}
