/**
 * Builds minimal, structurally valid MPEG-4 audio files (ftyp + moov with one sound track + mdat) for
 * tests: duration, channels, sample rate and audio object type are configurable.
 */
function box(type: string, ...payload: Buffer[]): Buffer {
  const body = Buffer.concat(payload);
  const head = Buffer.alloc(8);
  head.writeUInt32BE(body.length + 8, 0);
  head.write(type, 4, 'latin1');
  return Buffer.concat([head, body]);
}

const u32 = (n: number) => {
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
}

export function buildM4a(o: M4aOptions = {}): Buffer {
  const { durationMs = 12_000, channels = 1, sampleRate = 16_000, aot = 2, payload = 48_000, v1 = false } = o;
  const timescale = sampleRate;
  const duration = Math.round((durationMs / 1000) * timescale);
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
  const stbl = box('stbl', stsd);
  const minf = box('minf', stbl);
  const mdia = box('mdia', mdhd, hdlr, minf);
  const trak = box('trak', mdia);
  const mvhd = box('mvhd', Buffer.alloc(4), u32(0), u32(0), u32(1000), u32(durationMs), Buffer.alloc(80));
  const moov = box('moov', mvhd, trak);
  const mdat = box('mdat', Buffer.alloc(payload, 0x21));
  return Buffer.concat([ftyp, moov, mdat]);
}
