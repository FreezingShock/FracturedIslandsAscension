"""Procedural stylized oak for Roblox (run inside Blender via the Blender MCP: exec(open(path).read())).

Builds painterly leaf atlas + ridged bark (+normal map), then the trunk/roots/branches and double-sided
leaf-puff cards. Outputs PNGs next to OUT. Tune the PARAMS block, re-run, screenshot.
"""
import bpy, bmesh, math, random
import numpy as np
from mathutils import Vector, Matrix, Euler

OUT = "C:/Users/natea/Documents/Roblox Game Development/Fractured Islands Ascension/assets/blender/tree_oak"
SEED = globals().get("SEED_OVERRIDE", 12)
OFFSET = globals().get("OFFSET_OVERRIDE", (0.0, 0.0, 0.0))   # where this tree is placed
TAG = globals().get("TAG_OVERRIDE", "")                      # suffix for object/mesh names so several trees can coexist
CLEAR = globals().get("CLEAR_OVERRIDE", True)                # remove existing meshes first (False to add another tree)
REGEN = globals().get("REGEN_OVERRIDE", True)                # rebuild the leaf atlas / reload bark (False = reuse what's loaded)
VARY = globals().get("VARY_OVERRIDE", False)                 # randomise crown layout, lean and trunk height from SEED
# ---- PARAMS ----
CANOPY_Z = 5.5                      # canopy centre height
CANOPY_RADII = (3.2, 3.2, 2.35)      # ellipsoid radii (x, y, z): wide, slightly flattened sphere
# shells: (radius fraction, coverage factor, card size)
SHELLS = ((1.00, 2.5, 1.9, 'all'), (0.86, 1.5, 2.1, 'all'), (0.66, 1.0, 2.5, 'all'), (0.40, 0.5, 2.5, 'all'),
          (1.00, 1.2, 1.7, 'top'))   # last: extra top-only layer
STICK_COVER = 1.1                   # coverage of the sticking-out cluster layer
ROUGH = 1.8                         # outline roughness multiplier
HT = 3.0                 # trunk height to the fork
CARD_DENSITY = 11        # cards per R^2 per puff
GAP_FREE_FRAC = 0.2      # fraction of freely oriented cards
LEAF_STRIPES = 300       # leaves painted per lump in the atlas

def save_img(name, arr, path, noncolor=False):
    h, w, _ = arr.shape
    if name in bpy.data.images: bpy.data.images.remove(bpy.data.images[name])
    img = bpy.data.images.new(name, w, h, alpha=True)
    if noncolor: img.colorspace_settings.name = 'Non-Color'
    img.pixels.foreach_set(np.ascontiguousarray(arr[::-1]).astype(np.float32).ravel())
    img.filepath_raw = path; img.file_format = 'PNG'; img.save(); return img

# ---------------- leaf atlas ----------------
STOPS = np.array([0.0, 0.38, 0.72, 1.0])
COLS = np.array([[0.05,0.22,0.22],[0.18,0.44,0.14],[0.52,0.74,0.21],[0.80,0.92,0.40]])
def ramp_arr(s):
    s = np.clip(s, 0, 1)
    return np.stack([np.interp(s, STOPS, COLS[:,c]) for c in range(3)], -1)

def leaf_cell(S, seed, bias, warm):
    rng = np.random.default_rng(seed)
    rgb = np.zeros((S,S,3), np.float32); a = np.zeros((S,S), np.float32)
    yy, xx = np.mgrid[0:S,0:S].astype(np.float32); c = S/2
    lumps = []
    for _ in range(6):
        ang = rng.uniform(0, 2*np.pi); d = rng.uniform(0.0, 0.13)*S
        lumps.append((c + d*np.cos(ang), c + 0.8*d*np.sin(ang) + 0.02*S, rng.uniform(0.17, 0.225)*S))
    lumps.sort(key=lambda l: -l[1])
    for (lx, ly, lr) in lumps:
        dd = np.hypot(xx-lx, (yy-ly)*1.05)/lr
        core = np.clip((0.55-dd)*lr*0.35, 0, 1)
        ht = np.clip(0.5+0.5*(ly-yy)/lr, 0, 1); top = np.clip((0.92-yy/S)/0.8, 0, 1)
        col = ramp_arr((0.5*ht+0.5*top)*0.75 - 0.12 + bias)
        rgb = rgb*(1-core[...,None]) + col*core[...,None]; a = a + core*(1-a)
        for _ in range(LEAF_STRIPES):
            th = rng.uniform(0, 2*np.pi); rr = lr*1.05*rng.uniform(0,1)**0.8
            cx = lx + rr*np.cos(th); cy = ly + rr*np.sin(th)*0.95
            rot = rng.uniform(0, np.pi); edge = rr/(lr*1.05)
            Lh = S*rng.uniform(0.055, 0.085)*(1.0-0.28*edge); W = Lh*0.42
            x0, x1 = int(max(cx-Lh,0)), int(min(cx+Lh+2,S)); y0, y1 = int(max(cy-Lh,0)), int(min(cy+Lh+2,S))
            if x1<=x0 or y1<=y0: continue
            dx = xx[y0:y1,x0:x1]-cx; dy = yy[y0:y1,x0:x1]-cy
            u = dx*np.cos(rot)+dy*np.sin(rot); v = -dx*np.sin(rot)+dy*np.cos(rot)
            halfw = (W/2)*np.clip(1-np.abs(2*u/Lh)**1.5, 0, None)
            m = np.clip((halfw-np.abs(v))*1.6, 0, 1); m[np.abs(u) > Lh/2] = 0
            if m.max() <= 0: continue
            hl = np.clip(0.5+0.5*(ly-cy)/lr, 0, 1); tg = np.clip((0.92-cy/S)/0.8, 0, 1)
            s = (0.5*hl+0.5*tg)*0.95 + bias + rng.normal(0, 0.11) + 0.10*np.clip(u/Lh+0.5,0,1)
            colr = ramp_arr(np.full(m.shape, s))*(0.94+0.12*rng.random())
            if warm: colr = colr + np.array([0.04,0.02,-0.03])
            mm = m[...,None]
            rgb[y0:y1,x0:x1] = rgb[y0:y1,x0:x1]*(1-mm) + colr*mm
            a[y0:y1,x0:x1] = a[y0:y1,x0:x1] + m*(1-a[y0:y1,x0:x1])
    mean = (rgb*a[...,None]).sum((0,1))/max(a.sum(),1)
    rgb = rgb*a[...,None] + mean[None,None,:]*(1-a[...,None])
    return np.clip(rgb,0,1), np.clip(a*1.6,0,1)

