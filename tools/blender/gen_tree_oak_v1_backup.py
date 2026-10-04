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

# ---------------- bark: Poly Haven "Bark Brown 01" by Rob Tuytel (CC0), 1k ----------------
if REGEN or "bark" not in bpy.data.images:
    for nm_ in ("bark", "bark_normal"):
        if nm_ in bpy.data.images: bpy.data.images.remove(bpy.data.images[nm_])
    _bd = bpy.data.images.load(OUT + "/bark_color.png", check_existing=False); _bd.name = "bark"; _bd.colorspace_settings.name = 'sRGB'
    _bn = bpy.data.images.load(OUT + "/bark_normal_gl.png", check_existing=False); _bn.name = "bark_normal"; _bn.colorspace_settings.name = 'Non-Color'
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
bm = bmesh.new(); uvl = bm.loops.layers.uv.new("UVMap")
rotz = lambda v, a: Matrix.Rotation(a, 3, 'Z') @ v

def tube(pts, rad_fn, segs, cap_end=False):
    n_r = len(pts); tans = []
    for i in range(n_r):
        a = pts[max(i-1,0)]; b = pts[min(i+1,n_r-1)]; tans.append((b-a).normalized())
    n = tans[0].cross(Vector((0.31,0.77,0.55))).normalized()
    rings, lens, acc = [], [], 0.0
    for i in range(n_r):
        t = tans[i]; n = (n - t*n.dot(t)).normalized(); b = t.cross(n)
        rings.append([bm.verts.new(pts[i] + (n*math.cos(2*math.pi*j/segs) + b*math.sin(2*math.pi*j/segs))*rad_fn(i, 2*math.pi*j/segs, pts[i])) for j in range(segs)])
        if i: acc += (pts[i]-pts[i-1]).length
        lens.append(acc)
    rmean = sum(rad_fn(i, 0, pts[i]) for i in range(n_r))/n_r
    circ = 2*math.pi*rmean; rep = max(1, round(circ/2.3)); vs = 1.0/(circ/rep)
    for i in range(n_r-1):
        for j in range(segs):
            f = bm.faces.new((rings[i][j], rings[i][(j+1)%segs], rings[i+1][(j+1)%segs], rings[i+1][j]))
            us = (j/segs*rep, (j+1)/segs*rep, (j+1)/segs*rep, j/segs*rep)
            vv = (lens[i]*vs,)*2 + (lens[i+1]*vs,)*2
            for lp, u, v in zip(f.loops, us, vv): lp[uvl].uv = (u, v)
    if cap_end:
        c = bm.verts.new(pts[-1] + tans[-1]*0.02)
        for j in range(segs):
            f = bm.faces.new((rings[-1][(j+1)%segs], rings[-1][j], c))
            for lp in f.loops: lp[uvl].uv = (0.5, 0.5)

def grow(start, d, length, r0, r1, steps, bend=0.10, up=0.04, kink=0.0, segs=6, pw=1.0, cap=False):
    pts = [start.copy()]; p = start.copy(); d = d.normalized()
    ki = random.randint(2, max(2, steps-2)) if kink > 0 else -1
    for i in range(1, steps+1):
        d = (d + Vector((random.gauss(0,bend), random.gauss(0,bend), random.gauss(0,bend)*0.6 + up))).normalized()
        if i == ki: d = (d + Vector((random.gauss(0,kink), random.gauss(0,kink), random.gauss(0,kink)*0.5))).normalized()
        p = p + d*(length/steps); pts.append(p.copy())
    tube(pts, lambda i, th, pp: (r0 + (r1-r0)*(i/steps)**pw)*(1 + 0.05*math.sin(3*th + i*1.3)), segs, cap_end=cap)
    return pts
def dir_at(pts, i):
    i = max(1, min(i, len(pts)-1)); return (pts[i]-pts[i-1]).normalized()

