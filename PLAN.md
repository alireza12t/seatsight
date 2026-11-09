# SeatSight plan (handover file, read first)

Pick a seat, see the screen from it. Web + iOS, no server, no 3D engine.

## v1.0.0 features
- [x] Shared room format (`docs/auditoriums.json`): screen size and aspect, row spacing, rake, rows as `"4-12-4"` strings
- [x] 6 typical presets: IMAX 1.90, IMAX GT 1.43, UltraAVX, Regular large, Regular small, VIP
- [x] Seat map like the booking apps, with sold seats (demo data, seeded so it's stable)
- [x] Tap a seat, fly from the back of the room into your seat in 3D
- [x] Drag to look around, scroll/pinch to zoom
- [x] Seat score 0 to 100: screen angle vs format's ideal, neck tilt, off-axis, head in front (C-value)
- [x] "Best seats" heatmap on the map, best seat badge
- [x] TV equivalent: "like a 140-inch TV from your couch"
- [x] Film format toggle: a 2.39 movie on an IMAX 1.90 screen shows bars, 1.43 IMAX footage fills a GT screen
- [x] Crowd toggle: heads in sold seats, see who blocks the subtitles
- [x] Compare: same relative seat in IMAX, UltraAVX, Regular, VIP side by side
- [x] Adjust room sliders (screen width, first row distance, rake) to match a theatre you know
- [x] Share link with room + seat in the URL hash (web), share button on iOS
- [x] Web: GitHub Pages from `docs/`, zero dependencies
- [x] iOS: SwiftUI `Canvas`, iOS 17+, XcodeGen project

## v1.1 (2026-11-08)
- [x] Flow: theatre, movie, showtime grouped by screen type, then seats (made-up movies and theatres, original design)
- [x] Two theatres with different rooms (Harbourfront has the 1.43 GT IMAX and a large Regular, Westgate has 1.90 IMAX and a small Regular)
- [x] Screens look different now: one fixed picture cropped by each frame, bare screen shows as grey bars, HUD says how much more picture you get
- [x] Room view: zoom out to see the room from above, your seat yellow, taken seats dark, tap to switch
- [x] Taken seats show in 3D and can't be picked; arrows skip taken seats

## v1.2 (2026-11-08): buyer-friendly redesign
- [x] Modern UI on web and iOS: clean dark design, bottom dock, bottom sheet in 3D, compact on phones
- [x] Verdict + four plain lines replace degrees and meters; worded as estimates; tall-person check for heads in front
- [x] Open seats teal, taken seats show a person, your seat coral with a pin in the room view
- [x] Removed room sliders, crowd toggle, technical format text
- [x] Bigger tappable seats on phones (map scrolls sideways, centered)

## Open items / next
- [ ] Real room data. Ask Cineplex (or theatre fans) for measured drawings per auditorium
- [ ] iOS gyro look-around (CoreMotion)
- [ ] Curved IMAX screens
- [ ] Staggered seats (offset rows) in the C-value check
- [ ] Short demo video for the Cineplex pitch post
- [x] Public repo alireza12t/seatsight with GitHub Pages from main /docs (2026-11-08)

## Layout
- `docs/` web app (index.html, engine.js, app.js, auditoriums.json)
- `ios/` SwiftUI app, `project.yml` for XcodeGen; bundles `docs/auditoriums.json`