if REGEN or "leaves_atlas" not in bpy.data.images:
    S = 512
    atlas = np.zeros((S*2,S*2,4), np.float32)
    for k,(seed,bias,warm) in enumerate([(401,0.0,False),(402,0.05,False),(403,0.20,True),(404,-0.22,False)]):
        r, al = leaf_cell(S, seed, bias, warm)
        row, col = divmod(k, 2)
        atlas[row*S:(row+1)*S, col*S:(col+1)*S, :3] = r; atlas[row*S:(row+1)*S, col*S:(col+1)*S, 3] = al
    save_img("leaves_atlas", atlas, OUT+"/leaves_atlas.png")

# ---------------- bark: stylised fantasy bark (muted warm grey-brown with violet shadows, painterly bands) ----------------
def _pnoise(S_, sx, sy, seed_):
    r = np.random.default_rng(seed_).standard_normal((S_, S_))
    fy = np.fft.fftfreq(S_)[:,None]; fx = np.fft.fftfreq(S_)[None,:]
    n = np.fft.ifft2(np.fft.fft2(r)*np.exp(-((fx*sx)**2+(fy*sy)**2))).real
    return (n-n.min())/(n.max()-n.min())
def make_bark(B=1024):
    rid = lambda sx, sy, sd: 1 - np.abs(2*_pnoise(B, sx, sy, sd)-1)
    h = 0.38*rid(36, 220, 41) + 0.26*rid(20, 120, 42) + 0.20*rid(10, 70, 45) + 0.10*rid(5, 38, 46) + 0.06*_pnoise(B, 10, 50, 43)   # long fibrous ridges, coarse to fine
    yy_, xx_ = np.mgrid[0:B, 0:B].astype(np.float32)/B
    lat = np.sin(2*np.pi*(xx_*4 + yy_*2))*np.sin(2*np.pi*(xx_*4 - yy_*2))                  # faint diamond lattice (tileable)
    h = 0.94*h + 0.06*(lat*0.5 + 0.5)
    lo, hi = np.percentile(h, [2, 98]); h = np.clip((h-lo)/(hi-lo), 0, 1)
    q = np.floor(h*5 + 0.5)/5                                                              # painterly steps, softened
    hp = 0.6*h + 0.4*q
    stops = np.array([0.0, 0.30, 0.62, 0.88, 1.0])
    cols = np.array([[0.09,0.065,0.08],[0.22,0.15,0.115],[0.36,0.255,0.18],[0.51,0.385,0.27],[0.66,0.53,0.38]])
    tone = 0.92 + 0.16*_pnoise(B, 22, 130, 44)[..., None]
    rgb = np.stack([np.interp(hp, stops, cols[:,c]) for c in range(3)], -1)*tone
    img_ = np.concatenate([np.clip(rgb, 0, 1), np.ones((B, B, 1))], -1)
    gx = (np.roll(h,-1,1)-np.roll(h,1,1))*0.5; gr = (np.roll(h,-1,0)-np.roll(h,1,0))*0.5
    nx_, ny_ = -gx*7.0, gr*7.0; nz_ = np.ones_like(h); L_ = np.sqrt(nx_**2+ny_**2+nz_**2)
    nm_ = np.stack([nx_/L_*0.5+0.5, ny_/L_*0.5+0.5, nz_/L_*0.5+0.5, np.ones_like(h)], -1)
    return img_, nm_
import os as _os
if REGEN or not _os.path.exists(OUT + "/bark_stylized.png"):
    _c, _n = make_bark()
    save_img("bark_stylized_tmp", _c, OUT + "/bark_stylized.png"); save_img("bark_stylized_n_tmp", _n, OUT + "/bark_stylized_normal.png", noncolor=True)
    for _t in ("bark_stylized_tmp", "bark_stylized_n_tmp"):
        if _t in bpy.data.images: bpy.data.images.remove(bpy.data.images[_t])
if REGEN or "bark" not in bpy.data.images:
    for nm_ in ("bark", "bark_normal"):
        if nm_ in bpy.data.images: bpy.data.images.remove(bpy.data.images[nm_])
    _bd = bpy.data.images.load(OUT + "/bark_stylized.png", check_existing=False); _bd.name = "bark"; _bd.colorspace_settings.name = 'sRGB'
    _bn = bpy.data.images.load(OUT + "/bark_stylized_normal.png", check_existing=False); _bn.name = "bark_normal"; _bn.colorspace_settings.name = 'Non-Color'
    _bd.pack(); _bn.pack()

# ---------------- geometry ----------------
random.seed(SEED)
if CLEAR:
    for o in list(bpy.data.objects):
        if o.type == 'MESH': bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes): bpy.data.meshes.remove(m)
