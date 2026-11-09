// SeatSight engine: room geometry, seat scoring and a tiny 3D renderer for SwiftUI Canvas.
// Mirrors docs/engine.js. Units are meters. x = right, y = up, z = distance from the screen.
import SwiftUI

typealias V3 = SIMD3<Double>

struct Auditorium: Codable, Identifiable, Hashable, Sendable {
    struct Screen: Codable, Hashable, Sendable { var width, aspect, bottom: Double }
    let id, name, variant, format: String
    var screen: Screen
    var firstRow, rowPitch, riser: Double
    var flatRows: Int
    var seatWidth, aisle: Double
    var eyeHeight: Double?
    var idealAngle: Double
    var seatColor: String?
    var rows: [String]
    var rowLabels: String?

    static var all: [Auditorium] { Catalog.shared.auditoriums }
    static func find(_ id: String) -> Auditorium { all.first { $0.id == id } ?? all[0] }
}

struct Theatre: Codable, Identifiable, Hashable, Sendable {
    let id, name: String
    let rooms: [String: String]   // format -> auditorium id
}

struct Movie: Codable, Identifiable, Hashable, Sendable {
    let id, title, genre, rating, film: String
    let runtime: Int
    let colors: [String]
    let formats: [String]
    func film(for format: String) -> Double { film == "imax" ? (format == "IMAX" ? 0 : 2.39) : Double(film) ?? 0 }
    var filmName: String { film == "imax" ? "Filmed for IMAX" : film == "2.39" ? "Scope 2.39:1" : "Flat 1.85:1" }
    var meta: String { "\(genre) · \(runtime / 60)h \(runtime % 60)m · \(rating)" }
}

struct Catalog: Codable, Sendable {
    let auditoriums: [Auditorium]
    let theatres: [Theatre]
    let movies: [Movie]
    static let shared: Catalog = {
        guard let url = Bundle.main.url(forResource: "auditoriums", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let c = try? JSONDecoder().decode(Catalog.self, from: data) else { return Catalog(auditoriums: [], theatres: [], movies: []) }
        return c
    }()
}

func fnv(_ s: String) -> UInt32 {
    var h: UInt32 = 2166136261
    for c in s.unicodeScalars { h = (h ^ c.value) &* 16777619 }
    return h
}

struct Metrics: Hashable, Sendable {
    var h = 0.0, neck = 0.0, off = 0.0
    var c: Double?
    var score = 0, tv = 0
    var notes: [String] = []
}

struct Seat: Identifiable, Hashable, Sendable {
    let id: String
    let row, num, section: Int
    let x, z, floor, eye: Double
    var m = Metrics()
    var sold = false
}

struct Row: Sendable {
    let label: String
    let z, floor, width: Double
    let parts: [Int]
    var seats: [Seat]
}

struct Room: Sendable {
    let a: Auditorium
    let rows: [Row]
    let seats: [Seat]
    let W, H, bottom, top, eyeH, roomW, back, ceil: Double
    let best: Seat

    init(_ a: Auditorium, seed: String = "") {
        self.a = a
        let eyeH = a.eyeHeight ?? 1.15
        let labels = Array(a.rowLabels ?? "ABCDEFGHJKLMNOPQRSTUVWXYZ")
        var rows: [Row] = a.rows.enumerated().map { i, spec in
            let parts = spec.split(separator: "-").compactMap { Int($0) }
            let width = Double(parts.reduce(0, +)) * a.seatWidth + Double(parts.count - 1) * a.aisle
            let z = a.firstRow + Double(i) * a.rowPitch
            let floor = i < a.flatRows ? 0 : Double(i - a.flatRows + 1) * a.riser
            let label = i < labels.count ? String(labels[i]) : String(i + 1)
            var seats: [Seat] = []
            var x = -width / 2, n = 1
            for (p, count) in parts.enumerated() {
                for _ in 0..<count {
                    seats.append(Seat(id: label + String(n), row: i, num: n, section: p, x: x + a.seatWidth / 2, z: z, floor: floor, eye: floor + eyeH))
                    x += a.seatWidth; n += 1
                }
                x += a.aisle
            }
            return Row(label: label, z: z, floor: floor, width: width, parts: parts, seats: seats)
        }
        let W = a.screen.width, H = W / a.screen.aspect, bottom = a.screen.bottom
        let last = rows[rows.count - 1]
        self.W = W; self.H = H; self.bottom = bottom; top = bottom + H; self.eyeH = eyeH
        roomW = max(W + 2, rows.map { $0.width + 2 * a.aisle }.max() ?? 0)
        back = last.z + a.rowPitch * 0.6
        ceil = max(bottom + H + 1.2, last.floor + 3.2)
        var index = 0
        for r in rows.indices {
            for s in rows[r].seats.indices {
                var seat = rows[r].seats[s]
                seat.m = Room.metrics(a: a, rows: rows, W: W, bottom: bottom, top: bottom + H, eyeH: eyeH, s: seat)
                seat.sold = Room.sold(a.id + seed, index, score: seat.m.score)
                rows[r].seats[s] = seat
                index += 1
            }
        }
        self.rows = rows
        seats = rows.flatMap(\.seats)
        let open = seats.filter { !$0.sold }
        best = (open.isEmpty ? seats : open).max { $0.m.score < $1.m.score } ?? seats[0]
    }

