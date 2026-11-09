// SeatSight web UI: movie > showtime > seat flow, 3D seat view with room overview, compare, share.
(() => {
  const $ = id => document.getElementById(id);
  const S = SeatSight;
  const COMPARE = ['imax-190', 'ultraavx', 'regular-large', 'vip'];
  const TIMES = ['11:30', '13:15', '14:40', '16:10', '17:45', '19:00', '20:20', '21:40', '22:50'];
  const WHY = {
    IMAX: 'Biggest, tallest screen and steep seating. Scenes shot for IMAX fill more of the frame.',
    UltraAVX: 'Wall-to-wall screen, reclining seats, big sound.',
    Regular: 'Standard screen and seats.',
    VIP: '19+, full recliners, food to your seat. Smaller screen.',
  };
  let D, movie, show, cfg, room, polys, seat, cam, anim = null, compareOn = false, overview = false;
  const st = { theatre: 'harbourfront', day: 0, heat: false, crowd: false };

  const hash = s => { let h = 2166136261; for (const c of s) h = Math.imul(h ^ c.charCodeAt(0), 16777619); return h >>> 0; };
  const preset = id => D.auditoriums.find(a => a.id === id);
  const theatre = () => D.theatres.find(t => t.id === st.theatre);
  const dayLabel = k => k === 0 ? 'Today' : k === 1 ? 'Tomorrow' : new Date(Date.now() + k * 864e5).toLocaleDateString('en-CA', { weekday: 'short', day: 'numeric' });
  const filmFor = (m, fmt) => m.film === 'imax' ? (fmt === 'IMAX' ? 0 : 2.39) : +m.film;
  const fmtName = m => m.film === 'imax' ? 'Filmed for IMAX' : m.film === '2.39' ? 'Scope 2.39:1' : 'Flat 1.85:1';

  fetch('auditoriums.json').then(r => r.json()).then(d => {
    D = d;
    $('theatre').innerHTML = D.theatres.map(t => `<option value="${t.id}">${t.name}</option>`).join('');
    route(new URLSearchParams(location.hash.slice(1)));
  });

  function route(h) {
    if (D.theatres.some(t => t.id === h.get('t'))) st.theatre = h.get('t');
    st.day = Math.max(0, Math.min(6, +h.get('d') || 0));
    $('theatre').value = st.theatre;
    const m = D.movies.find(m => m.id === h.get('m'));
    if (!m) return go('movies');
    movie = m;
    if (!h.get('fmt') || !h.get('at') || !m.formats.includes(h.get('fmt'))) return go('times');
    openShow(h.get('fmt'), h.get('at'), h.get('sw') && { w: +h.get('sw'), f: +h.get('fr'), k: +h.get('rk') });
    const s = h.get('seat') && room.seats.find(s => s.id === h.get('seat'));
    if (s) { seat = s; drawMap(); open(s); }
  }

  // ---------- steps ----------
  function go(step) {
    ['movies', 'times', 'seats'].forEach(s => $('s-' + s).hidden = s !== step);
    $('tray').hidden = step !== 'seats' || !seat;
    const names = [['movies', 'Movie'], ['times', 'Showtime'], ['seats', 'Seats']];
    const at = names.findIndex(n => n[0] === step);
    $('steps').innerHTML = names.map(([id, n], i) => `<button data-step="${id}" class="${i === at ? 'on' : ''}" ${i > at ? 'disabled' : ''}>${i + 1}. ${n}</button>`).join('<span>›</span>');
    if (step === 'movies') drawMovies();
    if (step === 'times') drawTimes();
    if (step !== 'seats') setHash({ m: step === 'times' ? movie.id : null });
    scrollTo(0, 0);
  }
  $('steps').onclick = e => { const s = e.target.dataset.step; if (s) { if (s !== 'seats') seat = null; go(s); } };
  $('theatre').onchange = e => {
    st.theatre = e.target.value;
    if (!$('s-seats').hidden) { seat = null; go('times'); } else if (!$('s-times').hidden) drawTimes();
  };

  const poster = (m, small) => `<div class="poster" style="background:linear-gradient(160deg,${m.colors[0]} 30%,${m.colors[1]}55);--c1:${m.colors[1]}">${!small && m.film === 'imax' ? '<span class="tag">FILMED FOR IMAX</span>' : ''}<b>${m.title}</b></div>`;
  const meta = m => `${m.genre} · ${Math.floor(m.runtime / 60)}h ${m.runtime % 60}m · ${m.rating}`;

  function drawMovies() {
    $('movies').innerHTML = D.movies.map(m => `<button class="movie" data-m="${m.id}">${poster(m)}<div class="meta">${meta(m)}</div></button>`).join('');
  }
  $('movies').onclick = e => { const b = e.target.closest('[data-m]'); if (b) { movie = D.movies.find(m => m.id === b.dataset.m); go('times'); } };

  function showtimes(fmt) {
    const h = hash(movie.id + st.theatre + st.day + fmt), n = fmt === 'VIP' ? 2 : 3;
    return Array.from({ length: n }, (_, k) => TIMES[(h % 4) + k * 2]);
  }
  function drawTimes() {
    $('mhead').innerHTML = `${poster(movie, true)}<div><h2>${movie.title}</h2><p>${meta(movie)} · ${fmtName(movie)}</p><p>${theatre().name}</p></div>`;
    $('days').innerHTML = Array.from({ length: 7 }, (_, k) => `<button data-d="${k}" aria-pressed="${k === st.day}">${dayLabel(k)}</button>`).join('');
    $('formats').innerHTML = movie.formats.map(fmt => {
      const a = preset(theatre().rooms[fmt]), aud = Object.keys(theatre().rooms).indexOf(fmt) + 1;
      return `<div class="fmt"><h3>${a.name} <small>${a.variant} · Auditorium ${aud} · ${a.screen.width} m screen</small></h3>
        <div class="why">${WHY[fmt]}</div>
        <div class="times">${showtimes(fmt).map(t => `<button data-fmt="${fmt}" data-at="${t}">${t}</button>`).join('')}</div></div>`;
    }).join('');
  }
  $('days').onclick = e => { const d = e.target.dataset.d; if (d) { st.day = +d; drawTimes(); } };
  $('formats').onclick = e => { const b = e.target.dataset; if (b.at) { seat = null; openShow(b.fmt, b.at); } };

  // ---------- seats ----------
  function openShow(fmt, at, tw) {
    const a = preset(theatre().rooms[fmt]);
    show = { fmt, at, film: filmFor(movie, fmt), seed: movie.id + st.theatre + st.day + fmt + at };
    cfg = structuredClone(a);
    if (tw) { cfg.screen.width = tw.w; cfg.firstRow = tw.f; cfg.riser = tw.k; }
    [['tw', cfg.screen.width], ['tf', cfg.firstRow], ['tk', cfg.riser]].forEach(([id, v]) => setSlider(id, v));
    rebuild();
    $('shead').innerHTML = `${poster(movie, true)}<div><h2>${movie.title}</h2><p>${cfg.name} · ${cfg.variant}</p><p>${dayLabel(st.day)} ${at} · ${theatre().name}</p></div>`;
    go('seats');
    setHash();
  }
  function setSlider(id, v) { $(id).value = v; $(id).nextElementSibling.textContent = v + ' m'; }
  function tweaked() { const b = preset(cfg.id); return cfg.screen.width !== b.screen.width || cfg.firstRow !== b.firstRow || cfg.riser !== b.riser; }
  function setHash(over = {}) {
    const h = new URLSearchParams({ t: st.theatre, d: st.day });
    const m = 'm' in over ? over.m : movie?.id;
    if (m) h.set('m', m);
    if (!('m' in over) && show) {
      h.set('fmt', show.fmt); h.set('at', show.at);
      if (seat) h.set('seat', seat.id);
      if (tweaked()) { h.set('sw', cfg.screen.width); h.set('fr', cfg.firstRow); h.set('rk', cfg.riser); }
    }
    history.replaceState(null, '', '#' + h);
  }

  function rebuild() {
    room = S.build(cfg, show.seed);
    if (seat) seat = room.seats.find(s => s.id === seat.id && !s.sold) || null;
    drawMap();
  }
  function drawMap() {
    const map = $('map');
    const cols = Math.max(...room.rows.map(r => r.seats.length + (r.parts.length - 1) * 1.4)) + 3;
    map.style.setProperty('--s', Math.max(11, Math.min(26, (map.clientWidth - 24) / cols - 2)) + 'px');
    const heat = s => `hsl(${s.m.score * 1.2},65%,45%)`;
    map.innerHTML = `<div class="screen" style="width:${Math.min(92, 40 + room.W * 2.2)}%">${cfg.name} screen · ${room.W.toFixed(1)} m wide</div>` +
      room.rows.map(r => {
        let html = `<div class="row"><b>${r.label}</b>`, p = 0;
        r.seats.forEach(s => {
          if (s.section !== p) { html += '<span class="aisle"></span>'; p = s.section; }
          const cls = `seat${s.sold ? ' sold' : ''}${s === room.best ? ' best' : ''}${s === seat ? ' sel' : ''}`;
          const bg = st.heat && !s.sold ? ` style="background:${heat(s)}"` : '';
          html += `<button class="${cls}" data-id="${s.id}"${bg}${s.sold ? ' disabled' : ''} title="${s.id} · ${s.sold ? 'taken' : 'score ' + s.m.score}" aria-label="Seat ${s.id}, ${s.sold ? 'taken' : 'score ' + s.m.score}"></button>`;
        });
        return html + `<b>${r.label}</b></div>`;
      }).join('') +
      `<div class="legend"><span><i style="background:var(--seat)"></i>Available</span><span><i style="background:var(--sold)"></i>Taken</span><span><i style="background:var(--accent)"></i>Your seat</span><span><i style="box-shadow:inset 0 0 0 2px var(--accent)"></i>Best seat</span>${st.heat ? '<span><i style="background:hsl(0,65%,45%)"></i>Poor → <i style="background:hsl(120,65%,45%)"></i>Great</span>' : ''}</div>`;
    $('best').textContent = `Best open seat: ${room.best.id} (${room.best.m.score})`;
    tray();
  }
  function tray() {
    $('tray').hidden = !seat || $('s-seats').hidden;
    if (seat) $('sum').innerHTML = `<b>Seat ${seat.id}</b> · score ${seat.m.score}<br>${cfg.name} · ${dayLabel(st.day)} ${show.at}`;
  }

  $('map').addEventListener('click', e => { const id = e.target.dataset?.id; if (id) select(room.seats.find(s => s.id === id), true); });
  $('heat').onclick = e => { st.heat = !st.heat; e.target.setAttribute('aria-pressed', st.heat); drawMap(); };
  $('crowd').onclick = e => { st.crowd = !st.crowd; e.target.setAttribute('aria-pressed', st.crowd); };
  $('best').onclick = () => select(room.best, true);
  $('see').onclick = () => seat && open(seat);
  [['tw', v => cfg.screen.width = v], ['tf', v => cfg.firstRow = v], ['tk', v => cfg.riser = v]].forEach(([id, set]) => {
    $(id).oninput = e => { const v = +e.target.value; set(v); setSlider(id, v); rebuild(); setHash(); };
  });
  addEventListener('resize', () => { if (room && !$('s-seats').hidden) drawMap(); draw(); });

  function select(s, view) {
    if (!s || s.sold) return;
    seat = s; drawMap(); setHash();
    if (view) open(s);
  }

  // ---------- 3D view ----------
  const canvas = $('c'), ctx = canvas.getContext('2d');
  const isOpen = () => $('view').classList.contains('open');
  function open(s) {
    const was = isOpen();
    seat = s;
    polys = S.scene(room, { film: show.film, crowd: st.crowd, self: s.id });
    $('view').classList.add('open');
    document.body.style.overflow = 'hidden';
    setOverview(false);
    fly(was && cam ? cam : S.overCam(room), S.eyeCam(room, s), was ? 700 : 1400);
    hud(); drawMap(); setHash();
    if (compareOn) drawCompare();
  }
  function close() {
    $('view').classList.remove('open', 'cmp'); document.body.style.overflow = '';
    compareOn = false; $('compare').classList.remove('open'); $('cmp').textContent = 'Compare';
    drawMap();
  }
  function setOverview(on) {
    overview = on;
    $('view').classList.toggle('ov', on);
    $('ov').setAttribute('aria-pressed', on); $('ov').textContent = on ? 'My seat' : 'Room view';
    $('hint').textContent = on ? 'Yellow is your seat, dark seats are taken. Tap an open seat to switch.' : 'Drag to look around · pinch or scroll out for the room view · tap a seat to switch';
  }
  $('ov').onclick = () => { setOverview(!overview); fly(cam, overview ? S.overCam(room) : S.eyeCam(room, seat), 900); };
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
    if (!isOpen() || !cam) return;
    const dpr = Math.min(2, devicePixelRatio || 1), w = canvas.clientWidth, h = canvas.clientHeight;
    if (canvas.width !== w * dpr || canvas.height !== h * dpr) { canvas.width = w * dpr; canvas.height = h * dpr; }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const near = Math.hypot(cam.pos[0] - seat.x, cam.pos[1] - seat.eye, cam.pos[2] - seat.z) < 1;
    S.render(ctx, w, h, polys, cam, { highlight: seat.id, hide: near ? seat.id : null, map: overview });
  }
  function pictureNote() {
    const aspect = cfg.screen.aspect;
    if (!show.film) return `Filmed for IMAX, fills this ${aspect}:1 screen. ${Math.round((2.39 / aspect - 1) * 100)}% more picture than a 2.39 room`;
    if (Math.abs(show.film - aspect) < 0.06) return `${show.film}:1 movie fills the screen`;
    return show.film > aspect ? `${show.film}:1 movie, bars above and below` : `${show.film}:1 movie, bars on the sides`;
  }
  function hud() {
    const m = seat.m, col = `hsl(${m.score * 1.2},70%,55%)`;
    const c = m.c === null ? 'Front row, nobody ahead' : m.c >= 0.09 ? 'Clear view over heads' : m.c >= 0.06 ? 'Just clears heads' : 'May block the bottom';
    $('hud').innerHTML = `<h2>Seat ${seat.id}<span class="score" style="color:${col}">${m.score}</span></h2>
      <div class="sub">${movie.title} · ${cfg.name} ${cfg.variant} · row ${seat.row + 1} of ${room.rows.length}</div>
      <dl><dt>Screen fills</dt><dd>${Math.round(m.h)}° of your view (ideal ${cfg.idealAngle}°)</dd>
      <dt>Feels like</dt><dd>a ${m.tv}" TV from your couch</dd>
      <dt>Picture</dt><dd>${pictureNote()}</dd>
      <dt>Look up</dt><dd>${Math.round(m.neck)}° to the top edge</dd>
      <dt>Distance</dt><dd>${seat.z.toFixed(1)} m from the screen</dd>
      <dt>Head in front</dt><dd>${c}</dd></dl>
      <ul>${m.notes.map(n => `<li>${n}</li>`).join('')}</ul>`;
  }
  function toast(t) { const el = $('toast'); el.textContent = t; el.classList.add('show'); clearTimeout(el._t); el._t = setTimeout(() => el.classList.remove('show'), 1400); }

  // drag to look, wheel/pinch to zoom, tap a seat to switch
  const pts = new Map(); let pinch = 0, down = null;
  canvas.addEventListener('pointerdown', e => {
    canvas.setPointerCapture(e.pointerId); pts.set(e.pointerId, [e.clientX, e.clientY]);
    down = pts.size === 1 ? { x: e.clientX, y: e.clientY, t: performance.now() } : null;
    cancelAnimationFrame(anim);
  });
  canvas.addEventListener('pointermove', e => {
    if (!pts.has(e.pointerId)) return;
    const [x0, y0] = pts.get(e.pointerId); pts.set(e.pointerId, [e.clientX, e.clientY]);
    if (pts.size === 2) {
      const [a, b] = [...pts.values()], d = Math.hypot(a[0] - b[0], a[1] - b[1]);
      if (pinch) zoom(d / pinch); pinch = d; return;
    }
    const k = 0.004 / cam.zoom;
    cam.yaw -= (e.clientX - x0) * k;
    cam.pitch = Math.max(-1.4, Math.min(1.3, cam.pitch + (e.clientY - y0) * k));
    draw();
  });
  const up = e => {
    pts.delete(e.pointerId); pinch = 0;
    if (down && Math.hypot(e.clientX - down.x, e.clientY - down.y) < 6 && performance.now() - down.t < 400) {
      const r = canvas.getBoundingClientRect(), id = S.pick(r.width, r.height, polys, cam, e.clientX - r.left, e.clientY - r.top);
      const s = id && room.seats.find(s => s.id === id);
      if (s && s.sold) toast(`Seat ${s.id} is taken`);
      else if (s && s !== seat) open(s);
    }
    down = null;
  };
  canvas.addEventListener('pointerup', up); canvas.addEventListener('pointercancel', up);
  canvas.addEventListener('wheel', e => { e.preventDefault(); zoom(Math.exp(-e.deltaY * 0.0015)); }, { passive: false });
  function zoom(f) {
    if (!overview && cam.zoom * f < 0.7) { setOverview(true); fly(cam, S.overCam(room), 900); pinch = 0; return; }
    cam.zoom = Math.max(0.6, Math.min(4, cam.zoom * f)); draw();
  }

  function move(dx, dr) {
    let s = seat;
    for (let n = 0; n < 30; n++) {
      const row = room.rows[Math.max(0, Math.min(room.rows.length - 1, s.row + dr))];
      const next = dr ? row.seats.filter(q => !q.sold || q === seat).reduce((b, q) => (Math.abs(q.x - seat.x) < Math.abs(b.x - seat.x) ? q : b), row.seats[0])
        : row.seats[Math.max(0, Math.min(row.seats.length - 1, row.seats.indexOf(s) + dx))];
      if (next === s) return;
      s = next;
      if (!s.sold) return open(s);
    }
  }
  $('nav').onclick = e => { const d = e.target.dataset.d; if (d) move(...d.split(',').map(Number)); };
  addEventListener('keydown', e => {
    if (!isOpen()) return;
    const k = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[e.key];
    if (k) { e.preventDefault(); move(...k); }
    if (e.key === 'Escape') close();
  });
  $('close').onclick = close;

  $('share').onclick = async () => {
    const text = `Seat ${seat.id} for ${movie.title} in ${cfg.name}: the screen fills ${Math.round(seat.m.h)}° of my view, like a ${seat.m.tv}" TV. Score ${seat.m.score}/100.`;
    try { if (navigator.share) return await navigator.share({ title: 'SeatSight', text, url: location.href }); } catch { return; }
    try { await navigator.clipboard.writeText(location.href); toast('Link copied'); } catch {}
  };

  // same relative seat across formats, same movie
  $('cmp').onclick = () => {
    compareOn = !compareOn;
    $('compare').classList.toggle('open', compareOn); $('view').classList.toggle('cmp', compareOn);
    $('cmp').textContent = compareOn ? 'My seat' : 'Compare';
    if (compareOn) drawCompare();
  };
  function drawCompare() {
    const box = $('compare');
    box.innerHTML = COMPARE.map(() => '<figure><canvas></canvas><figcaption></figcaption></figure>').join('');
    requestAnimationFrame(() => COMPARE.forEach((id, i) => {
      const r = S.build(preset(id), show.seed), s = S.similarSeat(room, seat, r);
      const fig = box.children[i], cv = fig.querySelector('canvas'), dpr = Math.min(2, devicePixelRatio || 1);
      cv.width = cv.clientWidth * dpr; cv.height = cv.clientHeight * dpr;
      const c2 = cv.getContext('2d'); c2.setTransform(dpr, 0, 0, dpr, 0, 0);
      S.render(c2, cv.clientWidth, cv.clientHeight, S.scene(r, { film: filmFor(movie, r.a.format), crowd: st.crowd, self: s.id }), S.eyeCam(r, s), { hide: s.id });
      fig.querySelector('figcaption').textContent = `${r.a.name} ${r.a.variant.split(',')[0]} · seat ${s.id} · ${Math.round(s.m.h)}° · ${s.m.tv}" TV · ${s.m.score}`;
    }));
  }
})();
