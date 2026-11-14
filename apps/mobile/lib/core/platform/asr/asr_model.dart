import '../../config/env.dart';
import '../recitation_engine.dart';

/// What a model file is for.
enum AsrFileRole { encoder, decoder, tokens, vad }

/// One file of the on-device model, pinned by size and SHA-256: a download that does not match is
/// thrown away (a CDN can't swap the model).
class AsrModelFile {
  const AsrModelFile(this.role, this.name, {required this.bytes, required this.sha256, this.url});
  final AsrFileRole role;
  final String name;
  final int bytes;
  final String sha256;

  /// Absolute URL; null → `<manifest.baseUrl><name>`.
  final String? url;
}

/// The recitation model the app downloads on request (docs/MODELS.md): a Whisper tiny fine-tuned on
/// Quran recitation (`tarteel-ai/whisper-tiny-ar-quran`, Apache-2.0), exported to ONNX int8 for the
/// sherpa-onnx runtime, plus Silero VAD (MIT). One download powers «تسميع», «تحفيظ» and the
/// recordings; it works offline afterwards. Never bundled in the app, never committed.
class AsrModelManifest {
  const AsrModelManifest({
    required this.id,
    required this.upstream,
    required this.licence,
    required this.baseUrl,
    required this.files,
  });

  final String id;

  /// `repo@revision` the weights come from.
  final String upstream;
  final String licence;
  final String baseUrl;
  final List<AsrModelFile> files;

  int get bytes => files.fold(0, (s, f) => s + f.bytes);

  /// Every file has a place to come from and a pinned checksum (else nothing is offered).
  bool get published => files.every((f) => f.sha256.length == 64 && f.bytes > 0 && (f.url != null || baseUrl.isNotEmpty));

  Uri urlOf(AsrModelFile f) => Uri.parse(f.url ?? '$baseUrl${f.name}');

  AsrModelFile file(AsrFileRole role) => files.firstWhere((f) => f.role == role);

  AsrModelInfo get info => AsrModelInfo(id: id, bytes: bytes, licence: licence, upstream: upstream);

  static const _tarteel = 'tarteel-ai/whisper-tiny-ar-quran@c3d7e624af5c81bef25a10a2af3a5a84cb4dd0f0';

  /// Silero VAD v4 as sherpa-onnx publishes it (MIT).
  static const _vad = AsrModelFile(
    AsrFileRole.vad,
    'silero_vad.onnx',
    bytes: 643854,
    sha256: '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
    url: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
  );

  /// Ours: `tools/asr/convert.py` output (every MatMul int8, one int8 embedding — 44.5 MB with the
  /// VAD; the run is deterministic, so a re-run reproduces these hashes), hosted at
  /// `ASR_MODEL_BASE_URL`. Values from `tools/asr/manifest.json`.
  static const yaqeen = AsrModelManifest(
    id: 'yaqeen-asr-v1',
    upstream: _tarteel,
    licence: 'Apache-2.0',
    baseUrl: Env.asrModelBaseUrl,
    files: [
      AsrModelFile(AsrFileRole.encoder, 'yaqeen-asr-v1-encoder.int8.onnx', bytes: yaqeenEncoderBytes, sha256: yaqeenEncoderSha256),
      AsrModelFile(AsrFileRole.decoder, 'yaqeen-asr-v1-decoder.int8.onnx', bytes: yaqeenDecoderBytes, sha256: yaqeenDecoderSha256),
      AsrModelFile(AsrFileRole.tokens, 'yaqeen-asr-v1-tokens.txt', bytes: yaqeenTokensBytes, sha256: yaqeenTokensSha256),
      _vad,
    ],
  );

  /// Until our copy is hosted: the same tarteel weights exported by sherpa-onnx's exporter (MatMul
  /// int8 only, so ≈ 104 MB), pinned to one revision of a public Hugging Face repo by SHA-256.
  /// A development default — production builds set `ASR_MODEL_BASE_URL` (docs/MODELS.md).
  static const interim = AsrModelManifest(
    id: 'tarteel-tiny-int8-interim',
    upstream: _tarteel,
    licence: 'Apache-2.0',
    baseUrl: 'https://huggingface.co/kasimyazan/sherpa-tarteel-whisper-tiny-ar-quran/resolve/cb901509d98460808e448f4c4e2b141e404dc069/',
    files: [
      AsrModelFile(
        AsrFileRole.encoder,
        'tiny-encoder.int8.onnx',
        bytes: 12926487,
        sha256: '75d864b165300880f3b4571d6e50d7d64210e8c6fc5539c3a9fd0e2b4d61361b',
      ),
      AsrModelFile(
        AsrFileRole.decoder,
        'tiny-decoder.int8.onnx',
        bytes: 89846458,
        sha256: '5a26d9ccfd65cdc2be8972290a002616e95832add32ba3f4e03cac91f8b43dcc',
      ),
      AsrModelFile(
        AsrFileRole.tokens,
        'tiny-tokens.txt',
        bytes: 866987,
        sha256: 'febeed8e568f92d9ca984580bc2e6b605b867dc5ba4486f9646de381b44a8226',
      ),
      _vad,
    ],
  );

  /// The model this build downloads.
  static AsrModelManifest get current => Env.asrModelBaseUrl.isEmpty ? interim : yaqeen;
}

// tools/asr/manifest.json (yaqeen-asr-v1) — update together with the hosted files.
const yaqeenEncoderBytes = 12926470;
const yaqeenEncoderSha256 = 'd3b05195086f02c565084638faa1d5d1710b63ea8703201246c9fb4f0207ab42';
const yaqeenDecoderBytes = 30099011;
const yaqeenDecoderSha256 = '2b983686b02c7cad345b2d399aea0180f66e0c754ca5709b1ab5dd0d25f68fe2';
const yaqeenTokensBytes = 866987;
const yaqeenTokensSha256 = 'febeed8e568f92d9ca984580bc2e6b605b867dc5ba4486f9646de381b44a8226';