    // Stable fake "sold" seats so the map looks real. Center seats sell first.
    static func sold(_ id: String, _ i: Int, score: Int) -> Bool {
        let rnd = Double(fnv(id + String(i)) % 1000) / 1000
        return rnd < 0.15 + 0.4 * pow(Double(score) / 100, 2)
    }

    static func metrics(a: Auditorium, rows: [Row], W: Double, bottom: Double, top: Double, eyeH: Double, s: Seat) -> Metrics {
        let d = s.z
        let h = deg(atan2(W / 2 - s.x, d) - atan2(-W / 2 - s.x, d))
        let neck = deg(atan2(top - s.eye, d))
        let off = deg(atan2(abs(s.x), d))
        var c: Double?
        if s.row > 0 { // C-value: sightline clearance over the eye of the person in front
            let f = rows[s.row - 1]
            let ys = s.eye + (bottom - s.eye) * ((s.z - f.z) / s.z)
            c = ys - (f.floor + eyeH)
        }
        let ideal = a.idealAngle
        let aS = 0.25 + 0.75 * exp(-pow((h - ideal) / (ideal * 0.6), 2))
        let nS = neck > 30 ? max(0.4, 1 - (neck - 30) / 30) : 1
        let oS = max(0.35, 1 - off * 0.004 - max(0, off - 15) / 45)
        let cS: Double = { guard let c else { return 1 }; return c >= 0.09 ? 1 : c >= 0.06 ? 0.94 : c >= 0 ? 0.82 : 0.68 }()
        var m = Metrics(h: h, neck: neck, off: off, c: c)
        m.score = Int((100 * aS * nS * oS * cS).rounded())
        m.tv = Int((2 * 2.5 * tan(h / 2 * .pi / 180) * 1.147 / 0.0254).rounded())
        if h > ideal * 1.25 { m.notes.append("Very close. The screen spills past your view, you will move your head to follow action.") }
        else if h < ideal * 0.7 { m.notes.append("Far back. Feels more like a big TV than a wall of picture.") }
        else { m.notes.append("The screen fills your view about right for this format.") }
        if neck > 30 { m.notes.append("You look up \(Int(neck.rounded()))° to the top edge. Neck strain is likely in a long movie.") }
        if off > 20 { m.notes.append("Well off to the side. The picture looks skewed.") }
        if let c, c < 0.06 { m.notes.append("The head in front may cover the bottom of the screen (subtitles).") }
        return m
    }

    // Same relative spot in another room, for the compare view.
    func similar(to seat: Seat, from: Room) -> Seat {
        let fr = Double(seat.row) / Double(max(1, from.rows.count - 1))
        let fx = seat.x / (from.rows[seat.row].width / 2)
        let row = rows[Int((fr * Double(rows.count - 1)).rounded())]
        let tx = fx * row.width / 2
        return row.seats.min { abs($0.x - tx) < abs($1.x - tx) }!
    }
}

private func deg(_ r: Double) -> Double { r * 180 / .pi }

// MARK: - Scene

struct Poly: Sendable {
    var p: [V3]
    var col: V3
    var layer: Int
    var n: V3?
    var emit = false
    var seat: String?
    var sold: Bool?
    var center: V3?   // set for circles (heads)
    var radius = 0.0
}

struct Camera: Sendable {
    var pos: V3, yaw: Double, pitch: Double, zoom = 1.0

