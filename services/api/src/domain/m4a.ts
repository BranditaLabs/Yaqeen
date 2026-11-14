/**
 * Minimal MPEG-4 audio (.m4a) inspection for uploaded recordings (pure; unit-tested): checks the
 * container (`ftyp`), finds the sound track and reads its channel count and sample rate (`mp4a`), audio
 * object type (`esds` → AAC-LC = 2) and its length three ways — the `mdhd` header field (free for a
 * client to set), the sample table's timing (`stts`: Σ sample_count × sample_delta ÷ timescale, what
 * players follow) and the number of AAC frames (`stsz`/`stz2` sample count, what decoders decode).
 * Nothing is decoded or transcoded. Every read is bounds-checked: a truncated or malformed file is
 * `null`, never a throw.
 */
import { RECORDING_FORMAT } from '@yaqeen/contracts';

export interface M4aInfo {
  /** The length players follow: the sample table's timing (`stts`). */
  durationMs: number;
  /** The `mdhd` header's claim (a client can write anything there). */
  headerDurationMs: number;
  /** Encoded frames (samples of the sound track, `stsz`/`stz2`). */
  frames: number;
  channels: number;
  sampleRate: number;
  /** MPEG-4 Audio Object Type (2 = AAC-LC), null when the `esds` box is missing or unreadable. */
  audioObjectType: number | null;
}

/** PCM samples per AAC-LC frame. */
export const AAC_LC_FRAME_SAMPLES = 1024;

interface Box {
  type: string;
  start: number; // payload start
  end: number; // box end (exclusive)
}

function boxes(buf: Buffer, start: number, end: number): Box[] {
  const out: Box[] = [];
  let p = start;
  while (p + 8 <= end) {
    let size = buf.readUInt32BE(p);
    const type = buf.toString('latin1', p + 4, p + 8);
    let header = 8;
    if (size === 1) {
      if (p + 16 > end) break;
      const big = buf.readBigUInt64BE(p + 8);
      if (big > BigInt(end - p)) break;
      size = Number(big);
      header = 16;
    } else if (size === 0) {
      size = end - p;
    }
    if (size < header || p + size > end) break;
    out.push({ type, start: p + header, end: p + size });
    p += size;
  }
  return out;
}

function find(buf: Buffer, parent: Box, type: string): Box | undefined {
  return boxes(buf, parent.start, parent.end).find((b) => b.type === type);
}

/** The box's payload holds at least `n` bytes (reads within it then stay inside the buffer too). */
const holds = (b: Box, n: number) => b.end - b.start >= n;

/** Read a descriptor length (1–4 bytes, 7 bits each). */
function descLen(buf: Buffer, p: number, end: number): [number, number] {
  let len = 0;
  for (let i = 0; i < 4 && p < end; i++) {
    const b = buf[p++]!;
    len = (len << 7) | (b & 0x7f);
    if ((b & 0x80) === 0) break;
  }
  return [len, p];
}

function audioObjectType(buf: Buffer, esds: Box): number | null {
  let p = esds.start + 4; // version + flags
  const end = esds.end;
  if (p >= end || buf[p] !== 0x03) return null;
  let len: number;
  [len, p] = descLen(buf, p + 1, end);
  const esEnd = Math.min(end, p + len);
  if (p + 3 > esEnd) return null;
  const flags = buf[p + 2]!;
  p += 3;
  if (flags & 0x80) p += 2; // dependsOn_ES_ID
  if (flags & 0x40) p += 1 + (buf[p] ?? 0); // URL
  if (flags & 0x20) p += 2; // OCR_ES_Id
  if (p >= esEnd || buf[p] !== 0x04) return null;
  [len, p] = descLen(buf, p + 1, esEnd);
  if (p >= esEnd) return null;
  const objectType = buf[p]!;
  if (objectType !== 0x40) return null; // MPEG-4 Audio
  p += 13;
  if (p >= esEnd || buf[p] !== 0x05) return null;
  [len, p] = descLen(buf, p + 1, esEnd);
  if (len < 1 || p >= esEnd) return null;
  const aot = buf[p]! >> 3;
  return aot === 31 && p + 1 < esEnd ? 32 + (((buf[p]! & 0x07) << 3) | (buf[p + 1]! >> 5)) : aot;
}

/** Σ sample_count × sample_delta of an `stts` box, or null when its entry table is cut short. */
function sttsTicks(buf: Buffer, stts: Box): number | null {
  if (!holds(stts, 8)) return null;
  const n = buf.readUInt32BE(stts.start + 4);
  if (!holds(stts, 8 + n * 8)) return null;
  let ticks = 0;
  for (let i = 0; i < n; i++) {
    const at = stts.start + 8 + i * 8;
    ticks += buf.readUInt32BE(at) * buf.readUInt32BE(at + 4);
  }
  return ticks;
}

