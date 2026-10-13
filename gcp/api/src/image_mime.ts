/** Sniff image bytes — browsers often send application/octet-stream. */
export function sniffImageMime(
  bytes?: Buffer | Uint8Array | null,
  declared?: string | null,
): 'image/jpeg' | 'image/png' | 'image/webp' | 'image/gif' {
  const d = (declared || '').toLowerCase().trim();
  if (
    d === 'image/jpeg' ||
    d === 'image/jpg' ||
    d === 'image/png' ||
    d === 'image/webp' ||
    d === 'image/gif'
  ) {
    return d === 'image/jpg' ? 'image/jpeg' : (d as 'image/jpeg' | 'image/png' | 'image/webp' | 'image/gif');
  }
  if (!bytes || bytes.length < 12) return 'image/jpeg';
  const b = bytes;
  // JPEG
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'image/jpeg';
  // PNG
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) {
    return 'image/png';
  }
  // GIF
  if (b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46) return 'image/gif';
  // WEBP: RIFF....WEBP
  if (
    b[0] === 0x52 &&
    b[1] === 0x49 &&
    b[2] === 0x46 &&
    b[3] === 0x46 &&
    b[8] === 0x57 &&
    b[9] === 0x45 &&
    b[10] === 0x42 &&
    b[11] === 0x50
  ) {
    return 'image/webp';
  }
  return 'image/jpeg';
}
