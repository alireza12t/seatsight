# SeatSight

See the screen from your seat before you book.

Every time I book a movie I stare at a grid of little squares and guess. Row F in IMAX and row F in a VIP room are completely different views, and the seat map doesn't tell you that. SeatSight does: tap a seat and you fly into it in 3D and see the screen the way you'll see it.

**Try it:** https://alireza12t.github.io/seatsight/

## What it does
- Booking-style flow: pick a theatre, a movie, a showtime by screen type, then a seat (movies and theatres are made up)
- Tap a seat and you fly into it in 3D. Drag to look around
- Open seats are teal, taken seats have someone sitting in them, so you see who's in front of you
- Pinch out for the whole room from above, with a pin on your seat. Tap any open seat to move there
- A plain verdict (Great, Good, Okay, Not ideal) and four simple lines: screen size ("like a 147-inch TV at home"), neck comfort, heads in front, and how centered you are
- "Show best seats" and "Pick the best seat for me"
- Each screen crops the same movie frame, so IMAX looks taller and a scope movie gets bars on an IMAX screen
- Compare: the same spot in IMAX, UltraAVX, Regular and VIP side by side

## How accurate is it?
It's an estimate, and the app says so. Room sizes are typical values, not measured plans. The "heads in front" line uses an average seated eye height and also checks a person about 10 cm taller, because people vary. Real auditorium drawings would make it exact.

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
