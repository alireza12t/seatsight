// SeatSight engine: room geometry, seat scoring and a tiny Canvas2D 3D renderer.
// No dependencies. Units are meters. x = right, y = up, z = distance from the screen.
// The iOS app (ios/SeatSight/Engine.swift) mirrors this file line for line.
const SeatSight = (() => {
  const COUCH = 2.5;            // couch-to-TV distance used for the "TV equivalent"
  const NEAR = 0.05;
  const LABELS = 'ABCDEFGHJKLMNOPQRSTUVWXYZ';
  const rad = d => d * Math.PI / 180, deg = r => r * 180 / Math.PI;

  // ---------- Room ----------
  function build(a, seed = '') {
    const eyeH = a.eyeHeight || 1.15;
    const rows = a.rows.map((spec, i) => {
      const parts = String(spec).split('-').map(Number);
      const width = parts.reduce((s, n) => s + n, 0) * a.seatWidth + (parts.length - 1) * a.aisle;
      const z = a.firstRow + i * a.rowPitch;
      const floor = i < a.flatRows ? 0 : (i - a.flatRows + 1) * a.riser;
      const label = (a.rowLabels || LABELS)[i] || String(i + 1);
      const seats = [];
      let x = -width / 2, n = 1;
      parts.forEach((count, p) => {
        for (let k = 0; k < count; k++, n++, x += a.seatWidth)
          seats.push({ id: label + n, row: i, num: n, section: p, x: x + a.seatWidth / 2, z, floor, eye: floor + eyeH });
        x += a.aisle;
      });
      return { label, z, floor, width, parts, seats };
    });
    const W = a.screen.width, H = W / a.screen.aspect, bottom = a.screen.bottom;
    const last = rows[rows.length - 1];
    const r = {
      a, rows, W, H, bottom, top: bottom + H, eyeH,
      roomW: Math.max(W + 2, ...rows.map(r => r.width + 2 * a.aisle)),
      back: last.z + a.rowPitch * 0.6,
      ceil: Math.max(bottom + H + 1.2, last.floor + 3.2),
    };
    r.seats = rows.flatMap(row => row.seats);
    r.seats.forEach((s, i) => { s.m = metrics(r, s); s.sold = sold(a.id + seed, i, s, r); });
    const open = r.seats.filter(s => !s.sold);
    r.best = (open.length ? open : r.seats).reduce((b, s) => (s.m.score > b.m.score ? s : b));
    return r;
  }

  // Stable fake "sold" seats so the map looks real. Center seats sell first.
  function sold(id, i, s, r) {
    let h = 2166136261;
    for (const c of id + i) h = Math.imul(h ^ c.charCodeAt(0), 16777619);
    const rnd = ((h >>> 0) % 1000) / 1000;
    return rnd < 0.15 + 0.4 * (s.m.score / 100) ** 2;
  }

  // ---------- Scoring ----------
  function metrics(r, s) {
    const d = s.z;
    const h = deg(Math.atan2(r.W / 2 - s.x, d) - Math.atan2(-r.W / 2 - s.x, d));
    const neck = deg(Math.atan2(r.top - s.eye, d));
    const off = deg(Math.atan2(Math.abs(s.x), d));
    let c = null; // C-value: sightline clearance over the eye of the person in front
    if (s.row > 0) {
      const f = r.rows[s.row - 1];
      const ys = s.eye + (r.bottom - s.eye) * ((s.z - f.z) / s.z);
      c = ys - (f.floor + r.eyeH);
    }
    const ideal = r.a.idealAngle;
    const aS = 0.25 + 0.75 * Math.exp(-(((h - ideal) / (ideal * 0.6)) ** 2));
    const nS = neck > 30 ? Math.max(0.4, 1 - (neck - 30) / 30) : 1;
    const oS = Math.max(0.35, 1 - off * 0.004 - Math.max(0, off - 15) / 45);
    const cS = c === null || c >= 0.09 ? 1 : c >= 0.06 ? 0.94 : c >= 0 ? 0.82 : 0.68;
    const score = Math.round(100 * aS * nS * oS * cS);
    const tv = Math.round((2 * COUCH * Math.tan(rad(h / 2)) * 1.147) / 0.0254);
    const notes = [];
    if (h > ideal * 1.25) notes.push('Very close. The screen spills past your view, you will move your head to follow action.');
    else if (h < ideal * 0.7) notes.push('Far back. Feels more like a big TV than a wall of picture.');
    else notes.push('The screen fills your view about right for this format.');
    if (neck > 30) notes.push(`You look up ${Math.round(neck)}° to the top edge. Neck strain is likely in a long movie.`);
    if (off > 20) notes.push('Well off to the side. The picture looks skewed.');
    if (c !== null && c < 0.06) notes.push('The head in front may cover the bottom of the screen (subtitles).');
    return { h, neck, off, c, score, tv, notes };
  }

  // ---------- Scene (built once per room) ----------
  // A poly: { p: [[x,y,z]...], col: [r,g,b], layer, n: normal|null, emit, seat }
  function scene(r, opt = {}) {
    const out = [], a = r.a;
    const hw = r.roomW / 2;
    const quad = (p, col, layer, n, extra) => out.push({ p, col, layer, n, ...extra });
    const box = (x0, x1, y0, y1, z0, z1, col, seat, sold) => {
      quad([[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0]], col, 20, [0, 0, -1], { seat, sold });
      quad([[x1, y0, z1], [x0, y0, z1], [x0, y1, z1], [x1, y1, z1]], col, 20, [0, 0, 1], { seat, sold });
      quad([[x0, y1, z0], [x1, y1, z0], [x1, y1, z1], [x0, y1, z1]], col, 20, [0, 1, 0], { seat, sold });
      quad([[x0, y0, z1], [x0, y0, z0], [x0, y1, z0], [x0, y1, z1]], col, 20, [-1, 0, 0], { seat, sold });
      quad([[x1, y0, z0], [x1, y0, z1], [x1, y1, z1], [x1, y1, z0]], col, 20, [1, 0, 0], { seat, sold });
    };
    const wall = [22, 24, 34], floorC = [30, 28, 34], stepC = [44, 40, 48];
    // shell
    quad([[-hw, 0, 0], [hw, 0, 0], [hw, r.ceil, 0], [-hw, r.ceil, 0]], [14, 15, 20], 0, [0, 0, 1]);
    quad([[-hw, 0, r.back], [-hw, 0, 0], [-hw, r.ceil, 0], [-hw, r.ceil, r.back]], wall, 0, [1, 0, 0]);
    quad([[hw, 0, 0], [hw, 0, r.back], [hw, r.ceil, r.back], [hw, r.ceil, 0]], wall, 0, [-1, 0, 0]);
    quad([[hw, 0, r.back], [-hw, 0, r.back], [-hw, r.ceil, r.back], [hw, r.ceil, r.back]], wall, 0, [0, 0, -1]);
    quad([[-hw, r.ceil, 0], [hw, r.ceil, 0], [hw, r.ceil, r.back], [-hw, r.ceil, r.back]], [12, 12, 16], 0, [0, -1, 0]);
    // floor and steps
    let prevFloor = 0, prevZ = 0;
    r.rows.forEach((row) => {
      const z0 = row.z - a.rowPitch * 0.55, z1 = row.z + a.rowPitch * 0.45;
      quad([[-hw, prevFloor, prevZ], [hw, prevFloor, prevZ], [hw, prevFloor, z0], [-hw, prevFloor, z0]], floorC, 1, [0, 1, 0]);
      if (row.floor > prevFloor) {
        quad([[-hw, prevFloor, z0], [hw, prevFloor, z0], [hw, row.floor, z0], [-hw, row.floor, z0]], stepC, 1, [0, 0, -1]);
        // little aisle step lights at both walls
        [-hw + 0.3, hw - 0.5].forEach(x => quad([[x, row.floor - 0.06, z0 - 0.01], [x + 0.2, row.floor - 0.06, z0 - 0.01], [x + 0.2, row.floor - 0.02, z0 - 0.01], [x, row.floor - 0.02, z0 - 0.01]], [255, 190, 90], 1, [0, 0, -1], { emit: true }));
      }
      prevFloor = row.floor; prevZ = z0;
    });
    quad([[-hw, prevFloor, prevZ], [hw, prevFloor, prevZ], [hw, prevFloor, r.back], [-hw, prevFloor, r.back]], floorC, 1, [0, 1, 0]);
    // screen: masking, then the movie fitted to the film's aspect ratio
    const zS = 0.02, sx = r.W / 2;
    quad([[-sx - 0.3, r.bottom - 0.3, zS], [sx + 0.3, r.bottom - 0.3, zS], [sx + 0.3, r.top + 0.3, zS], [-sx - 0.3, r.top + 0.3, zS]], [4, 4, 6], 2, null, { emit: true });
    const film = opt.film || a.screen.aspect;
    let cw = r.W, ch = r.W / film;
    if (ch > r.H) { ch = r.H; cw = r.H * film; }
    const mid = r.bottom + r.H / 2, hh = ch / cw / 2; // half frame height, in picture widths
    // the bare screen: any part the movie doesn't cover shows as grey bars
    quad([[-sx, r.bottom, zS + 0.0005], [sx, r.bottom, zS + 0.0005], [sx, r.top, zS + 0.0005], [-sx, r.top, zS + 0.0005]], [24, 24, 30], 3, null, { emit: true });
    // One fixed picture cropped by the frame. A taller frame (IMAX) reveals more sky and foreground,
    // a 2.39 scope frame is a thin slice of it. Picture units: width = 1, y = 0 at frame center.
    const pic = (pts, col, l) => { const c = clipY(pts, -hh, hh); if (c.length > 2) quad(c.map(([u, y]) => [-cw / 2 + u * cw, mid + y * cw, zS + l * 0.001]), col, 3 + l, null, { emit: true }); };
    const ring = (u, y, rr, n = 20) => Array.from({ length: n }, (_, k) => [u + rr * Math.cos((k / n) * 6.283), y + rr * Math.sin((k / n) * 6.283)]);
    const sky = [[255, 196, 120], [247, 150, 110], [196, 98, 120], [110, 70, 130], [44, 44, 96], [12, 14, 40]];
    for (let i = 0; i < 16; i++) {
      const y0 = -0.06 + i * 0.026, t = (i / 15) * 5, k = Math.min(4, Math.floor(t));
      pic([[0, y0], [1, y0], [1, y0 + 0.027], [0, y0 + 0.027]], sky[k].map((c, j) => c + (sky[k + 1][j] - c) * (t - k)), 1);
    }
    for (let k = 0; k < 24; k++) { const u = (k * 0.137 + 0.03) % 1, y = 0.215 + ((k * 0.071) % 0.13); pic([[u, y], [u + 0.003, y], [u + 0.003, y + 0.003], [u, y + 0.003]], [230, 230, 255], 2); }
    pic(ring(0.18, 0.245, 0.02), [236, 232, 214], 2);
    pic(ring(0.62, 0.0, 0.045, 24), [255, 236, 190], 2);
    pic([[0, -0.35], [0, -0.02], [0.12, 0.05], [0.22, 0.0], [0.35, 0.08], [0.5, 0.01], [0.66, 0.05], [0.8, -0.02], [0.9, 0.03], [1, -0.01], [1, -0.35]], [120, 70, 110], 3);
    pic([[0, -0.16], [0, -0.08], [0.15, -0.05], [0.3, -0.1], [0.45, -0.06], [0.6, -0.12], [0.78, -0.07], [1, -0.11], [1, -0.16]], [40, 26, 52], 4);
    pic([[0, -0.35], [1, -0.35], [1, -0.15], [0, -0.15]], [26, 40, 62], 5);
    [[-0.17, 0.05], [-0.2, 0.035], [-0.24, 0.025], [-0.29, 0.015]].forEach(([y, wd]) => pic([[0.62 - wd / 2, y], [0.62 + wd / 2, y], [0.62 + wd / 2, y + 0.008], [0.62 - wd / 2, y + 0.008]], [255, 200, 140], 6));
    // subtitles sit at the bottom of the frame, to check what the head in front covers
    [[0.25, 0.75, 0.05], [0.32, 0.68, 0.025]].forEach(([u0, u1, v]) => { const y = mid - ch / 2 + v * ch; quad([[-cw / 2 + u0 * cw, y, zS + 0.008], [-cw / 2 + u1 * cw, y, zS + 0.008], [-cw / 2 + u1 * cw, y + ch * 0.028, zS + 0.008], [-cw / 2 + u0 * cw, y + ch * 0.028, zS + 0.008]], [250, 250, 250], 10, null, { emit: true }); });
    // seats and people
    const seatC = hex(a.seatColor || '#35416b'), soldC = [46, 46, 52];
    const recl = a.seatWidth >= 0.8;
    r.seats.forEach(s => {
      const w = a.seatWidth * 0.44, f = s.floor, z = s.z;
      box(s.x - w, s.x + w, f + 0.28, f + 0.48, z - (recl ? 0.45 : 0.32), z + 0.12, s.sold ? soldC : seatC, s.id, s.sold);
      box(s.x - w, s.x + w, f + 0.28, f + (recl ? 1.08 : 0.98), z + 0.12, z + 0.24, s.sold ? soldC : seatC, s.id, s.sold);
      if (opt.crowd && s.sold && s.id !== opt.self) {
        out.push({ circle: [s.x, s.eye + 0.04, z], r: 0.11, col: [52, 48, 56], layer: 20, seat: s.id });
        quad([[s.x - 0.22, s.eye - 0.38, z + 0.02], [s.x + 0.22, s.eye - 0.38, z + 0.02], [s.x + 0.2, s.eye - 0.12, z + 0.02], [s.x - 0.2, s.eye - 0.12, z + 0.02]], [52, 48, 56], 20, null, { seat: s.id });
      }
    });
    return out;
  }

  // ---------- Camera ----------
  const eyeCam = (r, s) => look([s.x, s.eye, s.z], [0, r.bottom + r.H / 2, 0]);
  // Dollhouse view from behind and above; the back wall and ceiling are culled so you see every seat.
  const overCam = r => look([0, r.ceil + 3, r.back + 2.5], [0, r.rows[0].floor, r.back * 0.45]);
  function look(pos, t) {
    const dx = t[0] - pos[0], dy = t[1] - pos[1], dz = t[2] - pos[2];
    return { pos, yaw: Math.atan2(dx, -dz), pitch: Math.atan2(dy, Math.hypot(dx, dz)), zoom: 1 };
  }
  const lerpCam = (a, b, t) => ({
    pos: a.pos.map((v, i) => v + (b.pos[i] - v) * t),
    yaw: a.yaw + (b.yaw - a.yaw) * t, pitch: a.pitch + (b.pitch - a.pitch) * t, zoom: a.zoom + (b.zoom - a.zoom) * t,
  });

  // ---------- Render ----------
  const L = norm([0.25, 0.6, -0.75]); // light from the screen, a bit above
  function view(cam, w, h) {
    const cy = Math.cos(cam.yaw), sy = Math.sin(cam.yaw), cp = Math.cos(cam.pitch), sp = Math.sin(cam.pitch);
    const fw = [sy * cp, sp, -cy * cp], rt = [cy, 0, sy], up = cross(rt, fw);
    const f = Math.min(w / 2 / Math.tan(rad(45)), h / 2 / Math.tan(rad(37))) * cam.zoom;
    const [px, py, pz] = cam.pos;
    const toCam = ([x, y, z]) => { const vx = x - px, vy = y - py, vz = z - pz; return [vx * rt[0] + vy * rt[1] + vz * rt[2], vx * up[0] + vy * up[1] + vz * up[2], vx * fw[0] + vy * fw[1] + vz * fw[2]]; };
    const proj = q => [w / 2 + (f * q[0]) / q[2], h / 2 - (f * q[1]) / q[2]];
    return { f, px, py, pz, toCam, proj };
  }

  // Which seat is under screen point (x, y)? Returns the seat id or null.
  function pick(w, h, polys, cam, x, y) {
    const { px, py, pz, toCam, proj } = view(cam, w, h);
    let hit = null, best = Infinity, near = null, nearD = Infinity;
    for (const poly of polys) {
      if (!poly.seat || poly.circle) continue;
      const v = poly.p[0], n = poly.n;
      if (n && (px - v[0]) * n[0] + (py - v[1]) * n[1] + (pz - v[2]) * n[2] <= 0) continue;
      const cs = poly.p.map(toCam);
      if (cs.some(q => q[2] < NEAR)) continue;
      const pts = cs.map(proj);
      let inside = false;
      for (let i = 0, j = pts.length - 1; i < pts.length; j = i++)
        if ((pts[i][1] > y) !== (pts[j][1] > y) && x < ((pts[j][0] - pts[i][0]) * (y - pts[i][1])) / (pts[j][1] - pts[i][1]) + pts[i][0]) inside = !inside;
      const d = cs.reduce((s, q) => s + q[2], 0) / cs.length;
      if (inside && d < best) { best = d; hit = poly.seat; }
      if (!hit) { // forgiving taps: nearest seat face within 24 px
        const cx = pts.reduce((s, q) => s + q[0], 0) / pts.length, cy = pts.reduce((s, q) => s + q[1], 0) / pts.length;
        const dist = Math.hypot(cx - x, cy - y);
        if (dist < 24 && dist < nearD) { nearD = dist; near = poly.seat; }
      }
    }
    return hit || near;
  }

  function render(ctx, w, h, polys, cam, opt = {}) {
    const { f, px, py, pz, toCam, proj } = view(cam, w, h);
    const items = [];
    for (const poly of polys) {
      if (opt.hide && poly.seat === opt.hide) continue;
      if (poly.circle) {
        const q = toCam(poly.circle);
        if (q[2] > NEAR) items.push({ poly, d: q[2], c: proj(q), rr: (f * poly.r) / q[2] });
        continue;
      }
      if (poly.n) { const v = poly.p[0], n = poly.n; if ((px - v[0]) * n[0] + (py - v[1]) * n[1] + (pz - v[2]) * n[2] <= 0) continue; }
      let cs = poly.p.map(toCam);
      let behind = 0; for (const q of cs) if (q[2] < NEAR) behind++;
      if (behind === cs.length) continue;
      if (behind) cs = clipNear(cs);
      let d = 0; const pts = cs.map(q => { d += q[2]; return proj(q); });
      items.push({ poly, d: d / cs.length, pts });
    }
    items.sort((A, B) => A.poly.layer - B.poly.layer || B.d - A.d);
    ctx.fillStyle = '#07080c'; ctx.fillRect(0, 0, w, h);
    for (const it of items) {
      const p = it.poly;
      let col = p.col;
      if (opt.map && p.sold !== undefined) col = p.sold ? [58, 58, 66] : [70, 120, 205]; // room view: map colors
      if (p.seat && p.seat === opt.highlight) col = [255, 196, 60];
      let k = 1;
      if (!p.emit) {
        const lit = p.n ? Math.max(0, p.n[0] * L[0] + p.n[1] * L[1] + p.n[2] * L[2]) : 0.5;
        k = (0.45 + 0.75 * lit) / (opt.map ? 1 : 1 + it.d * 0.03);
      }
      ctx.fillStyle = `rgb(${col[0] * k | 0},${col[1] * k | 0},${col[2] * k | 0})`;
      ctx.beginPath();
      if (it.c) ctx.arc(it.c[0], it.c[1], Math.max(0.5, it.rr), 0, Math.PI * 2);
      else { ctx.moveTo(it.pts[0][0], it.pts[0][1]); for (let i = 1; i < it.pts.length; i++) ctx.lineTo(it.pts[i][0], it.pts[i][1]); }
      ctx.fill();
    }
  }

  function clipY(pts, lo, hi) {
    const cut = (P, keep, yv) => {
      const o = [];
      for (let i = 0; i < P.length; i++) {
        const A = P[i], B = P[(i + 1) % P.length], a = keep(A[1]), b = keep(B[1]);
        if (a) o.push(A);
        if (a !== b) { const t = (yv - A[1]) / (B[1] - A[1]); o.push([A[0] + (B[0] - A[0]) * t, yv]); }
      }
      return o;
    };
    return cut(cut(pts, y => y >= lo, lo), y => y <= hi, hi);
  }
  function clipNear(cs) {
    const out = [];
    for (let i = 0; i < cs.length; i++) {
      const A = cs[i], B = cs[(i + 1) % cs.length], ai = A[2] >= NEAR, bi = B[2] >= NEAR;
      if (ai) out.push(A);
      if (ai !== bi) { const t = (NEAR - A[2]) / (B[2] - A[2]); out.push([A[0] + (B[0] - A[0]) * t, A[1] + (B[1] - A[1]) * t, NEAR]); }
    }
    return out;
  }
  function cross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; }
  function norm(v) { const l = Math.hypot(...v); return v.map(x => x / l); }
  function hex(s) { const n = parseInt(s.slice(1), 16); return [n >> 16, (n >> 8) & 255, n & 255]; }

  // Same relative spot in another room, for the compare view.
  function similarSeat(from, seat, to) {
    const fr = seat.row / Math.max(1, from.rows.length - 1);
    const fx = seat.x / (from.rows[seat.row].width / 2);
    const row = to.rows[Math.round(fr * (to.rows.length - 1))];
    return row.seats.reduce((b, s) => (Math.abs(s.x - fx * row.width / 2) < Math.abs(b.x - fx * row.width / 2) ? s : b));
  }

  return { build, scene, render, pick, eyeCam, overCam, lerpCam, similarSeat };
})();
