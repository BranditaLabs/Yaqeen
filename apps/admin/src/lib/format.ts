/** Western digits everywhere (product rule), Arabic text. */
const nf = new Intl.NumberFormat('en-US');
export const num = (n: number) => nf.format(n);
export const pct = (n: number) => `${n.toFixed(1)}%`;

const df = new Intl.DateTimeFormat('ar-EG-u-nu-latn', { day: 'numeric', month: 'short', year: 'numeric' });
const dtf = new Intl.DateTimeFormat('ar-EG-u-nu-latn', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
export const date = (iso: string | Date) => df.format(new Date(iso));
export const dateTime = (iso: string | Date) => dtf.format(new Date(iso));

/** "2026-10-23T10:30" interpreted in `timeZone` → ISO UTC string (DST-safe). */
export function zonedLocalToIso(local: string, timeZone = 'Africa/Cairo'): string {
  const asUtc = Date.parse(`${local}:00Z`);
  const offsetAt = (t: number) => {
    const p = Object.fromEntries(
      new Intl.DateTimeFormat('en-US', { timeZone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit' })
        .formatToParts(new Date(t))
        .map((x) => [x.type, x.value]),
    );
    return Date.UTC(+p.year!, +p.month! - 1, +p.day!, +p.hour!, +p.minute!, +p.second!) - t;
  };
  const first = asUtc - offsetAt(asUtc);
  return new Date(asUtc - offsetAt(first)).toISOString();
}
