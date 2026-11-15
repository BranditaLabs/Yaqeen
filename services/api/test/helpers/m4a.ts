/**
 * Builds minimal, structurally valid MPEG-4 audio files (ftyp + moov with one sound track + mdat) for
 * tests: duration, channels, sample rate and audio object type are configurable, and the three lengths
 * (header `mdhd`, timing `stts`, frame count `stsz`) can be set apart to forge a file.
 */
export function box(type: string, ...payload: Buffer[]): Buffer {
  const body = Buffer.concat(payload);
  const head = Buffer.alloc(8);
  head.writeUInt32BE(body.length + 8, 0);
  head.write(type, 4, 'latin1');
  return Buffer.concat([head, body]);
}

export const u32 = (n: number) => {
  const b = Buffer.alloc(4);
  b.writeUInt32BE(n >>> 0, 0);
  return b;
};
const u16 = (n: number) => {
  const b = Buffer.alloc(2);
  b.writeUInt16BE(n, 0);
  return b;
};

export interface M4aOptions {
  durationMs?: number;
  channels?: number;
  sampleRate?: number;
  /** MPEG-4 audio object type (2 = AAC-LC). */
  aot?: number;
  /** Bytes of fake audio payload in `mdat`. */
  payload?: number;
  /** Write a 64-bit mdhd (version 1). */
  v1?: boolean;
  /** Forge the `mdhd` header length (default: `durationMs`). */
  headerMs?: number;
  /** Forge the `stts` timing (default: `durationMs`). */
  sttsMs?: number;
  /** Forge the `stsz` frame count (default: enough 1024-sample AAC frames for `durationMs`). */
  frames?: number;
  /** Sound tracks in the file (default 1). */
  soundTracks?: number;
}

/** `stts` entries for `samples` PCM samples in 1024-sample frames (the last one shorter). */
function sttsFor(samples: number): Buffer {
  const full = Math.floor(samples / 1024);
  const rest = samples % 1024;
  const entries = [...(full ? [[full, 1024]] : []), ...(rest ? [[1, rest]] : [])];
  return box('stts', Buffer.alloc(4), u32(entries.length), ...entries.flatMap(([n, d]) => [u32(n!), u32(d!)]));
}

export function buildM4a(o: M4aOptions = {}): Buffer {
  const { durationMs = 12_000, channels = 1, sampleRate = 16_000, aot = 2, payload = 48_000, v1 = false, soundTracks = 1 } = o;
  const timescale = sampleRate;
  const samples = (ms: number) => Math.round((ms / 1000) * timescale);
  const duration = samples(o.headerMs ?? durationMs);
  const frames = o.frames ?? Math.ceil(samples(durationMs) / 1024);
  const ftyp = box('ftyp', Buffer.from('M4A ', 'latin1'), u32(0), Buffer.from('M4A mp42isom', 'latin1'));
  const mdhd = v1
    ? box('mdhd', Buffer.from([1, 0, 0, 0]), Buffer.alloc(16), u32(timescale), Buffer.from([0, 0, 0, 0]), u32(duration), u16(0x55c4), u16(0))
    : box('mdhd', Buffer.from([0, 0, 0, 0]), u32(0), u32(0), u32(timescale), u32(duration), u16(0x55c4), u16(0));
  const hdlr = box('hdlr', Buffer.alloc(4), u32(0), Buffer.from('soun', 'latin1'), Buffer.alloc(12), Buffer.from('SoundHandler\0', 'latin1'));
  // AudioSpecificConfig: 5 bits AOT, 4 bits frequency index (8 = 16 kHz), 4 bits channel config.
  const asc = Buffer.from([(aot << 3) | (8 >> 1), ((8 & 1) << 7) | (channels << 3)]);
  const dsi = Buffer.concat([Buffer.from([0x05, asc.length]), asc]);
  const dcd = Buffer.concat([Buffer.from([0x04, 13 + dsi.length, 0x40, 0x15]), Buffer.alloc(3), u32(32000), u32(32000), dsi]);
  const sl = Buffer.from([0x06, 0x01, 0x02]);
  const esd = Buffer.concat([Buffer.from([0x03, 3 + dcd.length + sl.length]), u16(1), Buffer.from([0]), dcd, sl]);
  const esds = box('esds', Buffer.alloc(4), esd);
  const mp4a = box('mp4a', Buffer.alloc(6), u16(1), Buffer.alloc(8), u16(channels), u16(16), u16(0), u16(0), u32(sampleRate * 65536), esds);
  const stsd = box('stsd', Buffer.alloc(4), u32(1), mp4a);
  const stts = sttsFor(samples(o.sttsMs ?? durationMs));
  // Uniform sample size (no per-sample table): version/flags, sample_size, sample_count.
  const stsz = box('stsz', Buffer.alloc(4), u32(Math.max(1, Math.floor(payload / Math.max(1, frames)))), u32(frames));
  const stbl = box('stbl', stsd, stts, stsz);
  const minf = box('minf', stbl);
  const mdia = box('mdia', mdhd, hdlr, minf);
  const traks = Array.from({ length: soundTracks }, () => box('trak', mdia));
  const mvhd = box('mvhd', Buffer.alloc(4), u32(0), u32(0), u32(1000), u32(durationMs), Buffer.alloc(80));
  const moov = box('moov', mvhd, ...traks);
  const mdat = box('mdat', Buffer.alloc(payload, 0x21));
  return Buffer.concat([ftyp, moov, mdat]);
}
