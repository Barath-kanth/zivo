/** Single grouped-bar SVG for the eval slice. No dependencies. */
type Rate = { precision?: number | null; recall?: number | null };
type Input = {
  safety: { gemini: Record<string, Rate>; keyword: Record<string, Rate> };
  translation: Record<string, { rate: number | null }>;
  voice: Record<string, { acc: number | null }>;
};

const SERIES = [
  { key: 'en', label: 'English', color: '#4285F4' },
  { key: 'ta', label: 'Tamil', color: '#EA4335' },
  { key: 'si', label: 'Sinhala', color: '#34A853' },
  { key: 'all', label: 'All', color: '#202124' },
] as const;

export function renderChart(d: Input): string {
  const groups: { title: string; sub: string; vals: Record<string, number | null> }[] = [
    {
      title: 'Safety block precision', sub: 'Zivo (Gemini)',
      vals: Object.fromEntries(SERIES.map((s) => [s.key, d.safety.gemini[s.key]?.precision ?? null])),
    },
    {
      title: 'Safety block recall', sub: 'Zivo (Gemini)',
      vals: Object.fromEntries(SERIES.map((s) => [s.key, d.safety.gemini[s.key]?.recall ?? null])),
    },
    {
      title: 'Safety block recall', sub: 'keyword lexicon alone (baseline)',
      vals: Object.fromEntries(SERIES.map((s) => [s.key, d.safety.keyword[s.key]?.recall ?? null])),
    },
    {
      title: 'Translation checks', sub: 'all 5 checks pass / message',
      vals: Object.fromEntries(SERIES.map((s) => [s.key, d.translation[s.key]?.rate ?? null])),
    },
    {
      title: 'Voice → task', sub: 'category accuracy (synthetic audio)',
      vals: Object.fromEntries(SERIES.map((s) => [s.key, d.voice[s.key]?.acc ?? null])),
    },
  ];

  const W = 1180, H = 620, L = 70, R = 30, T = 90, B = 150;
  const plotW = W - L - R, plotH = H - T - B;
  const gw = plotW / groups.length;
  const bw = Math.min(34, (gw - 36) / SERIES.length);
  const y = (v: number) => T + plotH * (1 - v);
  let s = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" font-family="Inter,Helvetica,Arial,sans-serif">`;
  s += `<rect width="${W}" height="${H}" fill="#fff"/>`;
  s += `<text x="${L}" y="38" font-size="22" font-weight="700" fill="#202124">Zivo evaluation slice — 30 utterances × (English · Tamil · Sinhala)</text>`;
  s += `<text x="${L}" y="62" font-size="13" fill="#5f6368">Live Cloud Run API + Vertex AI Gemini · single run · team-authored labels · smoke test, not a benchmark</text>`;
  for (const t of [0, 0.25, 0.5, 0.75, 1]) {
    s += `<line x1="${L}" x2="${W - R}" y1="${y(t)}" y2="${y(t)}" stroke="#e8eaed"/>`;
    s += `<text x="${L - 10}" y="${y(t) + 4}" font-size="12" text-anchor="end" fill="#5f6368">${Math.round(t * 100)}%</text>`;
  }
  groups.forEach((g, gi) => {
    const x0 = L + gi * gw + (gw - bw * SERIES.length) / 2;
    SERIES.forEach((se, si) => {
      const v = g.vals[se.key];
      const x = x0 + si * bw;
      if (v == null) {
        s += `<rect x="${x + 3}" y="${y(0) - 22}" width="${bw - 6}" height="22" fill="none" stroke="#9aa0a6" stroke-dasharray="3 3"/>`;
        s += `<text x="${x + bw / 2}" y="${y(0) - 7}" font-size="10" text-anchor="middle" fill="#9aa0a6">n/a</text>`;
        return;
      }
      s += `<rect x="${x + 2}" y="${y(v)}" width="${bw - 4}" height="${Math.max(1, y(0) - y(v))}" fill="${se.color}" rx="3"/>`;
      s += `<text x="${x + bw / 2}" y="${y(v) - 6}" font-size="12" font-weight="600" text-anchor="middle" fill="#202124">${Math.round(v * 100)}</text>`;
    });
    const cx = L + gi * gw + gw / 2;
    s += `<text x="${cx}" y="${y(0) + 24}" font-size="14" font-weight="700" text-anchor="middle" fill="#202124">${g.title}</text>`;
    s += `<text x="${cx}" y="${y(0) + 42}" font-size="12" text-anchor="middle" fill="#5f6368">${g.sub}</text>`;
  });
  SERIES.forEach((se, i) => {
    const x = L + i * 120;
    s += `<rect x="${x}" y="${H - 52}" width="14" height="14" fill="${se.color}" rx="3"/>`;
    s += `<text x="${x + 20}" y="${H - 40}" font-size="13" fill="#202124">${se.label}</text>`;
  });
  s += `<rect x="${L + 4 * 120}" y="${H - 52}" width="14" height="14" fill="none" stroke="#9aa0a6" stroke-dasharray="3 3"/>`;
  s += `<text x="${L + 4 * 120 + 20}" y="${H - 40}" font-size="13" fill="#5f6368">not measured (no Sinhala voice fixtures)</text>`;
  s += `<text x="${L}" y="${H - 14}" font-size="11" fill="#80868b">Dev items were used to tune the lexicon/prompt; see docs/EVALUATION.md for the 6-item held-out split. Voice: English + Tamil only.</text>`;
  s += `</svg>`;
  return s;
}
