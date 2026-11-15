#!/usr/bin/env python3
"""Builds Yaqeen's on-device recitation model (docs/MODELS.md) from pinned upstream sources.

    py -3.13 tools/asr/convert.py --out build/asr        # needs tools/asr/requirements.txt

Steps (every download is pinned to a revision and checked against its SHA-256):
  1. tarteel-ai/whisper-tiny-ar-quran (Apache-2.0) at UPSTREAM_REVISION: config.json + pytorch_model.bin.
  2. The Hugging Face checkpoint is mapped onto openai-whisper's module names (strict load: every
     tensor must land, nothing may be left over).
  3. sherpa-onnx's own Whisper exporter (scripts/whisper/export-onnx.py at SHERPA_COMMIT, Apache-2.0)
     writes the encoder/decoder ONNX graphs + metadata that the sherpa-onnx runtime in the app reads.
  4. int8 dynamic quantisation. sherpa's script quantises MatMul only, and its decoder computes the
     logits as MatMul(Identity(W), xᵀ) — the 51 865 x 384 token embedding W is the *first* input, which
     ONNX Runtime does not treat as a weight, so W stays fp32 (~80 MB of the ~90 MB decoder). We rewrite
     the logits as MatMul(x, Wᵀ) (checked equal to the export on random input), quantise every MatMul,
     and point the token lookup at the same int8 Wᵀ (Gather → Transpose → DequantizeLinear): one int8
     embedding instead of fp32. Result ≈ 13 MB encoder + ≈ 30 MB decoder.
  5. Silero VAD (MIT) at its pinned sherpa-onnx release asset, used by the app to cut speech segments.
  6. A smoke test: the int8 pair decodes a synthetic clip through sherpa-onnx (Python), same runtime
     and settings as the app.
  7. manifest.json: file names, byte sizes, SHA-256 — copy the values into
     apps/mobile/lib/core/platform/asr/asr_model.dart (`AsrModelManifest.yaqeen`) and upload the
     three files to ASR_MODEL_BASE_URL.

Nothing here is shipped in the app bundle and no model binary is ever committed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import runpy
import shutil
import sys
from pathlib import Path

import requests

UPSTREAM_REPO = "tarteel-ai/whisper-tiny-ar-quran"
UPSTREAM_REVISION = "c3d7e624af5c81bef25a10a2af3a5a84cb4dd0f0"
UPSTREAM_FILES = {
    # name: sha256 (the LFS oid for the weights)
    "pytorch_model.bin": "f26c96202427524ec015bcf25bd932414df0474e538d765c16759f1095757688",
    "config.json": "4aa68ebec1ca833b4c28a7be8f595fa6e7493ef3b1587e2d60f6d811087ed3fa",
}

SHERPA_COMMIT = "7be9a38e275ece9ee9a9277cc78295f2cbfd6673"
SHERPA_EXPORT_SHA256 = "5e0ddabfac8330ee9aecaba4c1b4286d1cd9f88df4cd30e54706b011bf976e45"

SILERO_URL = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx"
SILERO_SHA256 = "9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6"

MODEL_ID = "yaqeen-asr-v1"


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch(url: str, target: Path, sha256: str | None) -> Path:
    if target.exists() and (sha256 is None or sha256_of(target) == sha256):
        return target
    target.parent.mkdir(parents=True, exist_ok=True)
    print(f"download {url}")
    with requests.get(url, stream=True, timeout=60) as r:
        r.raise_for_status()
        tmp = target.with_suffix(target.suffix + ".part")
        with tmp.open("wb") as f:
            for chunk in r.iter_content(1 << 20):
                f.write(chunk)
        tmp.replace(target)
    got = sha256_of(target)
    if sha256 is not None and got != sha256:
        target.unlink()
        raise SystemExit(f"checksum mismatch for {url}: {got} != {sha256}")
    print(f"  sha256 {got}")
    return target


# Hugging Face Whisper → openai-whisper parameter names (applied in order).
HF_TO_OPENAI = [
    (".self_attn.q_proj", ".attn.query"),
    (".self_attn.k_proj", ".attn.key"),
    (".self_attn.v_proj", ".attn.value"),
    (".self_attn.out_proj", ".attn.out"),
    (".self_attn_layer_norm", ".attn_ln"),
    (".encoder_attn.q_proj", ".cross_attn.query"),
    (".encoder_attn.k_proj", ".cross_attn.key"),
    (".encoder_attn.v_proj", ".cross_attn.value"),
    (".encoder_attn.out_proj", ".cross_attn.out"),
    (".encoder_attn_layer_norm", ".cross_attn_ln"),
    (".final_layer_norm", ".mlp_ln"),
    (".fc1", ".mlp.0"),
    (".fc2", ".mlp.2"),
    (".layers.", ".blocks."),
    ("encoder.layer_norm.", "encoder.ln_post."),
    ("decoder.layer_norm.", "decoder.ln."),
    ("decoder.embed_tokens.", "decoder.token_embedding."),
    ("encoder.embed_positions.weight", "encoder.positional_embedding"),
    ("decoder.embed_positions.weight", "decoder.positional_embedding"),
]


def hf_to_openai(config: dict, state: dict):
    import torch  # noqa: F401
    from whisper.model import ModelDimensions, Whisper

    dims = ModelDimensions(
        n_mels=config["num_mel_bins"],
        n_audio_ctx=config["max_source_positions"],
        n_audio_state=config["d_model"],
        n_audio_head=config["encoder_attention_heads"],
        n_audio_layer=config["encoder_layers"],
        n_vocab=config["vocab_size"],
        n_text_ctx=config["max_target_positions"],
        n_text_state=config["d_model"],
        n_text_head=config["decoder_attention_heads"],
        n_text_layer=config["decoder_layers"],
    )
    mapped = {}
    for key, value in state.items():
        if key == "proj_out.weight":
            continue  # tied to the token embedding
        k = key.removeprefix("model.")
        for a, b in HF_TO_OPENAI:
            k = k.replace(a, b)
        mapped[k] = value
    model = Whisper(dims)
    model.load_state_dict(mapped, strict=True)
    model.eval()
    return model


def quantize(src: Path, dst: Path, ops: list[str]) -> None:
    from onnxruntime.quantization import QuantType, quantize_dynamic

    quantize_dynamic(model_input=str(src), model_output=str(dst), op_types_to_quantize=ops, weight_type=QuantType.QInt8)


EMBEDDING = "textDecoder.token_embedding.weight"
EMBEDDING_T = EMBEDDING + "_t"


def _consumers(m):
    out = {}
    for n in m.graph.node:
        for i in n.input:
            out.setdefault(i, []).append(n)
    return out


def logits_as_weight_matmul(src: Path, dst: Path) -> None:
    """Rewrites the logits so the embedding is a quantisable MatMul weight.

    The exported decoder computes `Transpose(MatMul(Identity(W), Transpose(x)))` (W = 51 865 x 384).
    ONNX Runtime's dynamic quantiser only treats a MatMul's second input as a weight, so W stayed
    fp32. Equivalent graph: `MatMul(x, W_T)` with W_T = Wᵀ as its own initializer.
    """
    import onnx
    from onnx import helper, numpy_helper

    m = onnx.load(str(src))
    inits = {i.name: i for i in m.graph.initializer}
    prod = {o: n for n in m.graph.node for o in n.output}
    # Identity(initializer) → the initializer itself.
    rename = {n.output[0]: n.input[0] for n in m.graph.node if n.op_type == "Identity" and n.input[0] in inits}
    for n in m.graph.node:
        for k, name in enumerate(n.input):
            if name in rename:
                n.input[k] = rename[name]
    nodes = [n for n in m.graph.node if not (n.op_type == "Identity" and n.output[0] in rename)]
    del m.graph.node[:]
    m.graph.node.extend(nodes)
    cons = _consumers(m)
    mm = next(n for n in m.graph.node if n.op_type == "MatMul" and n.input[0] == EMBEDDING)
    pre = prod[mm.input[1]]
    post = cons[mm.output[0]]
    perm = lambda n: next((list(a.ints) for a in n.attribute if a.name == "perm"), None)  # noqa: E731
    if pre.op_type != "Transpose" or perm(pre) != [0, 2, 1] or len(post) != 1 or post[0].op_type != "Transpose" or perm(post[0]) != [0, 2, 1]:
        raise SystemExit("unexpected logits subgraph; update logits_as_weight_matmul for this exporter")
    w = numpy_helper.to_array(inits[EMBEDDING])
    m.graph.initializer.append(numpy_helper.from_array(w.T.copy(), EMBEDDING_T))
    new = helper.make_node("MatMul", [pre.input[0], EMBEDDING_T], [post[0].output[0]], name="logits_matmul")
    drop = {id(mm), id(post[0])}
    if len(cons[pre.output[0]]) == 1:
        drop.add(id(pre))
    nodes = []
    for n in m.graph.node:
        if id(n) == id(mm):
            nodes.append(new)
        elif id(n) not in drop:
            nodes.append(n)
    del m.graph.node[:]
    m.graph.node.extend(nodes)
    onnx.save(m, str(dst))


def share_int8_embedding(src: Path, dst: Path) -> None:
    """Token lookup from the logits MatMul's int8 Wᵀ: Gather(axis=1) → Transpose → DequantizeLinear.

    One int8 copy of the embedding (≈ 20 MB) instead of fp32 (≈ 80 MB); the fp32 W is dropped.
    """
    import onnx
    from onnx import helper, numpy_helper

    m = onnx.load(str(src))
    inits = {i.name: i for i in m.graph.initializer}
    q, s, z = EMBEDDING_T + "_quantized", EMBEDDING_T + "_scale", EMBEDDING_T + "_zero_point"
    if q not in inits or s not in inits or z not in inits:
        raise SystemExit(f"expected {q} / {s} / {z} after MatMul quantisation")
    if numpy_helper.to_array(inits[q]).dtype.name != "int8" or numpy_helper.to_array(inits[s]).size != 1:
        raise SystemExit("embedding must be per-tensor int8")
    nodes = []
    for n in m.graph.node:
        if n.op_type == "Gather" and n.input[0] == EMBEDDING:
            out = n.output[0]
            base = n.name or out
            # Wᵀ is (384, V): gather the token columns → (384, batch, tokens) → (batch, tokens, 384).
            nodes.append(helper.make_node("Gather", [q, n.input[1]], [out + "_int8"], axis=1, name=base + "_int8"))
            nodes.append(helper.make_node("Transpose", [out + "_int8"], [out + "_int8_t"], perm=[1, 2, 0], name=base + "_t"))
            nodes.append(helper.make_node("DequantizeLinear", [out + "_int8_t", s, z], [out], name=base + "_dequant"))
        else:
            nodes.append(n)
    del m.graph.node[:]
    m.graph.node.extend(nodes)
    used = {i for n in m.graph.node for i in n.input}
    for name in (EMBEDDING, EMBEDDING_T):
        if name in used:
            raise SystemExit(f"{name} (fp32) still used")
    keep = [i for i in m.graph.initializer if i.name not in (EMBEDDING, EMBEDDING_T)]
    del m.graph.initializer[:]
    m.graph.initializer.extend(keep)
    onnx.checker.check_model(m)
    onnx.save(m, str(dst))


def equivalence_check(reference: Path, candidate: Path) -> float:
    """Max |Δ| between the fp32 decoder and the rewritten graph (before quantisation) on random input."""
    import numpy as np
    import onnxruntime as ort

    a = ort.InferenceSession(str(reference), providers=["CPUExecutionProvider"])
    b = ort.InferenceSession(str(candidate), providers=["CPUExecutionProvider"])
    rng = np.random.default_rng(0)
    feeds = {}
    for i in a.get_inputs():
        shape = [d if isinstance(d, int) else 1 for d in i.shape]
        if "tokens" in i.name:
            feeds[i.name] = np.array([[50258, 50259, 50359]], dtype=np.int64)
        elif "offset" in i.name:
            feeds[i.name] = np.array([0], dtype=np.int64)
        else:
            if "cross" in i.name:
                shape[2] = 1500
            feeds[i.name] = rng.standard_normal(shape).astype(np.float32) * 0.1
    ra = a.run(["logits"], feeds)[0]
    rb = b.run(["logits"], feeds)[0]
    return float(np.max(np.abs(ra - rb)))


def smoke_test(encoder: Path, decoder: Path, tokens: Path) -> str:
    import numpy as np
    import sherpa_onnx

    rec = sherpa_onnx.OfflineRecognizer.from_whisper(
        encoder=str(encoder), decoder=str(decoder), tokens=str(tokens), language="ar", task="transcribe", num_threads=2
    )
    t = np.arange(16000 * 2) / 16000.0
    samples = (0.05 * np.sin(2 * np.pi * 220 * t)).astype(np.float32)  # a tone: only checks the graph runs
    s = rec.create_stream()
    s.accept_waveform(16000, samples)
    rec.decode_stream(s)
    return s.result.text


def main() -> None:
    # sherpa's exporter writes language lists from Python sets: a fixed hash seed makes the ONNX
    # metadata (and so every file's SHA-256) the same on each run.
    if os.environ.get("PYTHONHASHSEED") != "0":
        import subprocess

        raise SystemExit(subprocess.run([sys.executable, *sys.argv], env={**os.environ, "PYTHONHASHSEED": "0"}).returncode)
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=Path("build/asr"))
    ap.add_argument("--cache", type=Path, default=Path("tools/asr/.cache"))
    args = ap.parse_args()
    out: Path = args.out.resolve()
    cache: Path = args.cache.resolve()
    work = cache / "work"
    work.mkdir(parents=True, exist_ok=True)
    out.mkdir(parents=True, exist_ok=True)

    # 1 · upstream checkpoint
    files = {}
    for name, sha in UPSTREAM_FILES.items():
        url = f"https://huggingface.co/{UPSTREAM_REPO}/resolve/{UPSTREAM_REVISION}/{name}"
        files[name] = fetch(url, cache / "upstream" / UPSTREAM_REVISION / name, sha)
    exporter = fetch(
        f"https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/{SHERPA_COMMIT}/scripts/whisper/export-onnx.py",
        cache / "sherpa" / SHERPA_COMMIT / "export-onnx.py",
        SHERPA_EXPORT_SHA256,
    )

    # 2 · HF → openai-whisper
    import torch
    import whisper

    config = json.loads(files["config.json"].read_text(encoding="utf-8"))
    state = torch.load(files["pytorch_model.bin"], map_location="cpu", weights_only=True)
    model = hf_to_openai(config, state)
    print(f"loaded {UPSTREAM_REPO}@{UPSTREAM_REVISION[:8]}: {model.dims}")

    # 3 · sherpa-onnx export, with our model in place of whisper.load_model("tiny")
    whisper.load_model = lambda *_a, **_k: model  # type: ignore[assignment]
    cwd = Path.cwd()
    try:
        os.chdir(work)
        sys.argv = [str(exporter), "--model", "tiny"]
        runpy.run_path(str(exporter), run_name="__main__")
    finally:
        os.chdir(cwd)

    # 4 · int8: every MatMul, and one int8 embedding shared with the token lookup
    encoder = out / f"{MODEL_ID}-encoder.int8.onnx"
    decoder = out / f"{MODEL_ID}-decoder.int8.onnx"
    tokens = out / f"{MODEL_ID}-tokens.txt"
    shutil.copyfile(work / "tiny-encoder.int8.onnx", encoder)
    logits_as_weight_matmul(work / "tiny-decoder.onnx", work / "decoder.wt.onnx")
    delta = equivalence_check(work / "tiny-decoder.onnx", work / "decoder.wt.onnx")
    print(f"rewritten decoder ≡ exported (max |Δlogits| {delta:.2e})")
    if delta > 1e-3:
        raise SystemExit("rewritten decoder differs from the export")
    quantize(work / "decoder.wt.onnx", work / "decoder.wt.int8.onnx", ["MatMul"])
    share_int8_embedding(work / "decoder.wt.int8.onnx", decoder)
    shutil.copyfile(work / "tiny-tokens.txt", tokens)

    # 5 · VAD
    vad = fetch(SILERO_URL, out / "silero_vad.onnx", SILERO_SHA256)

    # 6 · smoke test (same runtime as the app)
    print("smoke test:", repr(smoke_test(encoder, decoder, tokens)))

    # 7 · manifest
    manifest = {
        "id": MODEL_ID,
        "upstream": {"repo": UPSTREAM_REPO, "revision": UPSTREAM_REVISION, "licence": "Apache-2.0"},
        "exporter": {"repo": "k2-fsa/sherpa-onnx", "commit": SHERPA_COMMIT, "licence": "Apache-2.0"},
        "vad": {"url": SILERO_URL, "licence": "MIT"},
        "files": [
            {"role": role, "name": p.name, "bytes": p.stat().st_size, "sha256": sha256_of(p)}
            for role, p in (("encoder", encoder), ("decoder", decoder), ("tokens", tokens), ("vad", vad))
        ],
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    total = sum(f["bytes"] for f in manifest["files"])
    print(json.dumps(manifest, indent=2))
    print(f"total {total / 1e6:.1f} MB → {out}")


if __name__ == "__main__":
    main()