random_lean_amt = 0.50*(random.uniform(0.6, 1.5) if VARY else 1.0)
def sway(z):
    k = min(max(z, 0)/HT, 1.3)
    return Vector((LEAN*random_lean_amt*k**1.6, 0.14*math.sin(z*1.1)*k, z))
tz = [-0.25 + (HT+0.25)*(i/15)**1.1 for i in range(16)]
def trunk_r(i, th, p):
    z = max(p.z, 0); t = z/HT
    lobes = (0.5 + 0.5*math.cos(5*th + 0.7))**2
    r = 0.70*(1 - 0.34*t)
    r *= 1 + 0.30*math.exp(-z/0.60) + 0.20*math.exp(-z/0.40)*lobes
    r *= 1 + 0.04*math.sin(3*th + z*2.0) + 0.02*math.sin(7*th - z*3.1)
    return r
tube([sway(z) for z in tz], trunk_r, 14, cap_end=True)

for i in range(5):
    az = i*2*math.pi/5 + random.uniform(-0.25, 0.25)
    dist = [0.30, 0.85, 1.40, 2.00]; zz = [0.95, 0.40, 0.06, -0.14]; rr = [0.46, 0.30, 0.16, 0.06]
    wob = random.uniform(-0.2, 0.2)
    pts = [Vector((math.cos(az + wob*k/3)*dist[k], math.sin(az + wob*k/3)*dist[k], zz[k])) for k in range(4)]
    tube(pts, lambda ii, th, pp, rr=rr: rr[ii]*(1+0.06*math.sin(3*th)), 8)

# ---------------- crowns: 4 separate foliage masses at different heights, limbs run to each ----------------
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
def limb_to(P0, T, r0, r1, steps=10, segs=8):
    pts = []
    for i in range(steps+1):
        u = i/steps; p = P0.lerp(T, u)
        p.z += 0.55*math.sin(math.pi*0.5*u)*(1-u)               # leaves the trunk heading up, then eases to the crown
        if 0 < i < steps: p += Vector((random.gauss(0,0.10), random.gauss(0,0.10), random.gauss(0,0.06)))
        pts.append(p)
    tube(pts, lambda i, th, pp: (r0 + (r1-r0)*(i/steps))*(1 + 0.05*math.sin(3*th + i*1.3)), segs)
    return pts
for ci, (cc, cr) in enumerate(CROWNS):
    C0 = Vector(cc); P0 = sway(HT - 0.22*ci - 0.1)
    T = C0 - (C0 - P0).normalized()*0.2 + Vector((0, 0, -0.3))
    pts = limb_to(P0, T, 0.36 - 0.03*ci, 0.12)
    for idx, sgn, ln in ((4, -1, 1.4), (7, 1, 1.1)):
        dd = rotz(dir_at(pts, idx), sgn*random.uniform(0.6, 1.0)); dd.z += 0.35
        sp = grow(pts[idx] - Vector((0,0,0.02)), dd, ln, 0.115, 0.04, 7, bend=0.14, up=0.03, kink=0.28, segs=6)
        d3 = rotz(dir_at(sp, 4), -sgn*random.uniform(0.7, 1.1)); d3.z += 0.4
        grow(sp[4], d3, 0.8, 0.05, 0.018, 5, bend=0.16, up=0.04, segs=4)

for az, z0, ln in ((0.2, 2.8, 1.5), (2.4, 2.6, 1.3), (4.3, 2.9, 1.4)):
    el = math.radians(random.uniform(22, 34))
    d0 = Vector((math.cos(az)*math.cos(el), math.sin(az)*math.cos(el), math.sin(el)))
    grow(sway(z0), d0, ln, 0.10, 0.012, 7, bend=0.12, up=0.0, kink=0.55, segs=5, pw=0.8)

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
    bumps = [(rand_dir(0.75), random.uniform(0.16, 0.38), random.uniform(0.14, 0.34)) for _ in range(7)]
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
        ntot = int(1.25*cover*4*math.pi*(rmean*frac)**2/(0.4*size*size)); off = random.uniform(0, 6.28)
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