    static func look(_ pos: V3, _ t: V3) -> Camera {
        let d = t - pos
        return Camera(pos: pos, yaw: atan2(d.x, -d.z), pitch: atan2(d.y, (d.x * d.x + d.z * d.z).squareRoot()))
    }
    static func eye(_ r: Room, _ s: Seat) -> Camera { look(V3(s.x, s.eye, s.z), V3(0, r.bottom + r.H / 2, 0)) }
    // Dollhouse view from behind and above; the back wall and ceiling are culled so you see every seat.
    static func over(_ r: Room) -> Camera { look(V3(0, r.ceil + 3, r.back + 2.5), V3(0, r.rows[0].floor, r.back * 0.45)) }
    func lerp(_ b: Camera, _ t: Double) -> Camera {
        Camera(pos: pos + (b.pos - pos) * t, yaw: yaw + (b.yaw - yaw) * t, pitch: pitch + (b.pitch - pitch) * t, zoom: zoom + (b.zoom - zoom) * t)
    }
}

enum Engine {
    static let near = 0.05

    static func scene(_ r: Room, film: Double = 0, crowd: Bool = false, selfID: String? = nil) -> [Poly] {
        var out: [Poly] = []
        out.reserveCapacity(r.seats.count * 11 + 80)
        let a = r.a, hw = r.roomW / 2
        func quad(_ p: [V3], _ col: V3, _ layer: Int, _ n: V3?, emit: Bool = false, seat: String? = nil, sold: Bool? = nil) {
            out.append(Poly(p: p, col: col, layer: layer, n: n, emit: emit, seat: seat, sold: sold))
        }
        func box(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, _ z0: Double, _ z1: Double, _ col: V3, _ seat: String, _ sold: Bool) {
            quad([V3(x0, y0, z0), V3(x1, y0, z0), V3(x1, y1, z0), V3(x0, y1, z0)], col, 20, V3(0, 0, -1), seat: seat, sold: sold)
            quad([V3(x1, y0, z1), V3(x0, y0, z1), V3(x0, y1, z1), V3(x1, y1, z1)], col, 20, V3(0, 0, 1), seat: seat, sold: sold)
            quad([V3(x0, y1, z0), V3(x1, y1, z0), V3(x1, y1, z1), V3(x0, y1, z1)], col, 20, V3(0, 1, 0), seat: seat, sold: sold)
            quad([V3(x0, y0, z1), V3(x0, y0, z0), V3(x0, y1, z0), V3(x0, y1, z1)], col, 20, V3(-1, 0, 0), seat: seat, sold: sold)
            quad([V3(x1, y0, z0), V3(x1, y0, z1), V3(x1, y1, z1), V3(x1, y1, z0)], col, 20, V3(1, 0, 0), seat: seat, sold: sold)
        }
        let wall = V3(22, 24, 34), floorC = V3(30, 28, 34), stepC = V3(44, 40, 48)
        quad([V3(-hw, 0, 0), V3(hw, 0, 0), V3(hw, r.ceil, 0), V3(-hw, r.ceil, 0)], V3(14, 15, 20), 0, V3(0, 0, 1))
        quad([V3(-hw, 0, r.back), V3(-hw, 0, 0), V3(-hw, r.ceil, 0), V3(-hw, r.ceil, r.back)], wall, 0, V3(1, 0, 0))
        quad([V3(hw, 0, 0), V3(hw, 0, r.back), V3(hw, r.ceil, r.back), V3(hw, r.ceil, 0)], wall, 0, V3(-1, 0, 0))
        quad([V3(hw, 0, r.back), V3(-hw, 0, r.back), V3(-hw, r.ceil, r.back), V3(hw, r.ceil, r.back)], wall, 0, V3(0, 0, -1))
        quad([V3(-hw, r.ceil, 0), V3(hw, r.ceil, 0), V3(hw, r.ceil, r.back), V3(-hw, r.ceil, r.back)], V3(12, 12, 16), 0, V3(0, -1, 0))
        var prevFloor = 0.0, prevZ = 0.0
        for row in r.rows {
            let z0 = row.z - a.rowPitch * 0.55
            quad([V3(-hw, prevFloor, prevZ), V3(hw, prevFloor, prevZ), V3(hw, prevFloor, z0), V3(-hw, prevFloor, z0)], floorC, 1, V3(0, 1, 0))
            if row.floor > prevFloor {
                quad([V3(-hw, prevFloor, z0), V3(hw, prevFloor, z0), V3(hw, row.floor, z0), V3(-hw, row.floor, z0)], stepC, 1, V3(0, 0, -1))
                for x in [-hw + 0.3, hw - 0.5] {
                    quad([V3(x, row.floor - 0.06, z0 - 0.01), V3(x + 0.2, row.floor - 0.06, z0 - 0.01), V3(x + 0.2, row.floor - 0.02, z0 - 0.01), V3(x, row.floor - 0.02, z0 - 0.01)], V3(255, 190, 90), 1, V3(0, 0, -1), emit: true)
                }
            }
            prevFloor = row.floor; prevZ = z0
        }
        quad([V3(-hw, prevFloor, prevZ), V3(hw, prevFloor, prevZ), V3(hw, prevFloor, r.back), V3(-hw, prevFloor, r.back)], floorC, 1, V3(0, 1, 0))
        // screen: masking, then the movie fitted to the film's aspect ratio
        let zS = 0.02, sx = r.W / 2
        quad([V3(-sx - 0.3, r.bottom - 0.3, zS), V3(sx + 0.3, r.bottom - 0.3, zS), V3(sx + 0.3, r.top + 0.3, zS), V3(-sx - 0.3, r.top + 0.3, zS)], V3(4, 4, 6), 2, nil, emit: true)
        let f = film > 0 ? film : a.screen.aspect
        var cw = r.W, ch = r.W / f
        if ch > r.H { ch = r.H; cw = r.H * f }
        let mid = r.bottom + r.H / 2, hh = ch / cw / 2
        // the bare screen: any part the movie doesn't cover shows as grey bars
        quad([V3(-sx, r.bottom, zS + 0.0005), V3(sx, r.bottom, zS + 0.0005), V3(sx, r.top, zS + 0.0005), V3(-sx, r.top, zS + 0.0005)], V3(24, 24, 30), 3, nil, emit: true)
        // One fixed picture cropped by the frame: a taller frame (IMAX) shows more sky and foreground.
        func pic(_ pts: [(Double, Double)], _ col: V3, _ l: Int) {
            let c = clipY(pts, -hh, hh)
            if c.count > 2 { quad(c.map { V3(-cw / 2 + $0.0 * cw, mid + $0.1 * cw, zS + Double(l) * 0.001) }, col, 3 + l, nil, emit: true) }
        }
        func ring(_ u: Double, _ y: Double, _ rr: Double, _ n: Int = 20) -> [(Double, Double)] {
            (0..<n).map { k in let t = Double(k) / Double(n) * 6.283; return (u + rr * cos(t), y + rr * sin(t)) }
        }
        let sky: [V3] = [V3(255, 196, 120), V3(247, 150, 110), V3(196, 98, 120), V3(110, 70, 130), V3(44, 44, 96), V3(12, 14, 40)]
        for i in 0..<16 {
            let y0 = -0.06 + Double(i) * 0.026, t = Double(i) / 15 * 5, k = min(4, Int(t))
            pic([(0, y0), (1, y0), (1, y0 + 0.027), (0, y0 + 0.027)], sky[k] + (sky[k + 1] - sky[k]) * (t - Double(k)), 1)
        }
        for k in 0..<24 {
            let u = (Double(k) * 0.137 + 0.03).truncatingRemainder(dividingBy: 1), y = 0.215 + (Double(k) * 0.071).truncatingRemainder(dividingBy: 0.13)
            pic([(u, y), (u + 0.003, y), (u + 0.003, y + 0.003), (u, y + 0.003)], V3(230, 230, 255), 2)
        }
        pic(ring(0.18, 0.245, 0.02), V3(236, 232, 214), 2)
        pic(ring(0.62, 0, 0.045, 24), V3(255, 236, 190), 2)
        pic([(0, -0.35), (0, -0.02), (0.12, 0.05), (0.22, 0), (0.35, 0.08), (0.5, 0.01), (0.66, 0.05), (0.8, -0.02), (0.9, 0.03), (1, -0.01), (1, -0.35)], V3(120, 70, 110), 3)
        pic([(0, -0.16), (0, -0.08), (0.15, -0.05), (0.3, -0.1), (0.45, -0.06), (0.6, -0.12), (0.78, -0.07), (1, -0.11), (1, -0.16)], V3(40, 26, 52), 4)
        pic([(0, -0.35), (1, -0.35), (1, -0.15), (0, -0.15)], V3(26, 40, 62), 5)
        for (y, wd) in [(-0.17, 0.05), (-0.2, 0.035), (-0.24, 0.025), (-0.29, 0.015)] {
            pic([(0.62 - wd / 2, y), (0.62 + wd / 2, y), (0.62 + wd / 2, y + 0.008), (0.62 - wd / 2, y + 0.008)], V3(255, 200, 140), 6)
        }
        // subtitles at the bottom of the frame, to check what the head in front covers
        for (u0, u1, v) in [(0.25, 0.75, 0.05), (0.32, 0.68, 0.025)] {
            let y = mid - ch / 2 + v * ch
            quad([V3(-cw / 2 + u0 * cw, y, zS + 0.008), V3(-cw / 2 + u1 * cw, y, zS + 0.008), V3(-cw / 2 + u1 * cw, y + ch * 0.028, zS + 0.008), V3(-cw / 2 + u0 * cw, y + ch * 0.028, zS + 0.008)], V3(250, 250, 250), 10, nil, emit: true)
        }
        // seats and people
        let seatC = hex(a.seatColor ?? "#35416b"), soldC = V3(46, 46, 52), recl = a.seatWidth >= 0.8
        let person = V3(52, 48, 56)
        for s in r.seats {
            let w = a.seatWidth * 0.44, fl = s.floor, z = s.z
            box(s.x - w, s.x + w, fl + 0.28, fl + 0.48, z - (recl ? 0.45 : 0.32), z + 0.12, s.sold ? soldC : seatC, s.id, s.sold)
            box(s.x - w, s.x + w, fl + 0.28, fl + (recl ? 1.08 : 0.98), z + 0.12, z + 0.24, s.sold ? soldC : seatC, s.id, s.sold)
            if crowd && s.sold && s.id != selfID {
                out.append(Poly(p: [], col: person, layer: 20, seat: s.id, center: V3(s.x, s.eye + 0.04, z), radius: 0.11))
                quad([V3(s.x - 0.22, s.eye - 0.38, z + 0.02), V3(s.x + 0.22, s.eye - 0.38, z + 0.02), V3(s.x + 0.2, s.eye - 0.12, z + 0.02), V3(s.x - 0.2, s.eye - 0.12, z + 0.02)], person, 20, nil, seat: s.id)
            }
        }
        return out
    }