LEAN = 1.0
if VARY:
    LEAN = random.choice((-1.0, 1.0))                  # which way the trunk leans (crowns mirror with it)
    HT = HT*random.uniform(0.88, 1.18)                 # trunk height
rotz = lambda v, a: Matrix.Rotation(a, 3, 'Z') @ v

random_lean_amt = 0.50*(random.uniform(0.6, 1.5) if VARY else 1.0)
def sway(z):
    k = min(max(z, 0)/HT, 1.3)
    return Vector((LEAN*random_lean_amt*k**1.6, 0.14*math.sin(z*1.1)*k, z))

# ---------------- crowns: separate foliage masses at different heights ----------------
CROWNS = [((0.6, 0.0, 6.5), (2.6, 2.5, 2.0)),      # top crown, rises above the rest
          ((-2.8, 0.8, 4.6), (2.6, 2.3, 1.9)),     # left
          ((3.3, -0.6, 4.9), (2.6, 2.3, 1.9)),     # right
          ((1.5, -2.7, 4.0), (2.1, 2.0, 1.5))]     # low front crown
if VARY:                                               # every seed gets its own crown layout
    _u = random.uniform(0.85, 1.15); _new = []
    for (c, r) in CROWNS:
        _new.append(((LEAN*c[0] + random.uniform(-0.8, 0.8), c[1] + random.uniform(-0.8, 0.8), c[2]*HT/3.0*0.5 + c[2]*0.5 + random.uniform(-0.5, 0.5)),
                     (r[0]*_u*random.uniform(0.9, 1.1), r[1]*_u*random.uniform(0.9, 1.1), r[2]*random.uniform(0.88, 1.12))))
    if random.random() < 0.35 and len(_new) > 3: _new.pop()           # sometimes only three crowns
    CROWNS = _new

# ---------------- skeleton: ONE connected graph (roots, trunk, limbs, branches, sticks) ----------------
SK_P, SK_R, SK_PAR, SK_BR, SK_TH, SK_RT = [], [], [], [], [], []
_br = [0]; _thick = [True]; _rootflag = [False]
def sk_add(pos, rad, parent, br):
    SK_P.append(Vector(pos)); SK_R.append(rad); SK_PAR.append(parent); SK_BR.append(br); SK_TH.append(_thick[0]); SK_RT.append(_rootflag[0]); return len(SK_P) - 1
def sk_branch(): _br[0] += 1; return _br[0] - 1
def sk_grow(parent, d, length, r0, r1, steps, bend=0.12, up=0.03, kink=0.0, pw=1.0):
    br = sk_branch(); d = d.normalized(); p = SK_P[parent].copy(); prev = parent; idx = []
    ki = random.randint(1, max(1, steps-1)) if kink > 0 else -1
    for i in range(1, steps + 1):
        d = (d + Vector((random.gauss(0,bend), random.gauss(0,bend), random.gauss(0,bend)*0.6 + up))).normalized()
        if i == ki: d = (d + Vector((random.gauss(0,kink), random.gauss(0,kink), random.gauss(0,kink)*0.5))).normalized()
        p = p + d*(length/steps)
        prev = sk_add(p, r0 + (r1 - r0)*(i/steps)**pw, prev, br); idx.append(prev)
    return idx
def sk_limb(parent, T, r0, r1, steps=7):
    br = sk_branch(); P0 = SK_P[parent]; prev = parent; idx = []
    for j in range(1, steps + 1):
        u = j/steps; p = P0.lerp(T, u)
        p.z += 0.55*math.sin(math.pi*0.5*u)*(1 - u)                      # leaves the trunk heading up, then eases to the crown
        if j < steps: p += Vector((random.gauss(0,0.07), random.gauss(0,0.07), random.gauss(0,0.04)))
        prev = sk_add(p, r1 + (r0 - r1)*(1 - u)**0.8, prev, br); idx.append(prev)
    return idx
def node_dir(i):
    par = SK_PAR[i]; return (SK_P[i] - SK_P[par]).normalized() if par is not None else Vector((0,0,1))

# trunk: widely spaced nodes (the Skin modifier needs spacing comparable to the radius for a thick trunk)
TRUNK = []; _tb = sk_branch(); _prev = None
for z, r in ((-0.40, 1.10), (0.45, 0.86), (1.25, 0.70), (1.90, 0.63), (2.45, 0.57), (HT, 0.52)):
    _prev = sk_add(sway(z), r, _prev, _tb); TRUNK.append(_prev)
def trunk_near(z): return min(TRUNK, key=lambda i: abs(SK_P[i].z - z))

# roots: short, thick where they leave the trunk, curving down into the ground (unevenly spaced so they look grown, not stamped)
_root_az = [0.15, 1.45, 2.55, 3.85, 5.05]
ROOT_PATHS = []                                   # (points, radii) -> closed tubes, merged into the trunk by the voxel remesh
_rootflag[0] = True
for i in range(5):
    az = _root_az[i] + random.uniform(-0.30, 0.30)
    reach = random.uniform(0.85, 1.25)
    dist = [0.45*reach, 0.90*reach, 1.30*reach, 1.60*reach]; zz = [0.80, 0.42, 0.04, -0.28]; rr = [0.50, 0.38, 0.27, 0.17]
    wob = random.uniform(-0.25, 0.25)
    br = sk_branch(); prev = TRUNK[1]; pts = [SK_P[TRUNK[1]] + Vector((0, 0, 0.45))]; rads = [0.52]     # first point sits inside the trunk
    for k in range(4):
        pos = (SK_P[TRUNK[1]].x + math.cos(az + wob*k/3)*dist[k], SK_P[TRUNK[1]].y + math.sin(az + wob*k/3)*dist[k], zz[k])
        prev = sk_add(pos, rr[k], prev, br); pts.append(Vector(pos)); rads.append(rr[k])
    ROOT_PATHS.append((pts, rads))
