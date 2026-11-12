import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/platform/nfc_service.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/encode_repository.dart';
import '../domain/medal_nfc.dart';
import '../domain/public_card.dart';

/// Staff encoder (spec §5.26 › in-house encoding), opened only by `yaqeen://encode/<token>` from
/// admin › «ترميز بالهاتف». Writes `<baseUrl>/t/<code>` onto blank chips of one batch, reads each
/// back, optionally locks it, and reports it. The [token] lives only as long as this screen.
class EncodeScreen extends ConsumerStatefulWidget {
  const EncodeScreen({super.key, required this.token});
  final String token;

  @override
  ConsumerState<EncodeScreen> createState() => _EncodeScreenState();
}

enum _Phase { idle, writing, verifying, saving }

class _EncodeScreenState extends ConsumerState<EncodeScreen> {
  EncodeSession? _session;
  bool _loading = true;
  EncodeProblem? _loadProblem;

  _Phase _phase = _Phase.idle;
  String? _selected;
  bool _lock = false;
  String? _status;
  bool _statusIsError = false;

  /// A chip written and verified whose report failed: retried with «أعد الحفظ».
  ({String code, String? uid, bool locked})? _unsaved;

  late final NfcService _nfc = ref.read(nfcServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (_phase == _Phase.writing || _phase == _Phase.verifying) _nfc.cancel().ignore();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadProblem = null;
    });
    try {
      final s = await ref.read(encodeRepositoryProvider).session(widget.token);
      if (mounted) setState(() => _session = s);
    } on EncodeException catch (e) {
      if (mounted) setState(() => _loadProblem = e.problem);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _expired => _session != null && !ref.read(clockProvider)().isBefore(_session!.expiresAt);
  String? get _target => _selected ?? _session?.next;

  void _say(String? message, {bool error = false}) => setState(() {
        _status = message;
        _statusIsError = error;
      });

  String _nfcMessage(AppLocalizations t, NfcError e) => switch (e) {
        NfcError.unavailable => t.encodeNfcOff,
        NfcError.cancelled => '',
        NfcError.timeout => t.encodeErrTimeout,
        NfcError.notNdef => t.encodeErrNotNdef,
        NfcError.readOnly => t.encodeErrReadOnly,
        NfcError.tooSmall => t.encodeErrTooSmall,
        NfcError.empty => t.encodeErrVerify,
        NfcError.writeFailed => t.encodeErrWrite,
        NfcError.verifyFailed => t.encodeErrVerify,
        NfcError.lockFailed => t.encodeErrLock,
      };

  void _gone() => setState(() {
        _loadProblem = EncodeProblem.gone;
        _session = null;
        _phase = _Phase.idle;
      });

  Future<void> _write() async {
    final t = AppLocalizations.of(context);
    final session = _session;
    final code = _target;
    if (session == null || code == null) return;
    if (_expired) return _gone();
    final url = session.urlFor(code);
    setState(() {
      _phase = _Phase.writing;
      _unsaved = null;
    });
    _say(t.encodeWriting);
    try {
      var result = await _nfc.writeUri(url, lock: _lock, prompt: t.encodeWrite, success: t.nfcSuccess, failure: t.nfcFailed);
      if (!mounted) return;
      if (!result.verified) {
        // Formatted from blank: one more tap reads it back.
        setState(() => _phase = _Phase.verifying);
        _say(t.encodeVerifyAgain);
        final back = await _nfc.readUri(prompt: t.encodeVerifyAgain, failure: t.nfcFailed);
        if (back.uri != url) throw const NfcException(NfcError.verifyFailed);
        result = NfcWrite(uid: result.uid ?? back.uid, verified: true, locked: result.locked);
      }
      HapticFeedback.mediumImpact();
      await _save(code: code, uid: result.uid, locked: result.locked);
    } on NfcException catch (e) {
      if (!mounted) return;
      setState(() => _phase = _Phase.idle);
      final message = _nfcMessage(t, e.error);
      _say(message.isEmpty ? null : message, error: message.isNotEmpty);
    }
  }

  Future<void> _save({required String code, String? uid, required bool locked}) async {
    final t = AppLocalizations.of(context);
    setState(() => _phase = _Phase.saving);
    try {
      await ref.read(encodeRepositoryProvider).written(widget.token, code: code, uid: uid, locked: locked);
      if (!mounted) return;
      setState(() {
        _session = _session!.markEncoded(code, ref.read(clockProvider)());
        _selected = null;
        _unsaved = null;
        _phase = _Phase.idle;
      });
      _say(t.encodeDone(formatTagCode(code)));
    } on EncodeException catch (e) {
      if (!mounted) return;
      if (e.problem == EncodeProblem.gone) return _gone();
      setState(() {
        _phase = _Phase.idle;
        _unsaved = e.problem == EncodeProblem.network ? (code: code, uid: uid, locked: locked) : null;
      });
      _say(e.problem == EncodeProblem.notInBatch ? t.encodeErrNotInBatch : t.encodeErrNetwork, error: true);
    }
  }

  /// Read a chip and say what it carries (re-encode / test).
  Future<void> _test() async {
    final t = AppLocalizations.of(context);
    final session = _session;
    if (session == null) return;
    setState(() => _phase = _Phase.verifying);
    _say(t.medalNfcWaiting);
    try {
      final read = await _nfc.readUri(prompt: t.medalNfcPrompt, failure: t.nfcFailed);
      if (!mounted) return;
      final code = tagCodeFromChipUri(read.uri, siteUrl: session.baseUrl);
      setState(() {
        _phase = _Phase.idle;
        if (code != null && session.contains(code) && session.urlFor(code) == read.uri) _selected = code;
      });
      if (code != null && session.contains(code) && session.urlFor(code) == read.uri) {
        _say(t.encodeTestResult(formatTagCode(code)));
      } else {
        _say(t.encodeTestOther(read.uri), error: true);
      }
    } on NfcException catch (e) {
      if (!mounted) return;
      setState(() => _phase = _Phase.idle);
      final message = e.error == NfcError.empty ? t.medalNfcEmpty : _nfcMessage(t, e.error);
      _say(message.isEmpty ? null : message, error: message.isNotEmpty);
    }
  }

  Future<void> _cancel() async {
    await _nfc.cancel();
    if (mounted) setState(() => _phase = _Phase.idle);
    _say(null);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final session = _session;
    final nfc = ref.watch(nfcStateProvider).valueOrNull;

    if (session == null) {
      return Scaffold(
        body: YqCanvas(
          bottom: YqSpace.l,
          stage: YqStage(compact: true, child: YqStageBar(back: true, title: t.encodeTitle)),
          children: [
            if (_loading)
              const YqSkeletonRows(rows: 3)
            else if (_loadProblem == EncodeProblem.gone)
              YqEmptyState(icon: YqIcons.settings, title: t.encodeGone)
            else
              YqErrorState(onRetry: _load),
          ],
        ),
      );
    }

    final target = _target;
    final busy = _phase != _Phase.idle;
    final ready = nfc == NfcState.enabled;
    return Scaffold(
      body: YqCanvas(
        bottom: YqSpace.l,
        stage: YqStage(
          compact: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YqStageBar(back: true, title: t.encodeTitle, subtitle: t.encodeBatch(session.batch)),
              const SizedBox(height: YqSpace.l),
              Center(
                child: YqRing(
                  value: session.total == 0 ? 0 : session.encoded / session.total,
                  size: 132,
                  stroke: 9,
                  child: Text(
                    '${YqFormat.number(session.encoded)}/${YqFormat.number(session.total)}',
                    textDirection: TextDirection.ltr,
                    style: YqMoment.numeral(size: 28),
                  ),
                ),
              ),
              const SizedBox(height: YqSpace.m),
              YqMoment(
                eyebrow: t.encodeProgress(YqFormat.number(session.encoded), YqFormat.number(session.total)),
                value: Text(
                  target == null
                      ? t.encodeAllDone
                      : (_selected != null ? t.encodeSelected(formatTagCode(target)) : t.encodeNext(formatTagCode(target))),
                  style: target == null ? text.bodyMedium : YqMoment.display(context, size: 24),
                ),
                caption: Text(t.encodeExpires(YqFormat.time(session.expiresAt, locale))),
              ),
            ],
          ),
        ),
        // Long batches (up to 5,000 codes) stay lazy.
        slivers: [
          SliverList.builder(
            itemCount: session.codes.length,
            itemBuilder: (_, i) {
              final c = session.codes[i];
              final chosen = c.code == target;
              return YqListRow(
                dense: true,
                title: formatTagCode(c.code),
                titleColor: chosen ? YqColors.lapis : null,
                subtitle: c.encoded ? '${t.encodeCodeDone} · ${YqFormat.time(c.encodedAt!, locale)}' : t.encodeCodeTodo,
                semanticLabel: '${formatTagCode(c.code)}، ${c.encoded ? t.encodeCodeDone : t.encodeCodeTodo}',
                trailing: Icon(
                  c.encoded ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: c.encoded ? YqColors.success : YqColors.mist,
                ),
                onTap: busy ? null : () => setState(() => _selected = c.code == _session?.next ? null : c.code),
              );
            },
          ),
        ],
        children: [
          if (nfc == NfcState.unsupported) _Note(t.encodeNoNfc, error: true),
          if (nfc == NfcState.disabled) _Note(t.encodeNfcOff, error: true),
          YqGroup(
            children: [
              YqListRow(
                title: t.encodeLock,
                subtitle: t.encodeLockHint,
                trailing: YqSwitch(
                  label: t.encodeLock,
                  value: _lock,
                  activeColor: YqColors.error,
                  onChanged: (v) {
                    if (!busy) setState(() => _lock = v);
                  },
                ),
              ),
            ],
          ),
          if (_lock) _Note(t.encodeLockOnWarning, error: true),
          const SizedBox(height: YqSpace.l),
          YqButton(
            label: t.encodeWrite,
            loading: busy,
            onPressed: !ready || busy || target == null ? null : _write,
          ),
          if (busy && _phase != _Phase.saving) ...[
            const SizedBox(height: YqSpace.s),
            YqButton.text(label: t.cancel, onPressed: _cancel),
          ],
          if (_unsaved case final u?) ...[
            const SizedBox(height: YqSpace.s),
            YqButton.secondary(label: t.encodeRetrySave, onPressed: busy ? null : () => _save(code: u.code, uid: u.uid, locked: u.locked)),
          ],
          if (_status != null) _Note(_status!, error: _statusIsError),
          const SizedBox(height: YqSpace.s),
          YqButton.text(label: t.encodeTest, onPressed: !ready || busy ? null : _test),
          const SizedBox(height: YqSpace.l),
          YqHeading(t.encodeCodes),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: YqSpace.m),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: error ? YqColors.error : YqColors.success, height: 1.6),
        ),
      );
}
