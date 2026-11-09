# Research (2026-11-08)

## The problem
Cineplex's web and iOS seat pickers show a flat grid. You can't tell how big the screen will look from row F in IMAX vs row F in a VIP room, or whether you'll crane your neck in row B.

## What we know about the formats
| Format | What's public | What we assume (typical values) |
|---|---|---|
| IMAX | Digital/single-laser IMAX is 1.90:1. Only dual-projector GT Laser shows the full 1.43:1 frame, and only about a dozen rooms in North America have it. Steep stadium rake, seats close to the screen. | 18 m wide 1.90:1 screen, steep rake. A 1.43:1 GT room as a second preset. |
| UltraAVX | Cineplex's own premium large format. Wall-to-wall screen, "the biggest we could fit", reserved recliner/rocker seats, Dolby Atmos in newer rooms. Not certified by an outside body, so it varies by location. | 16.5 m wide scope (2.39:1) screen, wider row spacing. |
| Regular | Varies a lot by room. | Large house (13 m) and small house (9.5 m) presets. |
| VIP | 19+, licensed, smaller rooms (one Vancouver room seats 123, others 114), full recliners. Screens are smaller than UltraAVX; it's a comfort upgrade, not a picture upgrade. | 11 m scope screen, ~1.6 m row pitch, few rows. |

**No official Cineplex room dimensions are public.** Every preset in this repo is a typical value, labeled as such. The data format is open so real drawings can be dropped in.

## Viewing standards we score against
- **Horizontal viewing angle** (how much of your view the screen fills). THX: at least 36° from the back row, best seat around 40°. SMPTE EG-18: at least 30°. Immersive formats aim wider, so each format gets its own ideal angle.
- **Neck tilt.** A commonly cited SMPTE figure says discomfort starts when you look up more than 35° to the top of the screen. CEDIA's home figure is much stricter (15°). We start penalizing at 30°.
- **Off-axis.** Sitting far to the side skews the picture.
- **Head in front (C-value).** Auditorium designers measure how far your sightline to the bottom of the screen clears the eye of the person in front. About 60 mm is a minimum, 90 mm good, 120 mm excellent. This is the "will a head cover the subtitles" check.

Secondary sources disagree in places. The scoring weights are ours and documented in code, not an official standard.

## Prior art
- Seat-view photo sites (user-uploaded photos per seat). Great when they exist, empty for most rooms.
- No booking app we found renders the actual view from the chosen seat with the real screen format.

## Tech choice: least memory
- **No 3D engine.** A ~300-line renderer (camera, near-plane clipping, painter's sort, flat shading) draws a few thousand flat polygons to Canvas2D on web and SwiftUI `Canvas` on iOS. Zero dependencies, nothing to download, renders only when the camera moves.
- Same JSON room format and same math on both platforms.
- Easy for Cineplex to drop into their existing seat map: one JS file on web, four Swift files on iOS.

## Sources
- [CinemaView: UltraAVX vs VIP vs IMAX](https://cinemaview.in/en/blog/cineplex-ultraavx-vs-vip-vs-imax-canada)
- [Cineplex UltraAVX expansion press release (2012)](https://www.globenewswire.com/news-release/2012/01/26/1397597/0/en/Cineplex-to-Offer-UltraAVX-TM-in-12-Additional-Theatres-Across-Canada.html?print=1)
- [Cineplex UltraAVX page](https://www.cineplex.com/experiences/ultraavx)
- [Retail Insider: VIP at Brentwood](https://retail-insider.com/retail-insider/2021/07/adult-only-cineplex-vip-cinemas-opens-at-the-amazing-brentwood/)
- [Daily Hive: Marine Gateway VIP](https://dailyhive.com/vancouver/cineplex-marine-gateway-vancouver-theatres)
- [CinemaView: IMAX 1.43 vs 1.90](https://cinemaview.in/blog/understanding-imax-aspect-ratios)
- [SlashGear: IMAX with Laser vs regular IMAX](https://www.slashgear.com/2264102/imax-with-laser-vs-regular-differences/)
- [Screen size vs viewing distance: THX and SMPTE](https://hometheater.us.com/video/screen-size-viewing-distance/)
- [Acoustic Frontiers: viewing angles and sightlines](https://acousticfrontiers.com/blogs/articles/home-theater-viewing-angles-distances-and-sightlines)
- [Wikipedia: Optimum HDTV viewing distance](https://www.Wikipedia.org/wiki/Optimum_HDTV_viewing_distance)