_rootflag[0] = False

# limbs -> crowns. Three leave the trunk at staggered heights (no node ever has more than 3 connections, so the skin builds clean topology);
# the fourth branches off the second limb near its base, the way a real secondary leader does.
def _rdir():
    return Vector((random.gauss(0,1), random.gauss(0,1), random.gauss(0,1))).normalized()
LIMBS = []
for ci, (cc, cr) in enumerate(CROWNS):
    C0 = Vector(cc)
    if ci == 0: start = TRUNK[-1]
    elif ci == 1: start = trunk_near(2.4)
    elif ci == 2: start = trunk_near(1.9)
    else: start = LIMBS[2][1]
    P0 = SK_P[start]
    T = C0 - (C0 - P0).normalized()*0.2 + Vector((0, 0, -0.3))
    LIMBS.append(sk_limb(start, T, 0.40 - 0.04*ci, 0.14, 6))
TW = []
# each limb splits into three much thinner branches that stay inside the canopy (they never reach the surface)
_thick[0] = False
for ci, (cc, cr) in enumerate(CROWNS):
    C0 = Vector(cc); Rv = Vector(cr); limb = LIMBS[ci]
    for k in (2, 3, 4):
        par = limb[k]
        for _try in range(12):
            dn = _rdir(); dn.z = abs(dn.z)*0.6 + dn.z*0.4
            tgt = C0 + Vector((dn.x*Rv.x, dn.y*Rv.y, dn.z*Rv.z))*random.uniform(0.25, 0.55)
            if (tgt - SK_P[par]).length > 0.9: break
        d0 = tgt - SK_P[par]
        sk_grow(par, d0, d0.length, 0.085, 0.03, 2, bend=0.08, up=0.0)

# ---------------- skeleton -> continuous mesh ----------------
# thick wood (trunk, roots, limbs): Skin -> subdivide -> voxel remesh (smooth union, uniform triangles, no pinched joints) -> decimate
# thin branches inside the canopy: plain Skin + subdivide, merged in
def _eval(ob):
    bpy.context.view_layer.update()
    return bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
segs_ = [i for i in range(len(SK_P)) if SK_PAR[i] is not None]
A_ = np.array([tuple(SK_P[SK_PAR[i]]) for i in segs_]); B_ = np.array([tuple(SK_P[i]) for i in segs_])
AB_ = B_ - A_; AB2_ = (AB_*AB_).sum(1); RA_ = np.array([SK_R[SK_PAR[i]] for i in segs_]); RB_ = np.array([SK_R[i] for i in segs_])
def _vert_w(p_):                              # 1 on thick wood, 0 on thin parts (they would shrink)
    d_ = p_ - A_; t_ = np.clip((d_*AB_).sum(1)/AB2_, 0, 1); cp_ = A_ + AB_*t_[:, None]
    dist_ = np.linalg.norm(p_ - cp_, axis=1); rat_ = RA_ + (RB_ - RA_)*t_
    k_ = int(np.argmin(dist_/np.maximum(rat_, 0.02)))
    return float(np.clip((rat_[k_] - 0.16)/0.25, 0, 1))
def relax_mesh(me, iters):                    # smooth out kinks, waists and stretched joints
    bm_ = bmesh.new(); bm_.from_mesh(me); bm_.verts.ensure_lookup_table()
    W_ = [_vert_w(np.array(tuple(v.co))) for v in bm_.verts]
    for _ in range(iters):
        new_ = {}
        for v in bm_.verts:
            w = W_[v.index]
            if w <= 0: continue
            nb = [e.other_vert(v).co for e in v.link_edges]
            if nb: new_[v.index] = v.co.lerp(sum(nb, Vector())/len(nb), 0.5*w)
        for i, c in new_.items(): bm_.verts[i].co = c
    bm_.to_mesh(me); bm_.free()
RELAX = globals().get("RELAX_OVERRIDE", 6)
def tube_mesh(pts, rads, segs=10):               # closed tapered tube (end caps) so the voxel remesh treats it as solid
    n = len(pts); tans = []
    for i in range(n):
        a_ = pts[max(i-1, 0)]; b_ = pts[min(i+1, n-1)]; tans.append((b_ - a_).normalized())
    nv = tans[0].cross(Vector((0.31, 0.77, 0.55))).normalized(); verts = []; rings = []
    for i in range(n):
        t = tans[i]; nv = (nv - t*nv.dot(t)).normalized(); bv = t.cross(nv); ring = []
        for j in range(segs):
            th = 2*math.pi*j/segs; ring.append(len(verts)); verts.append(tuple(pts[i] + (nv*math.cos(th) + bv*math.sin(th))*rads[i]))
        rings.append(ring)
    faces = []
    for i in range(n-1):
        for j in range(segs):
            faces.append((rings[i][j], rings[i][(j+1) % segs], rings[i+1][(j+1) % segs], rings[i+1][j]))
    c0 = len(verts); verts.append(tuple(pts[0] - tans[0]*0.02)); c1 = len(verts); verts.append(tuple(pts[-1] + tans[-1]*0.02))
    for j in range(segs):
        faces.append((c0, rings[0][(j+1) % segs], rings[0][j])); faces.append((c1, rings[-1][j], rings[-1][(j+1) % segs]))
    me = bpy.data.meshes.new("rt_tmp"); me.from_pydata(verts, [], faces); me.update(); return me
