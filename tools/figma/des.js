// FIA Figma consolidation: DESERIALIZER (runs inside use_figma on the MASTER file; paste as the head of the code).
// Usage: const nodes = await build(DATA, parentNode, false);   DATA = the object ser() produced (or an array form for plain rects).
// Counts what it made into STATS so the caller can compare with the source.
const STATS = {};
const bump = t => { STATS[t] = (STATS[t] || 0) + 1; };
const col = h => ({ r: parseInt(h.slice(0, 2), 16) / 255, g: parseInt(h.slice(2, 4), 16) / 255, b: parseInt(h.slice(4, 6), 16) / 255 });
const AX = ['MIN', 'CENTER', 'MAX', 'SPACE_BETWEEN', 'BASELINE'];
const LM = { H: 'HORIZONTAL', V: 'VERTICAL' };
const SM = { F: 'FIXED', A: 'AUTO' };
const SA = { I: 'INSIDE', C: 'CENTER', O: 'OUTSIDE' };
const TH = { L: 'LEFT', C: 'CENTER', R: 'RIGHT', J: 'JUSTIFIED' };
const TV = { T: 'TOP', C: 'CENTER', B: 'BOTTOM' };
function mkPaint(p) {
  if (p.c !== undefined) return { type: 'SOLID', color: col(p.c), opacity: p.o === undefined ? 1 : p.o };
  if (p.g) return { type: p.g, gradientTransform: p.t, gradientStops: p.s.map(s => ({ position: s[0], color: Object.assign(col(s[1]), { a: s[2] }) })), opacity: p.o === undefined ? 1 : p.o };
  return { type: 'SOLID', color: { r: 1, g: 0, b: 1 }, opacity: 0.2 };
}
function mkEffects(list) {
  return list.map(e => {
    if (e.k === 'D' || e.k === 'I') return { type: e.k === 'D' ? 'DROP_SHADOW' : 'INNER_SHADOW', color: Object.assign(col(e.c), { a: e.a }), offset: { x: e.x, y: e.y }, radius: e.r, spread: e.s || 0, visible: true, blendMode: 'NORMAL' };
    return { type: e.k === 'LB' ? 'LAYER_BLUR' : 'BACKGROUND_BLUR', radius: e.r, visible: true };
  });
}
function collectFonts(o, set) {
  if (Array.isArray(o)) return;
  if (o.sg) for (const s of o.sg) set.add(s.fn[0] + '|' + s.fn[1]);
  if (o.c) for (const c of o.c) collectFonts(c, set);
}
async function loadFonts(data) {
  const set = new Set();
  for (const d of Array.isArray(data) && !isNaN(data[0]) ? [] : (Array.isArray(data) ? data : [data])) collectFonts(d, set);
  for (const k of set) { const [family, style] = k.split('|'); await figma.loadFontAsync({ family, style }); }
}
function place(node, o, parent, inAuto) {
  if (inAuto && !o.ab && !o.m) return;
  if (inAuto && o.ab) node.layoutPositioning = 'ABSOLUTE';
  if (o.m) { node.relativeTransform = o.m; } else { node.x = o.x; node.y = o.y; }
}
function style(node, o) {
  if (o.v === 0) node.visible = false;
  if (o.op !== undefined) node.opacity = o.op;
  if (o.bm) node.blendMode = o.bm;
  if ('fills' in node && o.f && o.T !== 'TEXT') node.fills = o.f.map(mkPaint);
  if (o.sk) {
    node.strokes = o.sk.map(mkPaint);
    node.strokeAlign = SA[o.sa];
    if (o.sw !== undefined) node.strokeWeight = o.sw;
    else if (o.swS) { node.strokeTopWeight = o.swS[0]; node.strokeRightWeight = o.swS[1]; node.strokeBottomWeight = o.swS[2]; node.strokeLeftWeight = o.swS[3]; }
    if (o.sd) node.dashPattern = o.sd;
  }
  if (o.ef) node.effects = mkEffects(o.ef);
  if ('cornerRadius' in node) { if (o.rr) { node.topLeftRadius = o.rr[0]; node.topRightRadius = o.rr[1]; node.bottomRightRadius = o.rr[2]; node.bottomLeftRadius = o.rr[3]; } else if (o.r) node.cornerRadius = o.r; }
  if ('clipsContent' in node) node.clipsContent = !!o.cl;
}
function layout(node, o) {
  if (!o.L) return;
  const L = o.L;
  node.layoutMode = LM[L[0]];
  node.primaryAxisSizingMode = SM[L[1]];
  node.counterAxisSizingMode = SM[L[2]];
  node.itemSpacing = L[3];
  node.paddingTop = L[4]; node.paddingRight = L[5]; node.paddingBottom = L[6]; node.paddingLeft = L[7];
  node.primaryAxisAlignItems = AX[L[8]];
  node.counterAxisAlignItems = AX[L[9]] === 'SPACE_BETWEEN' ? 'MIN' : AX[L[9]];
  if (L[10]) node.layoutWrap = 'WRAP';
}
function sizing(node, o) {
  if (o.lsh) { try { node.layoutSizingHorizontal = o.lsh; } catch (e) { } }
  if (o.lsv) { try { node.layoutSizingVertical = o.lsv; } catch (e) { } }
  if (o.lg) node.layoutGrow = o.lg;
  if (o.la) node.layoutAlign = o.la;
}
async function build(o, parent, inAuto) {
  if (Array.isArray(o)) { // plain rect [x,y,w,h,hex,opacity,name]
    const r = figma.createRectangle(); parent.appendChild(r); r.name = o[6]; r.resize(Math.max(o[2], 0.01), Math.max(o[3], 0.01)); r.x = o[0]; r.y = o[1];
    r.fills = [{ type: 'SOLID', color: col(o[4]), opacity: o[5] }]; bump('R'); return r;
  }
  let node;
  const T = o.T;
  if (T === 'TEXT') {
    node = figma.createText(); parent.appendChild(node);
    const first = o.sg[0];
    node.fontName = { family: first.fn[0], style: first.fn[1] };
    node.characters = o.tx;
    node.textAlignHorizontal = TH[o.ta[0]]; node.textAlignVertical = TV[o.ta[1]];
    for (const s of o.sg) {
      if (s.b <= s.a) continue;
      node.setRangeFontName(s.a, s.b, { family: s.fn[0], style: s.fn[1] });
      node.setRangeFontSize(s.a, s.b, s.fs);
      if (s.f) node.setRangeFills(s.a, s.b, s.f.map(mkPaint));
      if (s.ls) node.setRangeLetterSpacing(s.a, s.b, { unit: s.ls[0] === 'P' ? 'PERCENT' : 'PIXELS', value: s.ls[1] });
      if (s.lh) node.setRangeLineHeight(s.a, s.b, { unit: s.lh[0] === 'P' ? 'PERCENT' : 'PIXELS', value: s.lh[1] });
      if (s.tc) node.setRangeTextCase(s.a, s.b, s.tc);
      if (s.td) node.setRangeTextDecoration(s.a, s.b, s.td);
    }
    node.textAutoResize = o.tr;
    if (o.tr === 'NONE') node.resize(o.w, o.h); else if (o.tr === 'HEIGHT') node.resize(o.w, node.height);
  } else {
    if (T === 'FRAME') node = figma.createFrame();
    else if (T === 'COMPONENT') node = figma.createComponent();
    else if (T === 'RECTANGLE') node = figma.createRectangle();
    else if (T === 'ELLIPSE') node = figma.createEllipse();
    else if (T === 'POLYGON') { node = figma.createPolygon(); node.pointCount = o.pc; }
    else if (T === 'STAR') { node = figma.createStar(); node.pointCount = o.pc; node.innerRadius = o.ir; }
    else if (T === 'VECTOR') node = figma.createVector();
    else if (T === 'CS') node = null; // component sets are assembled below
    else node = figma.createFrame();
    if (node) {
      parent.appendChild(node);
      if (T === 'VECTOR') { node.resize(Math.max(o.w, 0.01), Math.max(o.h, 0.01)); node.vectorPaths = o.vp.map(p => ({ windingRule: p[0], data: p[1] })); }
      else node.resize(Math.max(o.w, 0.01), Math.max(o.h, 0.01));
      if (T === 'ELLIPSE' && o.arc) node.arcData = { startingAngle: o.arc[0], endingAngle: o.arc[1], innerRadius: o.arc[2] };
    }
  }
  if (T === 'CS') { // a component set: build the variants, combine them
    const comps = [];
    for (const c of o.c) comps.push(await build(c, parent, false));
    const set = figma.combineAsVariants(comps, parent);
    set.name = o.n; set.x = o.x; set.y = o.y;
    bump('CS'); return set;
  }
  node.name = o.n;
  if (T !== 'TEXT') layout(node, o);
  style(node, o);
  if (T === 'TEXT' && o.f === undefined) { /* fills come from the segments */ }
  if (o.px) {
    const q = o.px;
    for (let k = 0; k < q.p.length; k++) for (let j = 0; j < q.d[k].length; j += 2) {
      const r = figma.createRectangle(); node.appendChild(r); r.name = q.nm; r.resize(q.w, q.h); r.x = q.d[k][j]; r.y = q.d[k][j + 1];
      r.fills = [{ type: 'SOLID', color: col(q.p[k]) }]; bump('R');
    }
  }
  if (o.c && node.appendChild && T !== 'VECTOR') {
    const auto = !!o.L;
    for (const c of o.c) await build(c, node, auto);
  }
  place(node, o, parent, inAuto);
  if (inAuto) sizing(node, o);
  bump(T);
  return node;
}
