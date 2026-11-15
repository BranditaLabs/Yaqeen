/**
 * A small multipart/form-data parser for the one upload route that needs it (POST /v1/me/recordings:
 * a JSON `meta` part and an `audio` file part, ≤ 256 KB together). The body arrives as a Buffer; no
 * streaming, no temp files, no dependency.
 */
export interface Part {
  name: string;
  filename: string | null;
  contentType: string | null;
  data: Buffer;
}

export function boundaryOf(contentType: string | undefined): string | null {
  const m = /boundary=(?:"([^"]+)"|([^;]+))/i.exec(contentType ?? '');
  const b = m?.[1] ?? m?.[2]?.trim();
  return b && b.length <= 200 ? b : null;
}

/** Parse the parts; null when the body is not well-formed multipart for this boundary. */
export function parseMultipart(body: Buffer, boundary: string): Part[] | null {
  const delim = Buffer.from(`--${boundary}`, 'latin1');
  const parts: Part[] = [];
  let pos = body.indexOf(delim);
  if (pos < 0) return null;
  for (;;) {
    pos += delim.length;
    // "--" after a delimiter closes the body.
    if (body[pos] === 0x2d && body[pos + 1] === 0x2d) return parts;
    if (body[pos] === 0x0d && body[pos + 1] === 0x0a) pos += 2;
    else return null;
    const headerEnd = body.indexOf('\r\n\r\n', pos, 'latin1');
    if (headerEnd < 0) return null;
    const headers = body.toString('utf8', pos, headerEnd).split('\r\n');
    const next = body.indexOf(Buffer.concat([Buffer.from('\r\n', 'latin1'), delim]), headerEnd + 4);
    if (next < 0) return null;
    let name: string | null = null;
    let filename: string | null = null;
    let contentType: string | null = null;
    for (const h of headers) {
      const [k, ...rest] = h.split(':');
      const v = rest.join(':').trim();
      if (k!.trim().toLowerCase() === 'content-disposition') {
        name = /\bname="([^"]*)"/i.exec(v)?.[1] ?? null;
        filename = /\bfilename="([^"]*)"/i.exec(v)?.[1] ?? null;
      } else if (k!.trim().toLowerCase() === 'content-type') {
        contentType = v.toLowerCase();
      }
    }
    if (name === null) return null;
    parts.push({ name, filename, contentType, data: body.subarray(headerEnd + 4, next) });
    if (parts.length > 8) return null;
    pos = next + 2;
  }
}

/** Build a multipart body (tests and tooling). */
export function buildMultipart(boundary: string, parts: { name: string; filename?: string; contentType?: string; data: Buffer | string }[]): Buffer {
  const chunks: Buffer[] = [];
  for (const p of parts) {
    let head = `--${boundary}\r\nContent-Disposition: form-data; name="${p.name}"${p.filename ? `; filename="${p.filename}"` : ''}\r\n`;
    if (p.contentType) head += `Content-Type: ${p.contentType}\r\n`;
    chunks.push(Buffer.from(`${head}\r\n`, 'utf8'), Buffer.isBuffer(p.data) ? p.data : Buffer.from(p.data, 'utf8'), Buffer.from('\r\n', 'latin1'));
  }
  chunks.push(Buffer.from(`--${boundary}--\r\n`, 'latin1'));
  return Buffer.concat(chunks);
}