def _union_remesh(base, extras, voxel):
    verts = [tuple(v.co) for v in base.vertices]; faces = [tuple(p_.vertices) for p_ in base.polygons]
    for ex in extras:
        off = len(verts); verts += [tuple(v.co) for v in ex.vertices]; faces += [tuple(i + off for i in p_.vertices) for p_ in ex.polygons]
        bpy.data.meshes.remove(ex)
    comb = bpy.data.meshes.new("comb_tmp"); comb.from_pydata(verts, [], faces); comb.update()
    ob = bpy.data.objects.new("comb_tmp", comb); bpy.context.collection.objects.link(ob)
    rm_ = ob.modifiers.new("Remesh", 'REMESH'); rm_.mode = 'VOXEL'; rm_.voxel_size = voxel; rm_.use_smooth_shade = True
    out = _eval(ob); bpy.data.objects.remove(ob, do_unlink=True); bpy.data.meshes.remove(comb); bpy.data.meshes.remove(base)
    return out
def skin_mesh(nodes, radius_of, roots, remesh=None, ratio=None, levels=1, extras_fn=None):
    idx = {n: i for i, n in enumerate(nodes)}
    me = bpy.data.meshes.new("sk_tmp")
    me.from_pydata([tuple(SK_P[n]) for n in nodes], [(idx[n], idx[SK_PAR[n]]) for n in nodes if SK_PAR[n] in idx], [])
    ob = bpy.data.objects.new("sk_tmp", me); bpy.context.collection.objects.link(ob)
    m = ob.modifiers.new("Skin", 'SKIN'); m.branch_smoothing = 0.9; m.use_smooth_shade = True
    for n in nodes: me.skin_vertices[0].data[idx[n]].radius = (radius_of[n], radius_of[n])
    for r_ in roots: me.skin_vertices[0].data[idx[r_]].use_root = True
    if levels > 0:
        sm_ = ob.modifiers.new("Subsurf", 'SUBSURF'); sm_.levels = levels; sm_.render_levels = levels
    out = _eval(ob); bpy.data.objects.remove(ob, do_unlink=True); bpy.data.meshes.remove(me)
    if remesh:
        out = _union_remesh(out, extras_fn() if extras_fn else [], remesh)
        if RELAX > 0: relax_mesh(out, RELAX)
    if ratio is not None and ratio < 1.0:
        ob2 = bpy.data.objects.new("sk_tmp2", out); bpy.context.collection.objects.link(ob2)
        d_ = ob2.modifiers.new("Decimate", 'DECIMATE'); d_.decimate_type = 'COLLAPSE'; d_.ratio = ratio
        out2 = _eval(ob2); bpy.data.objects.remove(ob2, do_unlink=True); bpy.data.meshes.remove(out); out = out2
    return out
_tris = lambda m_: sum(len(p_.vertices) - 2 for p_ in m_.polygons)

THICK_NODES = [i for i in range(len(SK_P)) if SK_TH[i] and not SK_RT[i]]
THIN_NODES = [i for i in range(len(SK_P)) if not SK_TH[i] and not SK_RT[i]]
_root_meshes = lambda: [tube_mesh(pp, rr_) for pp, rr_ in ROOT_PATHS]
VOXEL = globals().get("VOXEL_OVERRIDE", 0.12)
THICK_TRIS = globals().get("THICK_TRIS_OVERRIDE", 3200)
_full = skin_mesh(THICK_NODES, {n: SK_R[n] for n in THICK_NODES}, [THICK_NODES[0]], remesh=VOXEL, extras_fn=_root_meshes)
me_thick = skin_mesh(THICK_NODES, {n: SK_R[n] for n in THICK_NODES}, [THICK_NODES[0]], remesh=VOXEL, ratio=THICK_TRIS/max(_tris(_full), 1), extras_fn=_root_meshes)
print('thick tris: remeshed', _tris(_full), '-> decimated', _tris(me_thick), 'ratio', round(THICK_TRIS/max(_tris(_full), 1), 3))
bpy.data.meshes.remove(_full)
meshes_ = [me_thick]
if THIN_NODES:
    parents_ = sorted({SK_PAR[n] for n in THIN_NODES if SK_PAR[n] is not None and SK_TH[SK_PAR[n]]})
    nodes_ = parents_ + THIN_NODES
    rad_ = {n: (min(SK_R[n], 0.06) if n in parents_ else SK_R[n]) for n in nodes_}
    meshes_.append(skin_mesh(nodes_, rad_, parents_, levels=0))     # thin, hidden inside the crowns: plain skin is enough

# merge into one bmesh (vertex positions only; faces re-indexed)
bm = bmesh.new()
for m_ in meshes_:
    vs_ = [bm.verts.new(v_.co) for v_ in m_.vertices]
    for p_ in m_.polygons:
        try: bm.faces.new([vs_[i_] for i_ in p_.vertices])
        except ValueError: pass
    bpy.data.meshes.remove(m_)
bm.verts.index_update(); bm.faces.ensure_lookup_table()
uvl = bm.loops.layers.uv.new("UVMap")

# ---------------- bark UVs: streaks follow each branch, continuing through junctions ----------------
segs_ = [i for i in range(len(SK_P)) if SK_PAR[i] is not None]
cum = [0.0]*len(SK_P)
for i in range(len(SK_P)):
    if SK_PAR[i] is not None: cum[i] = cum[SK_PAR[i]] + (SK_P[i] - SK_P[SK_PAR[i]]).length