    // MARK: Render

    private static let light: V3 = { let v = V3(0.25, 0.6, -0.75); return v / (v * v).sum().squareRoot() }()

    struct View {
        let f: Double, pos: V3, rt: V3, up: V3, fw: V3, w: Double, h: Double
        init(_ cam: Camera, _ size: CGSize) {
            w = size.width; h = size.height; pos = cam.pos
            let cy = cos(cam.yaw), sy = sin(cam.yaw), cp = cos(cam.pitch), sp = sin(cam.pitch)
            fw = V3(sy * cp, sp, -cy * cp); rt = V3(cy, 0, sy)
            up = V3(rt.y * fw.z - rt.z * fw.y, rt.z * fw.x - rt.x * fw.z, rt.x * fw.y - rt.y * fw.x)
            f = min(w / 2 / tan(.pi / 4), h / 2 / tan(37 * .pi / 180)) * cam.zoom
        }
        func toCam(_ v: V3) -> V3 { let d = v - pos; return V3((d * rt).sum(), (d * up).sum(), (d * fw).sum()) }
        func proj(_ q: V3) -> CGPoint { CGPoint(x: w / 2 + f * q.x / q.z, y: h / 2 - f * q.y / q.z) }
    }

    /// Which seat is under a tap? Forgiving: falls back to the nearest seat face within 24 pt.
    static func pick(_ point: CGPoint, size: CGSize, polys: [Poly], cam: Camera) -> String? {
        let v = View(cam, size)
        var hit: String?, best = Double.infinity, near: String?, nearD = 24.0
        for poly in polys {
            guard let seat = poly.seat, poly.center == nil, poly.sold != nil else { continue }
            if let n = poly.n, ((v.pos - poly.p[0]) * n).sum() <= 0 { continue }
            let cs = poly.p.map(v.toCam)
            if cs.contains(where: { $0.z < near0 }) { continue }
            let pts = cs.map(v.proj)
            var inside = false, j = pts.count - 1
            for i in pts.indices {
                if (pts[i].y > point.y) != (pts[j].y > point.y),
                   point.x < (pts[j].x - pts[i].x) * (point.y - pts[i].y) / (pts[j].y - pts[i].y) + pts[i].x { inside.toggle() }
                j = i
            }
            let d = cs.reduce(0) { $0 + $1.z } / Double(cs.count)
            if inside && d < best { best = d; hit = seat }
            let cx = pts.reduce(0) { $0 + $1.x } / Double(pts.count), cy = pts.reduce(0) { $0 + $1.y } / Double(pts.count)
            let dist = hypot(cx - point.x, cy - point.y)
            if dist < nearD { nearD = dist; near = seat }
        }
        return hit ?? near
    }
    private static let near0 = near

