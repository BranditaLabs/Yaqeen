/**
 * Minimal MPEG-4 audio (.m4a) inspection for uploaded recordings (pure; unit-tested): checks the
 * container (`ftyp`), finds the sound track and reads its duration (`mdhd`), channel count and sample
 * rate (`mp4a`) and audio object type (`esds` → AAC-LC = 2). Nothing is decoded or transcoded.
 */
import { RECORDING_FORMAT } from '@yaqeen/contracts';

export interface M4aInfo {
  durationMs: number;
  channels: number;
  sampleRate: number;
  /** MPEG-4 Audio Object Type (2 = AAC-LC), null when the `esds` box is missing or unreadable. */
  audioObjectType: number | null;
}

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
  if (buf[p] !== 0x03) return null;
  let len: number;
  [len, p] = descLen(buf, p + 1, end);
  const esEnd = Math.min(end, p + len);
  const flags = buf[p + 2]!;
  p += 3;
  if (flags & 0x80) p += 2; // dependsOn_ES_ID
  if (flags & 0x40) p += 1 + buf[p]!; // URL
  if (flags & 0x20) p += 2; // OCR_ES_Id
  if (buf[p] !== 0x04) return null;
  [len, p] = descLen(buf, p + 1, esEnd);
  const objectType = buf[p]!;
  if (objectType !== 0x40) return null; // MPEG-4 Audio
  p += 13;
  if (buf[p] !== 0x05) return null;
  [len, p] = descLen(buf, p + 1, esEnd);
  if (len < 1 || p >= esEnd) return null;
  const aot = buf[p]! >> 3;
  return aot === 31 && p + 1 < esEnd ? 32 + (((buf[p]! & 0x07) << 3) | (buf[p + 1]! >> 5)) : aot;
}

/** Parse an .m4a; null when it is not an MPEG-4 file with a readable sound track. */
export function inspectM4a(buf: Buffer): M4aInfo | null {
  if (buf.length < 16) return null;
  const top = boxes(buf, 0, buf.length);
  if (top[0]?.type !== 'ftyp') return null;
  const moov = top.find((b) => b.type === 'moov');
  if (!moov) return null;
  for (const trak of boxes(buf, moov.start, moov.end).filter((b) => b.type === 'trak')) {
    const mdia = find(buf, trak, 'mdia');
    if (!mdia) continue;
    const hdlr = find(buf, mdia, 'hdlr');
    if (!hdlr || buf.toString('latin1', hdlr.start + 8, hdlr.start + 12) !== 'soun') continue;
    const mdhd = find(buf, mdia, 'mdhd');
    const minf = find(buf, mdia, 'minf');
    const stbl = minf && find(buf, minf, 'stbl');
    const stsd = stbl && find(buf, stbl, 'stsd');
    if (!mdhd || !stsd) return null;
    const v = buf[mdhd.start]!;
    let timescale: number;
    let duration: number;
    if (v === 1) {
      timescale = buf.readUInt32BE(mdhd.start + 20);
      duration = Number(buf.readBigUInt64BE(mdhd.start + 24));
    } else {
      timescale = buf.readUInt32BE(mdhd.start + 12);
      duration = buf.readUInt32BE(mdhd.start + 16);
    }
    if (!timescale) return null;
    const entries = boxes(buf, stsd.start + 8, stsd.end);
    const mp4a = entries.find((e) => e.type === 'mp4a');
    if (!mp4a || mp4a.start + 28 > mp4a.end) return null;
    const channels = buf.readUInt16BE(mp4a.start + 16);
    const sampleRate = buf.readUInt32BE(mp4a.start + 24) >>> 16;
    const esds = boxes(buf, mp4a.start + 28, mp4a.end).find((b) => b.type === 'esds');
    let aot: number | null = null;
    try {
      aot = esds ? audioObjectType(buf, esds) : null;
    } catch {
      aot = null;
    }
    return { durationMs: Math.round((duration / timescale) * 1000), channels, sampleRate, audioObjectType: aot };
  }
  return null;
}


/** The contract's format: AAC-LC, mono, 16 kHz. */
export function matchesRecordingFormat(info: M4aInfo): boolean {
  return info.channels === RECORDING_FORMAT.channels && info.sampleRate === RECORDING_FORMAT.sampleRate && info.audioObjectType === 2;
}