seg_N = {}
for i in segs_:
    Tn = (SK_P[i] - SK_P[SK_PAR[i]]).normalized(); par = SK_PAR[i]
    base = seg_N.get(par, Vector((0.31, 0.77, 0.55)))
    N_ = base - Tn*base.dot(Tn)
    if N_.length < 1e-4: N_ = Tn.cross(Vector((1, 0, 0)))
    seg_N[i] = N_.normalized()
br_r = {}
for i in range(len(SK_P)): br_r.setdefault(SK_BR[i], []).append(SK_R[i])
TILE = 1.9                                    # world size of one bark tile: identical texel density on trunk, limbs and twigs
def _rep(r_):
    rf = 2*math.pi*(sum(r_)/len(r_))/TILE
    return max(1, round(rf)) if rf >= 1.5 else max(rf, 0.12)     # thick wood: whole tiles around (seamless); thin: just a slice of one tile
BR_REP = {b_: _rep(r_) for b_, r_ in br_r.items()}
BR_RM = {b_: max(0.03, sum(r_)/len(r_)) for b_, r_ in br_r.items()}
A_ = np.array([tuple(SK_P[SK_PAR[i]]) for i in segs_]); B_ = np.array([tuple(SK_P[i]) for i in segs_])
AB_ = B_ - A_; AB2_ = (AB_*AB_).sum(1); RA_ = np.array([SK_R[SK_PAR[i]] for i in segs_]); RB_ = np.array([SK_R[i] for i in segs_])

def seg_pick(p_):
    d_ = p_ - A_; t_ = np.clip((d_*AB_).sum(1)/AB2_, 0, 1); cp_ = A_ + AB_*t_[:, None]
    dist_ = np.linalg.norm(p_ - cp_, axis=1); rat_ = RA_ + (RB_ - RA_)*t_
    return int(np.argmin(dist_/np.maximum(rat_, 0.02)))
def seg_params(k_, p_):                       # u/v of point p_ expressed in segment k_'s frame (unclamped, so it extends smoothly)
    A = A_[k_]; AB = AB_[k_]; i = segs_[k_]
    t = float(np.dot(p_ - A, AB)/AB2_[k_]); cp = A + AB*t
    Tn = Vector(AB).normalized(); Nn = seg_N[i]; Bn = Tn.cross(Nn)
    rel = Vector(p_ - cp); th = math.atan2(rel.dot(Bn), rel.dot(Nn))
    arc = cum[SK_PAR[i]] + t*math.sqrt(AB2_[k_]); br_ = SK_BR[i]
    return th/(2*math.pi), arc*BR_REP[br_]/(2*math.pi*BR_RM[br_]), BR_REP[br_]
for f in bm.faces:                            # one mapping per face (chosen at its centre) -> no shearing inside a face
    k_ = seg_pick(np.array(tuple(f.calc_center_median())))
    vals = [seg_params(k_, np.array(tuple(l.vert.co))) for l in f.loops]
    fr = [v[0] for v in vals]; wrap = (max(fr) - min(fr)) > 0.5
    for l, (fu, vv, rp) in zip(f.loops, vals):
        if wrap and fu < 0: fu += 1.0
        l[uvl].uv = (fu*rp, vv)

# ---------------- leaf cards ----------------
sun = Vector((0.35,-0.25,0.9)).normalized()
lbm = bmesh.new(); luv = lbm.loops.layers.uv.new("UVMap"); vnormals = {}; made_ct = [0]
gold = math.pi*(3-math.sqrt(5))

def pick_cell(br):
    return 3 if br < 0.56 else random.choice((0, 1)) if br < 0.76 else 2

def add_card(p, n, d, s, stretch, dome, curl, k, ctr, R, roll_sd, two=True):
    if abs(n.z) < 0.93: b = (Vector((0,0,1)) - n*n.z).normalized()
    else:
        hh = Vector((d.x, d.y, 0)); b = (hh - n*hh.dot(n)).normalized() if hh.length > 1e-3 else Vector((1,0,0))
    a = b.cross(n); roll = random.gauss(0, roll_sd)
    a, b = a*math.cos(roll) + b*math.sin(roll), b*math.cos(roll) - a*math.sin(roll)
    row, col = divmod(k, 2)
    u0 = col*0.5 + 0.004; v0 = (1-row)*0.5 + 0.004; w = 0.5 - 0.008
    def nrm(pos):
        v = Vector(((pos.x-ctr.x)/R.x, (pos.y-ctr.y)/R.y, (pos.z-ctr.z)/R.z)).normalized(); v.z += 0.25
        return v.normalized()
    for side in ((1, -1) if two else (1,)):
        corners = []
        for yy in (-1, 1):
            for xx in (-1, 1):
                pos = p + a*xx*s/2 + b*yy*s*stretch/2 - d*(s*s*curl) + n*side*0.004
                v = lbm.verts.new(pos); vnormals[v] = nrm(pos); corners.append(v)
        cpos = p - d*(s*s*curl) + n*side*(dome*s)
        cv = lbm.verts.new(cpos); vnormals[cv] = nrm(cpos)
        A0, A1, B0, B1 = corners
        uvs = {A0: (0,0), A1: (1,0), B0: (0,1), B1: (1,1), cv: (0.5,0.5)}
        for t in ((A0, A1, cv), (A1, B1, cv), (B1, B0, cv), (B0, A0, cv)):
            f = lbm.faces.new(t if side == 1 else tuple(reversed(t)))
            for lp in f.loops:
                uu, vv = uvs[lp.vert]; lp[luv].uv = (u0 + w*uu, v0 + w*vv)
    made_ct[0] += 1