    static func render(_ g: inout GraphicsContext, size: CGSize, polys: [Poly], cam: Camera, highlight: String? = nil, hide: String? = nil, map: Bool = false) {
        let v = View(cam, size), f = v.f, pos = cam.pos
        func toCam(_ p: V3) -> V3 { v.toCam(p) }
        func proj(_ q: V3) -> CGPoint { v.proj(q) }

        struct Item { let i: Int; let d: Double; let path: Path }
        var items: [Item] = []
        items.reserveCapacity(polys.count / 2)
        for (i, poly) in polys.enumerated() {
            if let hide, poly.seat == hide { continue }
            if let c = poly.center {
                let q = toCam(c)
                guard q.z > near else { continue }
                let p = proj(q), rr = max(0.5, f * poly.radius / q.z)
                items.append(Item(i: i, d: q.z, path: Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2))))
                continue
            }
            if let n = poly.n, ((pos - poly.p[0]) * n).sum() <= 0 { continue }
            var cs = poly.p.map(toCam)
            let behind = cs.reduce(0) { $0 + ($1.z < near ? 1 : 0) }
            if behind == cs.count { continue }
            if behind > 0 { cs = clipNear(cs) }
            var path = Path(), d = 0.0
            for (k, q) in cs.enumerated() {
                d += q.z
                if k == 0 { path.move(to: proj(q)) } else { path.addLine(to: proj(q)) }
            }
            path.closeSubpath()
            items.append(Item(i: i, d: d / Double(cs.count), path: path))
        }
        items.sort { let a = polys[$0.i].layer, b = polys[$1.i].layer; return a != b ? a < b : $0.d > $1.d }
        g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 7 / 255, green: 8 / 255, blue: 12 / 255)))
        for it in items {
            let p = polys[it.i]
            var col = p.col
            if map, let sold = p.sold { col = sold ? V3(58, 58, 66) : V3(70, 120, 205) } // room view: map colors
            if let s = p.seat, s == highlight, p.center == nil { col = V3(255, 196, 60) }
            var k = 1.0
            if !p.emit {
                let lit = p.n.map { max(0, ($0 * light).sum()) } ?? 0.5
                k = (0.45 + 0.75 * lit) / (map ? 1 : 1 + it.d * 0.03)
            }
            let c = col * k / 255
            g.fill(it.path, with: .color(Color(red: min(1, c.x), green: min(1, c.y), blue: min(1, c.z))))
        }
    }

    private static func clipY(_ pts: [(Double, Double)], _ lo: Double, _ hi: Double) -> [(Double, Double)] {
        func cut(_ P: [(Double, Double)], _ keep: (Double) -> Bool, _ yv: Double) -> [(Double, Double)] {
            var o: [(Double, Double)] = []
            for i in P.indices {
                let A = P[i], B = P[(i + 1) % P.count], a = keep(A.1), b = keep(B.1)
                if a { o.append(A) }
                if a != b { let t = (yv - A.1) / (B.1 - A.1); o.append((A.0 + (B.0 - A.0) * t, yv)) }
            }
            return o
        }
        return cut(cut(pts, { $0 >= lo }, lo), { $0 <= hi }, hi)
    }

    private static func clipNear(_ cs: [V3]) -> [V3] {
        var out: [V3] = []
        for i in cs.indices {
            let A = cs[i], B = cs[(i + 1) % cs.count], ai = A.z >= near, bi = B.z >= near
            if ai { out.append(A) }
            if ai != bi { let t = (near - A.z) / (B.z - A.z); out.append(V3(A.x + (B.x - A.x) * t, A.y + (B.y - A.y) * t, near)) }
        }
        return out
    }

    static func hex(_ s: String) -> V3 {
        let n = Int(s.dropFirst(), radix: 16) ?? 0x35416b
        return V3(Double(n >> 16), Double((n >> 8) & 255), Double(n & 255))
    }
}