/** Sample count of an `stsz` (or compact `stz2`) box: both keep it at payload offset 8. */
function sampleCount(buf: Buffer, stsz: Box): number | null {
  return holds(stsz, 12) ? buf.readUInt32BE(stsz.start + 8) : null;
}

function inspect(buf: Buffer): M4aInfo | null {
  if (buf.length < 16) return null;
  const top = boxes(buf, 0, buf.length);
  if (top[0]?.type !== 'ftyp') return null;
  const moov = top.find((b) => b.type === 'moov');
  if (!moov) return null;
  const sound = boxes(buf, moov.start, moov.end)
    .filter((b) => b.type === 'trak')
    .map((trak) => find(buf, trak, 'mdia'))
    .filter((mdia): mdia is Box => {
      const hdlr = mdia && find(buf, mdia, 'hdlr');
      return !!hdlr && holds(hdlr, 12) && buf.toString('latin1', hdlr.start + 8, hdlr.start + 12) === 'soun';
    });
  // Exactly one sound track (what the app records): a second one could carry other audio for players.
  const mdia = sound.length === 1 ? sound[0]! : null;
  if (!mdia) return null;
  const mdhd = find(buf, mdia, 'mdhd');
  const minf = find(buf, mdia, 'minf');
  const stbl = minf && find(buf, minf, 'stbl');
  const stsd = stbl && find(buf, stbl, 'stsd');
  const stts = stbl && find(buf, stbl, 'stts');
  const stsz = stbl && (find(buf, stbl, 'stsz') ?? find(buf, stbl, 'stz2'));
  if (!mdhd || !stsd || !stts || !stsz || !holds(mdhd, 4)) return null;
  const v = buf[mdhd.start]!;
  let timescale: number;
  let duration: number;
  if (v === 1) {
    if (!holds(mdhd, 32)) return null;
    timescale = buf.readUInt32BE(mdhd.start + 20);
    duration = Number(buf.readBigUInt64BE(mdhd.start + 24));
  } else {
    if (!holds(mdhd, 20)) return null;
    timescale = buf.readUInt32BE(mdhd.start + 12);
    duration = buf.readUInt32BE(mdhd.start + 16);
  }
  if (!timescale) return null;
  const ticks = sttsTicks(buf, stts);
  const frames = sampleCount(buf, stsz);
  if (ticks === null || frames === null || !holds(stsd, 8)) return null;
  const entries = boxes(buf, stsd.start + 8, stsd.end);
  const mp4a = entries.find((e) => e.type === 'mp4a');
  if (!mp4a || !holds(mp4a, 28)) return null;
  const channels = buf.readUInt16BE(mp4a.start + 16);
  const sampleRate = buf.readUInt32BE(mp4a.start + 24) >>> 16;
  const esds = boxes(buf, mp4a.start + 28, mp4a.end).find((b) => b.type === 'esds');
  return {
    durationMs: Math.round((ticks / timescale) * 1000),
    headerDurationMs: Math.round((duration / timescale) * 1000),
    frames,
    channels,
    sampleRate,
    audioObjectType: esds ? audioObjectType(buf, esds) : null,
  };
}

/** Parse an .m4a; null when it is not an MPEG-4 file with a readable sound track (never throws). */
export function inspectM4a(buf: Buffer): M4aInfo | null {
  try {
    return inspect(buf);
  } catch {
    return null; // a malformed box the bounds checks did not foresee: not our format
  }
}

/** The contract's format: AAC-LC, mono, 16 kHz. */
export function matchesRecordingFormat(info: M4aInfo): boolean {
  return info.channels === RECORDING_FORMAT.channels && info.sampleRate === RECORDING_FORMAT.sampleRate && info.audioObjectType === 2;
}

/**
 * The lengths of an AAC-LC recording and whether the file agrees with itself: the decoded length
 * (frames × 1024 ÷ sample rate), the players' timing (`stts`) and the header (`mdhd`) must lie within
 * `toleranceMs` (+ one frame) of each other. `longestMs` is the longest of the three — what the limit is
 * checked against, so a forged header (or timing table) cannot make a long clip pass as short;
 * `durationMs` is the players' timing (what is stored and shown).
 */
export function durations(info: M4aInfo, toleranceMs: number): { durationMs: number; longestMs: number; consistent: boolean } {
  const frameMs = info.sampleRate > 0 ? (AAC_LC_FRAME_SAMPLES / info.sampleRate) * 1000 : 0;
  const all = [info.durationMs, info.headerDurationMs, Math.round(info.frames * frameMs)];
  const longestMs = Math.max(...all);
  return { durationMs: info.durationMs, longestMs, consistent: longestMs - Math.min(...all) <= toleranceMs + Math.ceil(frameMs) };
}