def rand_dir(up_bias=0.0):
    v = Vector((random.gauss(0,1), random.gauss(0,1), random.gauss(0,1))).normalized()
    if up_bias: v.z = abs(v.z)*up_bias + v.z*(1-up_bias); v.normalize()
    return v

for ci, (cc, cr) in enumerate(CROWNS):
    ctr = Vector(cc); R = Vector(cr)
    rmean = (R.x*R.y*R.z)**(1/3); sc = max(rmean/2.9, 0.95)
    phs = [random.uniform(0, 6.28) for _ in range(6)]
    # irregular silhouette: random outward lobes + a few dents, so no crown is a sphere
    bumps = [(rand_dir(0.75), random.uniform(0.14, 0.28), random.uniform(0.14, 0.30)) for _ in range(7)]
    bumps += [(rand_dir(), -random.uniform(0.07, 0.14), random.uniform(0.12, 0.2)) for _ in range(3)]
    def rough(d, phs=phs, bumps=bumps):
        r = (1.0 + 0.030*math.sin(2.3*d.x + phs[0]) + 0.030*math.sin(2.9*d.y + phs[1]) + 0.025*math.sin(3.4*d.z + phs[2])
             + 0.030*math.sin(7.3*(d.x - d.z) + phs[4]) + 0.030*math.sin(10.5*(d.y + d.z) + phs[5]) + 0.025*math.sin(13.0*(d.x - d.y) + phs[0]))
        for bd, amp, w in bumps: r += amp*math.exp(-(1.0 - d.dot(bd))/w)
        return r
    ell = lambda d, f, ctr=ctr, R=R: ctr + Vector((d.x*R.x, d.y*R.y, d.z*R.z))*f
    eln = lambda d, R=R: Vector((d.x/R.x, d.y/R.y, d.z/R.z)).normalized()

    def fib(i, n, off):
        yv = 1 - 2*(i+0.5)/n; rv = math.sqrt(max(0, 1-yv*yv)); pa = i*gold + off
        d = Vector((rv*math.cos(pa), rv*math.sin(pa), yv))
        d += Vector((random.gauss(0,.05), random.gauss(0,.05), random.gauss(0,.05))); return d.normalized()

    # --- base layers: every layer follows the same lumpy surface (offset shells), so nothing is hollow ---
    for frac, cover, size, mode in SHELLS:
        size *= sc
        ntot = int(1.5*cover*4*math.pi*(rmean*frac)**2/(0.4*size*size)); off = random.uniform(0, 6.28)
        outer = frac >= 0.8
        for ii in range(ntot):
            d = fib(ii, ntot, off)
            if mode == 'top' and d.z < 0.12: continue
            under = max(0.0, -d.z)
            if under > 0.12 and random.random() < min(0.70 if outer else 0.30, 1.1*under): continue     # sparser toward the bottom
            nb = 0.5 + 0.5*math.sin(3.3*d.x + phs[0])*math.sin(3.9*d.y + phs[1])
            f = frac*rough(d)*(1 + random.gauss(0, 0.03))*(1 - 0.30*under*nb)
            p = ell(d, f)
            n = (eln(d) + Vector((random.gauss(0,.22), random.gauss(0,.22), random.gauss(0,.18)))).normalized()
            s_ = size*random.uniform(0.9, 1.15)*(1 - 0.30*under*random.random())
            height = (p.z - (ctr.z - R.z))/(2*R.z)
            br = (0.28 + 0.30*(0.5+0.5*n.dot(sun)) + 0.30*height - 0.50*(1-frac)
                  - 0.04*(6.5 - ctr.z) - 0.30*max(0.0, -n.z) + random.uniform(-0.13, 0.13))
            add_card(p, n, d, s_, 1.0, 0.20, 0.04, pick_cell(br), ctr, R, 0.80, two=(frac < 0.85))

    # --- sticking-out layer: clusters at random orientations/rotations poking out of the surface, embedded in it ---
    s0 = 1.6*sc
    ntot = int(STICK_COVER*4*math.pi*rmean**2/(0.4*s0*s0)); off = random.uniform(0, 6.28)
    for ii in range(ntot):
        d = fib(ii, ntot, off); under = max(0.0, -d.z)
        if under > 0.15 and random.random() < min(0.80, 1.2*under): continue
        f = rough(d)*random.uniform(0.93, 1.10)*(1 - 0.28*under)
        p = ell(d, f)
        n = (eln(d)*0.50 + rand_dir()*0.50).normalized()                 # points all sorts of ways, still roughly outward
        if n.z < -0.5 and under < 0.3: n.z = -n.z*0.5; n.normalize()
        s_ = random.uniform(1.15, 1.8)*sc
        height = (p.z - (ctr.z - R.z))/(2*R.z)
        br = (0.30 + 0.30*(0.5+0.5*n.dot(sun)) + 0.30*height - 0.04*(6.5 - ctr.z) - 0.25*under + random.uniform(-0.15, 0.15))
        k_ = pick_cell(br)
        if k_ == 3 and d.z > 0.25: k_ = random.choice((0, 1))              # no dark clusters on the sunlit top
        add_card(p, n, d, s_, 1.0, 0.26, 0.04, k_, ctr, R, 1.6, two=True)

    # --- a few clusters hanging naturally from the lower edge, attached to the mass ---
    for _ in range(int(3*rmean)):
        pa = random.uniform(0, 2*math.pi); zz = -random.uniform(0.15, 0.6); rxy = math.sqrt(1 - zz*zz)
        d0 = Vector((rxy*math.cos(pa), rxy*math.sin(pa), zz))
        cp = ell(d0, rough(d0)*random.uniform(0.80, 0.95)) + Vector((0, 0, -random.uniform(0.0, 0.45)*sc))
        for _k in range(random.randint(3, 4)):
            p = cp + Vector((random.gauss(0, 0.35), random.gauss(0, 0.35), random.gauss(0, 0.25)))*sc
            dd = Vector(((p.x-ctr.x)/R.x, (p.y-ctr.y)/R.y, (p.z-ctr.z)/R.z))
            if dd.length > 1.0*rough(dd.normalized()): continue                  # must stay inside the crown's own surface
            dd = dd.normalized()
            n = (eln(dd) + Vector((random.gauss(0,.2), random.gauss(0,.2), random.gauss(0,.15) - 0.10))).normalized()
            br = (0.18 + 0.25*(0.5+0.5*n.dot(sun)) - 0.04*(6.5 - ctr.z) - 0.20 + random.uniform(-0.13, 0.13))
            add_card(p, n, dd, random.uniform(1.0, 1.5)*sc, 1.0, 0.30, 0.05, pick_cell(br), ctr, R, 1.0, two=True)
