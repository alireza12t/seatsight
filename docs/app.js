// SeatSight web UI: movie > showtime > seat, then a 3D view from the seat.
(() => {
  const $ = id => document.getElementById(id);
  const S = SeatSight;
  const COMPARE = ['imax-190', 'ultraavx', 'regular-large', 'vip'];
  const TIMES = ['11:30', '13:15', '14:40', '16:10', '17:45', '19:00', '20:20', '21:40', '22:50'];
  const ABOUT = { IMAX: 'Biggest screen, steep seating', UltraAVX: 'Wall-to-wall screen, recliners', Regular: 'Classic screen', VIP: '19+, recliners, food to your seat' };
  const svg = p => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${p}</svg>`;
  const ICON = {
    screen: svg('<rect x="3" y="5" width="18" height="11" rx="2"/><path d="M8 20h8"/>'),
    neck: svg('<path d="M12 19V5M6 11l6-6 6 6"/>'),
    heads: svg('<circle cx="12" cy="8" r="3.5"/><path d="M5 20c1-4 4-6 7-6s6 2 7 6"/>'),
    center: svg('<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="2.5"/>'),
  };
  let D, movie, show, room, polys, seat, chosen, cam, anim = null, compareOn = false, roomMode = false;
  const st = { theatre: 'harbourfront', day: 0, best: false };

  const hash = s => { let h = 2166136261; for (const c of s) h = Math.imul(h ^ c.charCodeAt(0), 16777619); return h >>> 0; };
  const preset = id => D.auditoriums.find(a => a.id === id);
  const theatre = () => D.theatres.find(t => t.id === st.theatre);
  const date = k => new Date(Date.now() + k * 864e5);
  const dayName = k => k === 0 ? 'Today' : k === 1 ? 'Tomorrow' : date(k).toLocaleDateString('en-CA', { weekday: 'long' });
  const filmFor = (m, fmt) => m.film === 'imax' ? (fmt === 'IMAX' ? 0 : 2.39) : +m.film;
  const seatName = s => `Row ${room.rows[s.row].label} · Seat ${s.num}`;

  fetch('auditoriums.json').then(r => r.json()).then(d => {
    D = d;
    $('theatre').innerHTML = D.theatres.map(t => `<option value="${t.id}">${t.name}</option>`).join('');
    route(new URLSearchParams(location.hash.slice(1)));
  });

  function route(h) {
    if (D.theatres.some(t => t.id === h.get('t'))) st.theatre = h.get('t');
    st.day = Math.max(0, Math.min(6, +h.get('d') || 0));
    $('theatre').value = st.theatre;
    movie = D.movies.find(m => m.id === h.get('m'));
    if (!movie) return go('movies');
    if (!movie.formats.includes(h.get('fmt')) || !h.get('at')) return go('times');
    openShow(h.get('fmt'), h.get('at'));
    const s = room.seats.find(s => s.id === h.get('seat') && !s.sold);
    if (s) { chosen = s; drawMap(); open(s); }
  }

  // ---------- pages ----------
  let page = 'movies';
  function go(p) {
    page = p;
    ['movies', 'times', 'seats'].forEach(x => $('p-' + x).hidden = x !== p);
    $('back').hidden = p === 'movies';
    $('place').hidden = p === 'seats';
    $('dock').hidden = p !== 'seats';
    if (p === 'movies') { $('title').innerHTML = '<span class="brand">Seat<i>Sight</i></span>'; drawMovies(); setHash({}); }
    if (p === 'times') { $('title').innerHTML = ''; drawTimes(); setHash({ m: movie.id }); }
    if (p === 'seats') $('title').innerHTML = `<b>${movie.title}</b><span>${show.fmt} · ${dayName(st.day)} ${show.at} · ${theatre().name}</span>`;
    scrollTo(0, 0);
  }
  $('back').onclick = () => { if (page === 'seats') { chosen = null; go('times'); } else go('movies'); };
  $('theatre').onchange = e => { st.theatre = e.target.value; if (page === 'times') go('times'); };

  const poster = m => `<div class="poster" style="background:linear-gradient(160deg,${m.colors[0]} 35%,${m.colors[1]}66);--c1:${m.colors[1]}"><b>${m.title}</b></div>`;
  const meta = m => `${m.genre} · ${Math.floor(m.runtime / 60)}h ${m.runtime % 60}m · ${m.rating}`;

  function drawMovies() {
    $('movies').innerHTML = D.movies.map(m => `<button class="movie" data-m="${m.id}">${poster(m)}<div class="meta">${meta(m)}</div></button>`).join('');
  }
  $('movies').onclick = e => { const b = e.target.closest('[data-m]'); if (b) { movie = D.movies.find(m => m.id === b.dataset.m); go('times'); } };

  const times = fmt => { const h = hash(movie.id + st.theatre + st.day + fmt); return Array.from({ length: fmt === 'VIP' ? 2 : 3 }, (_, k) => TIMES[(h % 4) + k * 2]); };
  function drawTimes() {
    $('hero').innerHTML = `${poster(movie)}<div><h1>${movie.title}</h1><div class="dim">${meta(movie)}</div>${movie.film === 'imax' ? '<div class="dim">Filmed for IMAX</div>' : ''}</div>`;
    $('days').innerHTML = Array.from({ length: 7 }, (_, k) => `<button data-d="${k}" aria-pressed="${k === st.day}">${k < 2 ? dayName(k) : date(k).toLocaleDateString('en-CA', { weekday: 'short' })}<b>${date(k).getDate()}</b></button>`).join('');
    $('formats').innerHTML = movie.formats.map(fmt => `<div class="fmt"><h3>${fmt}</h3><p>${ABOUT[fmt]}</p>
      <div class="times">${times(fmt).map(t => `<button data-fmt="${fmt}" data-at="${t}">${t}</button>`).join('')}</div></div>`).join('');
  }
  $('days').onclick = e => { const b = e.target.closest('[data-d]'); if (b) { st.day = +b.dataset.d; drawTimes(); } };
  $('formats').onclick = e => { const b = e.target.dataset; if (b.at) { chosen = null; openShow(b.fmt, b.at); setHash(); } };

  function openShow(fmt, at) {
    show = { fmt, at, film: filmFor(movie, fmt), seed: movie.id + st.theatre + st.day + fmt + at };
    room = S.build(preset(theatre().rooms[fmt]), show.seed);
    go('seats');
    drawMap();
  }
  function setHash(o = { all: true }) {
    const h = new URLSearchParams({ t: st.theatre, d: st.day });
    if (o.m) h.set('m', o.m);
    if (o.all && movie && show) { h.set('m', movie.id); h.set('fmt', show.fmt); h.set('at', show.at); if (chosen) h.set('seat', chosen.id); }
    history.replaceState(null, '', '#' + h);
  }

  // ---------- seat map ----------
  function drawMap() {
    const map = $('map');
    const cols = Math.max(...room.rows.map(r => r.seats.length + (r.parts.length - 1) * 1.2)) + 2.5;
    map.style.setProperty('--s', Math.max(15, Math.min(24, (Math.min(map.clientWidth, 940) - 20) / cols - 3)) + 'px');
    map.classList.toggle('best', st.best);
    map.innerHTML = '<div class="grid"><div class="screen"><span>SCREEN</span></div>' + room.rows.map(r => {
      let html = `<div class="row"><b>${r.label}</b>`, p = 0;
      r.seats.forEach(s => {
        if (s.section !== p) { html += '<span class="gap"></span>'; p = s.section; }
        const cls = `seat${s.sold ? ' taken' : ''}${s.m.score >= 85 ? ' top' : ''}${s === chosen ? ' mine' : ''}`;
        html += `<button class="${cls}" data-id="${s.id}"${s.sold ? ' disabled' : ''} aria-label="${seatName(s)}, ${s.sold ? 'taken' : s.m.verdict}" title="${seatName(s)} · ${s.sold ? 'Taken' : s.m.verdict}"></button>`;
      });
      return html + `<b>${r.label}</b></div>`;
    }).join('') + '</div>';
    map.scrollLeft = (map.scrollWidth - map.clientWidth) / 2;
    dock();
  }
  function dock() {
    if (!chosen) { $('what').innerHTML = '<b>Pick a seat</b><span class="dim">Tap any open seat to see your view</span>'; $('preview').disabled = true; return; }
    $('what').innerHTML = `<b>${seatName(chosen)}</b><span class="verdict ${chosen.m.tone}">${chosen.m.verdict}</span>`;
    $('preview').disabled = false;
  }
  $('map').addEventListener('click', e => { const s = room.seats.find(s => s.id === e.target.dataset?.id); if (s && !s.sold) { chosen = s; drawMap(); setHash(); open(s); } });
  $('bestOn').onclick = e => { st.best = !st.best; e.currentTarget.setAttribute('aria-pressed', st.best); drawMap(); };
  $('pickBest').onclick = () => { chosen = room.best; drawMap(); setHash(); open(room.best); };
  $('preview').onclick = () => chosen && open(chosen);
  addEventListener('resize', () => { if (page === 'seats') drawMap(); draw(); });

  // ---------- 3D view ----------
  const canvas = $('c'), ctx = canvas.getContext('2d');
  const isOpen = () => $('view').classList.contains('open');
  function open(s) {
    const was = isOpen();
    seat = s;
    polys = S.scene(room, { film: show.film, self: s.id });
    $('view').classList.add('open');
    document.body.style.overflow = 'hidden';
    setRoom(false, true);
    fly(was && cam ? cam : S.overCam(room), S.eyeCam(room, s), was ? 700 : 1400);
    sheet();
    if (!was) hint('Drag to look around. Pinch out to see the whole room.');
    if (compareOn) drawCompare();
  }
  function close() {
    $('view').classList.remove('open', 'cmp', 'room'); document.body.style.overflow = '';
    compareOn = false; $('compare').classList.remove('open');
  }
  function setRoom(on, quiet) {
    roomMode = on;
    $('view').classList.toggle('room', on);
    $('mYou').setAttribute('aria-pressed', !on); $('mRoom').setAttribute('aria-pressed', on);
    if (!quiet) { fly(cam, on ? S.overCam(room) : S.eyeCam(room, seat), 900); if (on) hint('Tap any teal seat to move there'); }
  }
  $('mYou').onclick = () => roomMode && setRoom(false);
  $('mRoom').onclick = () => !roomMode && setRoom(true);
  function hint(t) { const el = $('hint'); el.textContent = t; el.style.opacity = 1; clearTimeout(el._t); el._t = setTimeout(() => el.style.opacity = 0, 3500); }
  function toast(t) { const el = $('toast'); el.textContent = t; el.classList.add('show'); clearTimeout(el._t); el._t = setTimeout(() => el.classList.remove('show'), 1400); }

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
    S.centerY = w < 640 && !roomMode && !compareOn ? 0.36 : 0.5;
    const near = Math.hypot(cam.pos[0] - seat.x, cam.pos[1] - seat.eye, cam.pos[2] - seat.z) < 1;
    S.render(ctx, w, h, polys, cam, { highlight: seat.id, hide: near ? seat.id : null, map: roomMode, pin: roomMode ? [seat.x, seat.eye + 0.9, seat.z] : null });
  }
  function sheet() {
    const m = seat.m, isChosen = chosen === seat;
    $('sheet').innerHTML = `<div class="top"><div><b>${seatName(seat)}</b><span class="dim">${show.fmt} · ${movie.title} · ${show.at}</span></div><span class="verdict ${m.tone}">${m.verdict}</span></div>
      <ul class="facts">${m.facts.map(f => `<li class="${f.ok ? '' : 'warn'}"><span class="ico">${ICON[f.k]}</span><div>${f.t}${f.sub ? `<small>${f.sub}</small>` : ''}</div></li>`).join('')}</ul>
      <button class="more" id="more">${(n => n ? n + (n > 1 ? ' things' : ' thing') + ' to know · ' : '')(m.facts.filter(f => !f.ok).length)}See details ›</button>
      <div class="est">An estimate from a typical room and average height. Real rooms and people vary.</div>
      <button class="cta" id="choose">${isChosen ? 'Back to seat map' : 'Choose this seat'}</button>`;
    $('sheet').classList.toggle('mini', innerWidth < 640);
    $('more').onclick = () => $('sheet').classList.remove('mini');
    $('choose').onclick = () => { chosen = seat; drawMap(); setHash(); close(); };
  }

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
      S.centerY = r0(); const r = canvas.getBoundingClientRect(), id = S.pick(r.width, r.height, polys, cam, e.clientX - r.left, e.clientY - r.top);
      const s = id && room.seats.find(s => s.id === id);
      if (s && s.sold) toast(`${seatName(s)} is taken`);
      else if (s && s !== seat) open(s);
    }
    down = null;
  };
  canvas.addEventListener('pointerup', up); canvas.addEventListener('pointercancel', up);
  canvas.addEventListener('wheel', e => { e.preventDefault(); zoom(Math.exp(-e.deltaY * 0.0015)); }, { passive: false });
  function r0() { return canvas.clientWidth < 640 && !roomMode ? 0.36 : 0.5; }
  function zoom(f) {
    if (!roomMode && cam.zoom * f < 0.7) { setRoom(true); pinch = 0; return; }
    cam.zoom = Math.max(0.6, Math.min(4, cam.zoom * f)); draw();
  }

  // arrow keys move to the next open seat
  function move(dx, dr) {
    let s = seat;
    for (let n = 0; n < 40; n++) {
      const row = room.rows[s.row + dr];
      if (!row) return;
      s = dr ? row.seats.reduce((b, q) => (Math.abs(q.x - seat.x) < Math.abs(b.x - seat.x) ? q : b)) : row.seats[row.seats.indexOf(s) + dx];
      if (!s) return;
      if (!s.sold) return open(s);
    }
  }
  addEventListener('keydown', e => {
    if (!isOpen()) return;
    const k = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[e.key];
    if (k) { e.preventDefault(); move(...k); }
    if (e.key === 'Escape') close();
  });
  $('close').onclick = close;

  $('share').onclick = async () => {
    setHash();
    const text = `${seatName(seat)} for ${movie.title} in ${show.fmt}: ${seat.m.verdict.toLowerCase()}, like a ${seat.m.tv}" TV.`;
    try { if (navigator.share) return await navigator.share({ title: 'SeatSight', text, url: location.href }); } catch { return; }
    try { await navigator.clipboard.writeText(location.href); toast('Link copied'); } catch {}
  };

  // the same spot in each screen type
  $('cmp').onclick = () => {
    compareOn = !compareOn;
    $('compare').classList.toggle('open', compareOn); $('view').classList.toggle('cmp', compareOn);
    if (compareOn) drawCompare();
  };
  function drawCompare() {
    const box = $('compare');
    box.innerHTML = COMPARE.map(() => '<figure><canvas></canvas><figcaption></figcaption></figure>').join('');
    requestAnimationFrame(() => COMPARE.forEach((id, i) => {
      const r = S.build(preset(id), show.seed), s = S.similarSeat(room, seat, r);
      const fig = box.children[i], cv = fig.querySelector('canvas'), dpr = Math.min(2, devicePixelRatio || 1);
      cv.width = cv.clientWidth * dpr; cv.height = cv.clientHeight * dpr;
      S.centerY = 0.5; const c2 = cv.getContext('2d'); c2.setTransform(dpr, 0, 0, dpr, 0, 0);
      S.render(c2, cv.clientWidth, cv.clientHeight, S.scene(r, { film: filmFor(movie, r.a.format), self: s.id }), S.eyeCam(r, s), { hide: s.id });
      fig.querySelector('figcaption').innerHTML = `<b>${r.a.format}</b><span class="${s.m.tone}">${s.m.verdict}</span> · like a ${s.m.tv}" TV`;
    }));
  }
})();
