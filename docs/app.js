// SeatSight web UI: seat map, 3D seat view, compare, share. Uses engine.js.
(() => {
  const $ = id => document.getElementById(id);
  const S = SeatSight;
  const COMPARE = ['imax-190', 'ultraavx', 'regular-large', 'vip'];
  let presets = [], cfg, room, polys, seat, cam, anim = null, compareOn = false;
  const st = { id: 'imax-190', film: '', heat: false, crowd: false };

  fetch('auditoriums.json').then(r => r.json()).then(d => {
    presets = d.auditoriums;
    $('room').innerHTML = presets.map(a => `<option value="${a.id}">${a.name} · ${a.variant}</option>`).join('');
    const h = new URLSearchParams(location.hash.slice(1));
    if (presets.some(a => a.id === h.get('room'))) st.id = h.get('room');
    st.film = h.get('film') || '';
    $('film').value = st.film;
    load(h.get('w') && { w: +h.get('w'), f: +h.get('f'), k: +h.get('k') });
    const s = h.get('seat') && room.seats.find(s => s.id === h.get('seat'));
    if (s) open(s);
  });

  // ---------- Room + map ----------
  function load(tw) {
    const base = presets.find(a => a.id === st.id);
    cfg = structuredClone(base);
    if (tw) { cfg.screen.width = tw.w; cfg.firstRow = tw.f; cfg.riser = tw.k; }
    $('room').value = st.id;
    setSlider('tw', cfg.screen.width, 'm'); setSlider('tf', cfg.firstRow, 'm'); setSlider('tk', cfg.riser, 'm');
    rebuild();
  }
  function setSlider(id, v, unit) { $(id).value = v; $(id).nextElementSibling.textContent = v + ' ' + unit; }
  function tweaked() { const b = presets.find(a => a.id === st.id); return cfg.screen.width !== b.screen.width || cfg.firstRow !== b.firstRow || cfg.riser !== b.riser; }

  function rebuild() {
    room = S.build(cfg);
    const map = $('map');
    const cols = Math.max(...room.rows.map(r => r.seats.length + (r.parts.length - 1) * 1.4)) + 3;
    map.style.setProperty('--s', Math.max(11, Math.min(26, (map.clientWidth - 24) / cols - 2)) + 'px');
    const heat = s => `hsl(${s.m.score * 1.2},65%,${s.sold ? 22 : 45}%)`;
    map.innerHTML = `<div class="screen" style="width:${Math.min(92, 40 + room.W * 2.2)}%">${cfg.name} screen · ${room.W.toFixed(1)} m wide</div>` +
      room.rows.slice().map(r => {
        let html = `<div class="row"><b>${r.label}</b>`, p = 0;
        r.seats.forEach(s => {
          if (s.section !== p) { html += '<span class="aisle"></span>'; p = s.section; }
          const bg = st.heat ? ` style="background:${heat(s)}"` : '';
          html += `<button class="seat${s.sold ? ' sold' : ''}${s === room.best ? ' best' : ''}" data-id="${s.id}"${bg} title="${s.id} · score ${s.m.score}${s.sold ? ' · sold' : ''}" aria-label="Seat ${s.id}, score ${s.m.score}${s.sold ? ', sold' : ''}"></button>`;
        });
        return html + `<b>${r.label}</b></div>`;
      }).join('') +
      `<div class="legend"><span><i style="background:var(--seat)"></i>Available</span><span><i style="background:var(--sold)"></i>Sold (demo)</span><span><i style="box-shadow:inset 0 0 0 2px var(--accent)"></i>Best seat</span>${st.heat ? '<span><i style="background:hsl(0,65%,45%)"></i>Poor → <i style="background:hsl(120,65%,45%)"></i>Great</span>' : ''}</div>`;
    $('best').textContent = `Best seat: ${room.best.id} (${room.best.m.score})`;
  }

  $('map').addEventListener('click', e => { const id = e.target.dataset?.id; if (id) open(room.seats.find(s => s.id === id)); });
  $('room').onchange = e => { st.id = e.target.value; load(); };
  $('film').onchange = e => { st.film = e.target.value; };
  $('heat').onclick = e => { st.heat = !st.heat; e.target.setAttribute('aria-pressed', st.heat); rebuild(); };
  $('crowd').onclick = e => { st.crowd = !st.crowd; e.target.setAttribute('aria-pressed', st.crowd); };
  $('best').onclick = () => open(room.best);
  [['tw', v => cfg.screen.width = v], ['tf', v => cfg.firstRow = v], ['tk', v => cfg.riser = v]].forEach(([id, set]) => {
    $(id).oninput = e => { const v = +e.target.value; set(v); setSlider(id, v, 'm'); rebuild(); };
  });
  addEventListener('resize', () => { if (room) rebuild(); draw(); });

  // ---------- 3D view ----------
  const canvas = $('c'), ctx = canvas.getContext('2d');
  function open(s) {
    const wasOpen = $('view').classList.contains('open');
    seat = s;
    polys = S.scene(room, { film: +st.film || 0, crowd: st.crowd, self: s.id });
    $('view').classList.add('open');
    document.body.style.overflow = 'hidden';
    fly(wasOpen && cam ? cam : S.overCam(room), S.eyeCam(room, s), wasOpen ? 600 : 1300);
    hud();
    const h = new URLSearchParams({ room: st.id, seat: s.id });
    if (st.film) h.set('film', st.film);
    if (tweaked()) { h.set('w', cfg.screen.width); h.set('f', cfg.firstRow); h.set('k', cfg.riser); }
    history.replaceState(null, '', '#' + h);
    if (compareOn) drawCompare();
  }
  function close() {
    $('view').classList.remove('open'); document.body.style.overflow = '';
    history.replaceState(null, '', location.pathname); compareOn = false; $('compare').classList.remove('open'); $('view').classList.remove('cmp'); $('cmp').textContent = 'Compare';
  }
  function fly(from, to, ms) {
    const t0 = performance.now();
    cancelAnimationFrame(anim);
    const step = now => {
      const t = Math.min(1, (now - t0) / ms), e = t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2;
      cam = S.lerpCam(from, to, e); draw();
      if (t < 1) anim = requestAnimationFrame(step);
    };
    anim = requestAnimationFrame(step);
  }
  function draw() {
    if (!$('view').classList.contains('open') || !cam) return;
    const dpr = Math.min(2, devicePixelRatio || 1), w = canvas.clientWidth, h = canvas.clientHeight;
    if (canvas.width !== w * dpr || canvas.height !== h * dpr) { canvas.width = w * dpr; canvas.height = h * dpr; }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const near = Math.hypot(cam.pos[0] - seat.x, cam.pos[1] - seat.eye, cam.pos[2] - seat.z) < 1;
    S.render(ctx, w, h, polys, cam, { highlight: seat.id, hide: near ? seat.id : null });
  }
  function hud() {
    const m = seat.m, col = `hsl(${m.score * 1.2},70%,55%)`;
    const c = m.c === null ? 'Front row, nobody ahead' : m.c >= 0.09 ? 'Clear view over heads' : m.c >= 0.06 ? 'Just clears heads' : 'May block the bottom';
    $('hud').innerHTML = `<h2>Seat ${seat.id}<span class="score" style="color:${col}">${m.score}</span></h2>
      <div class="sub">${cfg.name} · ${cfg.variant} · row ${seat.row + 1} of ${room.rows.length}</div>
      <dl><dt>Screen fills</dt><dd>${Math.round(m.h)}° of your view (ideal ${cfg.idealAngle}°)</dd>
      <dt>Feels like</dt><dd>a ${m.tv}" TV from your couch</dd>
      <dt>Look up</dt><dd>${Math.round(m.neck)}° to the top edge</dd>
      <dt>Distance</dt><dd>${seat.z.toFixed(1)} m from the screen</dd>
      <dt>Head in front</dt><dd>${c}</dd></dl>
      <ul>${m.notes.map(n => `<li>${n}</li>`).join('')}</ul>`;
  }

  // drag to look, wheel/pinch to zoom
  const pts = new Map(); let pinch = 0;
  canvas.addEventListener('pointerdown', e => { canvas.setPointerCapture(e.pointerId); pts.set(e.pointerId, [e.clientX, e.clientY]); cancelAnimationFrame(anim); });
  canvas.addEventListener('pointermove', e => {
    if (!pts.has(e.pointerId)) return;
    const [x0, y0] = pts.get(e.pointerId); pts.set(e.pointerId, [e.clientX, e.clientY]);
    if (pts.size === 2) {
      const [a, b] = [...pts.values()], d = Math.hypot(a[0] - b[0], a[1] - b[1]);
      if (pinch) zoom(d / pinch); pinch = d; return;
    }
    const k = 0.004 / cam.zoom;
    cam.yaw -= (e.clientX - x0) * k;
    cam.pitch = Math.max(-1.3, Math.min(1.3, cam.pitch + (e.clientY - y0) * k));
    draw();
  });
  const up = e => { pts.delete(e.pointerId); pinch = 0; };
  canvas.addEventListener('pointerup', up); canvas.addEventListener('pointercancel', up);
  canvas.addEventListener('wheel', e => { e.preventDefault(); zoom(Math.exp(-e.deltaY * 0.0015)); }, { passive: false });
  function zoom(f) { cam.zoom = Math.max(0.6, Math.min(4, cam.zoom * f)); draw(); }

  // move between seats
  function move(dx, dr) {
    const row = room.rows[Math.max(0, Math.min(room.rows.length - 1, seat.row + dr))];
    let s;
    if (dr) s = row.seats.reduce((b, q) => (Math.abs(q.x - seat.x) < Math.abs(b.x - seat.x) ? q : b));
    else s = row.seats[Math.max(0, Math.min(row.seats.length - 1, row.seats.indexOf(seat) + dx))];
    if (s && s !== seat) open(s);
  }
  $('nav').onclick = e => { const d = e.target.dataset.d; if (d) move(...d.split(',').map(Number)); };
  addEventListener('keydown', e => {
    if (!$('view').classList.contains('open')) return;
    const k = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[e.key];
    if (k) { e.preventDefault(); move(...k); }
    if (e.key === 'Escape') close();
  });
  $('close').onclick = close;

  // share
  $('share').onclick = async () => {
    const text = `Seat ${seat.id} in ${cfg.name}: the screen fills ${Math.round(seat.m.h)}° of my view, like a ${seat.m.tv}" TV. Score ${seat.m.score}/100.`;
    try { if (navigator.share) return await navigator.share({ title: 'SeatSight', text, url: location.href }); } catch { return; }
    try { await navigator.clipboard.writeText(location.href); $('share').textContent = 'Link copied'; setTimeout(() => $('share').textContent = 'Share', 1500); } catch {}
  };

  // compare the same relative seat across formats
  $('cmp').onclick = () => { compareOn = !compareOn; $('compare').classList.toggle('open', compareOn); $('view').classList.toggle('cmp', compareOn); $('cmp').textContent = compareOn ? 'My seat' : 'Compare'; if (compareOn) drawCompare(); };
  function drawCompare() {
    const box = $('compare');
    box.innerHTML = COMPARE.map(id => `<figure><canvas></canvas><figcaption></figcaption></figure>`).join('');
    requestAnimationFrame(() => COMPARE.forEach((id, i) => {
      const r = S.build(presets.find(a => a.id === id)), s = S.similarSeat(room, seat, r);
      const fig = box.children[i], cv = fig.querySelector('canvas'), dpr = Math.min(2, devicePixelRatio || 1);
      cv.width = cv.clientWidth * dpr; cv.height = cv.clientHeight * dpr;
      const c2 = cv.getContext('2d'); c2.setTransform(dpr, 0, 0, dpr, 0, 0);
      S.render(c2, cv.clientWidth, cv.clientHeight, S.scene(r, { film: +st.film || 0, crowd: st.crowd, self: s.id }), S.eyeCam(r, s), { hide: s.id });
      fig.querySelector('figcaption').textContent = `${r.a.name} · seat ${s.id} · ${Math.round(s.m.h)}° · ${s.m.tv}" TV · ${s.m.score}`;
    }));
  }
})();
