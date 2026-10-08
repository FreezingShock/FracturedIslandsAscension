// FIA Figma consolidation: SERIALIZER (runs inside use_figma on a SOURCE file; paste as the head of the code, then call ser(node)).
// Compact JSON of a node subtree: frames/text/vectors/rects/ellipses/polygons, solid + gradient fills, strokes, shadows, auto layout.
// Instances are flattened into frames (name kept in `ins`). Components / component sets are kept (`C`, `CS`).
const r3 = v => Math.round(v * 1000) / 1000;
const hex = c => ((1 << 24) | (Math.round(c.r * 255) << 16) | (Math.round(c.g * 255) << 8) | Math.round(c.b * 255)).toString(16).slice(1);
const AL = { MIN: 0, CENTER: 1, MAX: 2, SPACE_BETWEEN: 3, BASELINE: 4 };
function paint(p) {
  if (p.visible === false) return null;
  if (p.type === 'SOLID') { const o = { c: hex(p.color) }; const op = p.opacity === undefined ? 1 : p.opacity; if (op !== 1) o.o = r3(op); return o; }
  if (p.type.startsWith('GRADIENT')) {
    const o = { g: p.type, t: p.gradientTransform.map(row => row.map(r3)), s: p.gradientStops.map(s => [r3(s.position), hex(s.color), r3(s.color.a)]) };
    if (p.opacity !== undefined && p.opacity !== 1) o.o = r3(p.opacity);
    return o;
  }
  return { img: 1 };
}
function paints(arr) { if (!Array.isArray(arr)) return undefined; const out = arr.map(paint).filter(Boolean); return out.length ? out : undefined; }
function effects(arr) {
  const out = [];
  for (const e of arr || []) {
    if (e.visible === false) continue;
    if (e.type === 'DROP_SHADOW' || e.type === 'INNER_SHADOW') out.push({ k: e.type === 'DROP_SHADOW' ? 'D' : 'I', c: hex(e.color), a: r3(e.color.a), x: e.offset.x, y: e.offset.y, r: e.radius, s: e.spread || 0 });
    else if (e.type === 'LAYER_BLUR' || e.type === 'BACKGROUND_BLUR') out.push({ k: e.type === 'LAYER_BLUR' ? 'LB' : 'BB', r: e.radius });
  }
  return out.length ? out : undefined;
}
function isPlainRect(n) {
  if (n.type !== 'RECTANGLE') return false;
  if (n.rotation || n.visible === false || n.opacity !== 1 || n.blendMode !== 'PASS_THROUGH' && n.blendMode !== 'NORMAL') return false;
  if (n.strokes.length || n.effects.length) return false;
  if (n.cornerRadius !== 0) return false;
  const f = n.fills;
  if (!Array.isArray(f) || f.length !== 1 || f[0].type !== 'SOLID' || f[0].visible === false) return false;
  return true;
}
// A run of >= 6 plain same-size rects that never overlap (pixel art) is packed as { px: { w, h, nm, p: [hex...], d: [[x,y,x,y...]...] } }.
function pack(list) {
  if (list.length < 6 || !list.every(i => Array.isArray(i))) return null;
  const w = list[0][2], h = list[0][3];
  if (!list.every(i => i[2] === w && i[3] === h)) return null;
  const seen = new Set();
  for (const i of list) { const k = i[0] + ',' + i[1]; if (seen.has(k)) return null; seen.add(k); }
  for (let a = 0; a < list.length; a++) for (let b = a + 1; b < list.length; b++) if (Math.abs(list[a][0] - list[b][0]) < w && Math.abs(list[a][1] - list[b][1]) < h) return null;
  if (!list.every(i => i[5] === 1)) return null;
  const pal = [], d = [];
  for (const i of list) { let k = pal.indexOf(i[4]); if (k < 0) { k = pal.length; pal.push(i[4]); d.push([]); } d[k].push(i[0], i[1]); }
  return { w, h, nm: list[0][6], p: pal, d };
}
function ser(n, inAuto) {
  if (isPlainRect(n) && !inAuto) { const f = n.fills[0]; return [r3(n.x), r3(n.y), r3(n.width), r3(n.height), hex(f.color), f.opacity === undefined ? 1 : r3(f.opacity), n.name]; }
  const o = { n: n.name, T: n.type };
  const lin = n.relativeTransform;
  if (n.rotation) o.m = lin.map(row => row.map(r3)); else { o.x = r3(n.x); o.y = r3(n.y); }
  o.w = r3(n.width); o.h = r3(n.height);
  if (n.visible === false) o.v = 0;
  if (n.opacity !== 1) o.op = r3(n.opacity);
  if (n.blendMode !== 'PASS_THROUGH' && n.blendMode !== 'NORMAL') o.bm = n.blendMode;
  if ('layoutPositioning' in n && n.layoutPositioning === 'ABSOLUTE') o.ab = 1;
  if (inAuto) { o.lsh = n.layoutSizingHorizontal; o.lsv = n.layoutSizingVertical; if (n.layoutGrow) o.lg = n.layoutGrow; if (n.layoutAlign && n.layoutAlign !== 'INHERIT') o.la = n.layoutAlign; }
  if ('fills' in n) { const f = paints(n.fills); if (f) o.f = f; else o.f = []; }
  if ('strokes' in n && n.strokes.length) {
    o.sk = paints(n.strokes); o.sa = n.strokeAlign[0];
    if (typeof n.strokeWeight === 'number') o.sw = n.strokeWeight; else o.swS = [n.strokeTopWeight, n.strokeRightWeight, n.strokeBottomWeight, n.strokeLeftWeight];
    if (n.dashPattern && n.dashPattern.length) o.sd = n.dashPattern;
  }
  if ('effects' in n) { const e = effects(n.effects); if (e) o.ef = e; }
  if ('cornerRadius' in n) { if (n.cornerRadius === figma.mixed) o.rr = [n.topLeftRadius, n.topRightRadius, n.bottomRightRadius, n.bottomLeftRadius]; else if (n.cornerRadius) o.r = n.cornerRadius; }
  if ('clipsContent' in n && n.clipsContent) o.cl = 1;
  if (n.type === 'ELLIPSE') { const a = n.arcData; if (a.startingAngle !== 0 || a.endingAngle !== Math.PI * 2 || a.innerRadius) o.arc = [r3(a.startingAngle), r3(a.endingAngle), r3(a.innerRadius)]; }
  if (n.type === 'POLYGON') o.pc = n.pointCount;
  if (n.type === 'STAR') { o.pc = n.pointCount; o.ir = n.innerRadius; }
  if (n.type === 'VECTOR' || n.type === 'BOOLEAN_OPERATION' && 0) o.vp = n.vectorPaths.map(p => [p.windingRule, p.data]);
  if (n.type === 'BOOLEAN_OPERATION') o.bo = n.booleanOperation;
  if (n.type === 'TEXT') {
    o.tx = n.characters; o.ta = [n.textAlignHorizontal[0], n.textAlignVertical[0]]; o.tr = n.textAutoResize;
    const segs = n.getStyledTextSegments(['fontName', 'fontSize', 'fills', 'letterSpacing', 'lineHeight', 'textCase', 'textDecoration']);
    o.sg = segs.map(s => ({ a: s.start, b: s.end, fn: [s.fontName.family, s.fontName.style], fs: s.fontSize, f: paints(s.fills), ls: s.letterSpacing.value ? [s.letterSpacing.unit[0], r3(s.letterSpacing.value)] : undefined, lh: s.lineHeight.unit === 'AUTO' ? undefined : [s.lineHeight.unit[0], r3(s.lineHeight.value)], tc: s.textCase !== 'ORIGINAL' ? s.textCase : undefined, td: s.textDecoration !== 'NONE' ? s.textDecoration : undefined }));
    delete o.f;
  }
  if (n.type === 'COMPONENT_SET') { o.T = 'CS'; }
  if (n.type === 'INSTANCE') { o.T = 'FRAME'; o.ins = n.mainComponent ? n.mainComponent.name : ''; }
  if ('layoutMode' in n && n.layoutMode !== 'NONE') {
    o.L = [n.layoutMode[0], n.primaryAxisSizingMode[0], n.counterAxisSizingMode[0], n.itemSpacing, n.paddingTop, n.paddingRight, n.paddingBottom, n.paddingLeft, AL[n.primaryAxisAlignItems], AL[n.counterAxisAlignItems], n.layoutWrap === 'WRAP' ? 1 : 0];
  }
  if ('children' in n && n.type !== 'VECTOR' && n.type !== 'BOOLEAN_OPERATION') {
    const auto = 'layoutMode' in n && n.layoutMode !== 'NONE';
    const kids = n.children.map(c => ser(c, auto));
    const px = auto ? null : pack(kids);
    if (px) o.px = px; else o.c = kids;
  }
  return o;
}

