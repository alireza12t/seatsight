# SeatSight

See the screen from your seat before you book.

Every time I book a movie I stare at a grid of little squares and guess. Row F in IMAX and row F in a VIP room are completely different views, and the seat map doesn't tell you that. SeatSight does: tap a seat and you fly into it in 3D and see the screen the way you'll see it.

**Try it:** https://alireza12t.github.io/seatsight/

## What it does
- Seat map like the booking apps, for IMAX (1.90:1 and the rare 1.43:1 GT), UltraAVX, Regular (large and small) and VIP rooms
- Tap a seat to fly from the back of the room into it. Drag to look around, pinch or scroll to zoom, arrows to try the seat next to you
- A seat score from 0 to 100 based on how much of your view the screen fills, how far you look up, how far off-center you are, and whether the head in front clears the bottom of the screen
- "Feels like a 140-inch TV from your couch" so the number means something
- Best seats heatmap and a best seat button
- Movie format: see the black bars when a scope movie plays on an IMAX screen
- Crowd mode: heads in the sold seats, so you can see who blocks the subtitles
- Compare: the same seat in IMAX, UltraAVX, Regular and VIP side by side
- Adjust the room (screen width, first row distance, rake) to match a theatre you know
- Share link with the room and seat in it

## Why it's cheap to add to a real app
- No 3D engine and no dependencies. A small renderer draws a few thousand flat polygons to a canvas. About 20 KB of JS on web, four Swift files on iOS
- Renders only when you move, so it sits idle at zero cost
- No server. Rooms are a small JSON file:

```json
{
  "id": "vip", "name": "VIP",
  "screen": { "width": 11, "aspect": 2.39, "bottom": 1.0 },
  "firstRow": 4.5, "rowPitch": 1.65, "riser": 0.55, "flatRows": 0,
  "seatWidth": 0.85, "aisle": 1.1, "idealAngle": 45,
  "rows": ["2-8-2", "2-10-2", "2-10-2"]
}
```
`"2-10-2"` means 2 seats, aisle, 10 seats, aisle, 2 seats. A theatre chain already has these numbers in its drawings.

## Honest notes
- The rooms here are **typical values, not measured plans** of any real auditorium. No chain publishes them. Real data would make it exact.
- Sold seats are fake.
- The scoring uses published guidance (THX, SMPTE, the auditorium C-value) with weights I picked. Details in [RESEARCH.md](RESEARCH.md).
- Not affiliated with Cineplex or any cinema chain.

## Run it
Web: any static server.
```bash
python3 -m http.server 8000 --directory docs
```
iOS (17+): open `ios/SeatSight.xcodeproj` (regenerate with `xcodegen` from `ios/`). The app bundles `docs/auditoriums.json`, so both platforms use the same rooms.

## Layout
- `docs/` web app, served by GitHub Pages (`engine.js` is the reusable part)
- `ios/` SwiftUI app (`Engine.swift` mirrors `engine.js`)
- [PLAN.md](PLAN.md) features and open items

MIT license.