# sticks that poke out of a crown get a few leaf clusters on their tips, so they read as attached to the foliage
for tip, ci in TW:
    ctr = Vector(CROWNS[ci][0]); R = Vector(CROWNS[ci][1]); tp = SK_P[tip]
    nr = Vector(((tp.x-ctr.x)/R.x, (tp.y-ctr.y)/R.y, (tp.z-ctr.z)/R.z)).length
    if nr > 0.82 and random.random() < 0.85:
        sc_ = max((R.x*R.y*R.z)**(1/3)/2.9, 0.95)
        for _ in range(random.randint(2, 3)):
            p = tp + Vector((random.gauss(0, 0.18), random.gauss(0, 0.18), random.gauss(0, 0.14)))*sc_
            dd = Vector(((p.x-ctr.x)/R.x, (p.y-ctr.y)/R.y, (p.z-ctr.z)/R.z)).normalized()
            n = (dd + Vector((random.gauss(0,.35), random.gauss(0,.35), random.gauss(0,.3)))).normalized()
            br = 0.40 + 0.25*(0.5+0.5*n.dot(sun)) + random.uniform(-0.15, 0.15)
            add_card(p, n, dd, random.uniform(0.9, 1.3)*sc_, 1.0, 0.28, 0.04, pick_cell(br), ctr, R, 1.4, two=True)
made = made_ct[0]
anchors = list(CROWNS)

bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
tme = bpy.data.meshes.new("Tree_Trunk" + TAG); bm.to_mesh(tme); bm.free()
nl = [tuple(vnormals[v]) for v in lbm.verts]
leme = bpy.data.meshes.new("Tree_Leaves" + TAG); lbm.to_mesh(leme); lbm.free()
for me in (tme, leme): me.polygons.foreach_set("use_smooth", [True]*len(me.polygons))
leme.normals_split_custom_set_from_vertices(nl)
trunk = bpy.data.objects.new("Tree_Trunk" + TAG, tme); leaves = bpy.data.objects.new("Tree_Leaves" + TAG, leme)
trunk.location = OFFSET; leaves.location = OFFSET
bpy.context.collection.objects.link(trunk); bpy.context.collection.objects.link(leaves)

def tex(nt, img, nc=False):
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = img
    if nc: t.image.colorspace_settings.name = 'Non-Color'
    return t
m = bpy.data.materials.get("Bark") or bpy.data.materials.new("Bark"); m.use_nodes = True
nt = m.node_tree; nt.nodes.clear()
out = nt.nodes.new("ShaderNodeOutputMaterial"); bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
c = tex(nt, bpy.data.images["bark"]); nm = tex(nt, bpy.data.images["bark_normal"], True)
nn = nt.nodes.new("ShaderNodeNormalMap"); bs.inputs["Roughness"].default_value = 0.92
nt.links.new(c.outputs["Color"], bs.inputs["Base Color"]); nt.links.new(nm.outputs["Color"], nn.inputs["Color"])
nt.links.new(nn.outputs["Normal"], bs.inputs["Normal"]); nt.links.new(bs.outputs["BSDF"], out.inputs["Surface"])
tme.materials.append(m)

lm = bpy.data.materials.get("Leaves") or bpy.data.materials.new("Leaves"); lm.use_nodes = True
nt = lm.node_tree; nt.nodes.clear()
out = nt.nodes.new("ShaderNodeOutputMaterial"); bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
c = tex(nt, bpy.data.images["leaves_atlas"]); bs.inputs["Roughness"].default_value = 0.8
nt.links.new(c.outputs["Color"], bs.inputs["Base Color"]); nt.links.new(c.outputs["Alpha"], bs.inputs["Alpha"])
nt.links.new(bs.outputs["BSDF"], out.inputs["Surface"])
try: lm.surface_render_method = 'DITHERED'
except Exception as e: print(e)
lm.use_backface_culling = False
leme.materials.append(lm)

tris = lambda me: sum(len(p.vertices)-2 for p in me.polygons)
print("anchors", len(anchors), "cards", made, "trunk tris", tris(tme), "leaf tris", tris(leme),
      "dims", tuple(round(x,2) for x in leaves.dimensions), tuple(round(x,2) for x in trunk.dimensions))
for w in bpy.context.window_manager.windows:
    for area in w.screen.areas:
        if area.type == 'VIEW_3D':
            r3 = area.spaces.active.region_3d
            r3.view_location = (0, 0, 3.0); r3.view_distance = 12.5
            r3.view_rotation = Euler((math.radians(86), 0, math.radians(30)), 'XYZ').to_quaternion()