// ---- chunking: use_figma returns at most 20480 bytes, so a big tree is cut into chunks of <= LIM chars; a cut child is replaced by { r: id }.
// readGroup(roots, g): serialize `roots` (nodes), return { g, total, chunks: [{ r, d }...] } for group g (groups are <= GROUP chars). The root of root k is chunk id R[k].
function plan(roots) {
  const LIM = 16000, chunks = [], rootRefs = [];
  function emit(o) {
    if (Array.isArray(o)) return o;
    let size = JSON.stringify(o).length;
    if (size <= LIM) return o;
    if (o.c) { for (let i = 0; i < o.c.length; i++) o.c[i] = emit(o.c[i]); }
    const id = chunks.length; chunks.push({ r: id, d: o }); return { r: id };
  }
  for (const n of roots) { const t = emit(ser(n, false)); if (t.r === undefined) { const id = chunks.length; chunks.push({ r: id, d: t }); rootRefs.push(id); } else rootRefs.push(t.r); }
  const GROUP = 19000, groups = [[]]; let cur = 0;
  for (const c of chunks) { const l = JSON.stringify(c).length; if (cur + l > GROUP && groups[groups.length - 1].length) { groups.push([]); cur = 0; } groups[groups.length - 1].push(c); cur += l; }
  return { groups, rootRefs };
}
