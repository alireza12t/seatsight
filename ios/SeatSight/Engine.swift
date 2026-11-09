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

    static let all: [Auditorium] = {
        struct File: Codable { let auditoriums: [Auditorium] }
        guard let url = Bundle.main.url(forResource: "auditoriums", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.auditoriums
    }()
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

    init(_ a: Auditorium) {
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
                seat.sold = Room.sold(a.id, index, score: seat.m.score)
                rows[r].seats[s] = seat
                index += 1
            }
        }
        self.rows = rows
        seats = rows.flatMap(\.seats)
        best = seats.max { $0.m.score < $1.m.score } ?? seats[0]
    }

    // Stable fake "sold" seats so the map looks real. Center seats sell first.
    static func sold(_ id: String, _ i: Int, score: Int) -> Bool {
        var h: UInt32 = 2166136261
        for c in (id + String(i)).unicodeScalars { h = (h ^ c.value) &* 16777619 }
        let rnd = Double(h % 1000) / 1000
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
    static func over(_ r: Room) -> Camera { look(V3(0, r.ceil - 0.6, r.back - 0.4), V3(0, r.bottom + r.H * 0.35, 0)) }
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
        func quad(_ p: [V3], _ col: V3, _ layer: Int, _ n: V3?, emit: Bool = false, seat: String? = nil) {
            out.append(Poly(p: p, col: col, layer: layer, n: n, emit: emit, seat: seat))
        }
        func box(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, _ z0: Double, _ z1: Double, _ col: V3, _ seat: String) {
            quad([V3(x0, y0, z0), V3(x1, y0, z0), V3(x1, y1, z0), V3(x0, y1, z0)], col, 9, V3(0, 0, -1), seat: seat)
            quad([V3(x1, y0, z1), V3(x0, y0, z1), V3(x0, y1, z1), V3(x1, y1, z1)], col, 9, V3(0, 0, 1), seat: seat)
            quad([V3(x0, y1, z0), V3(x1, y1, z0), V3(x1, y1, z1), V3(x0, y1, z1)], col, 9, V3(0, 1, 0), seat: seat)
            quad([V3(x0, y0, z1), V3(x0, y0, z0), V3(x0, y1, z0), V3(x0, y1, z1)], col, 9, V3(-1, 0, 0), seat: seat)
            quad([V3(x1, y0, z0), V3(x1, y0, z1), V3(x1, y1, z1), V3(x1, y1, z0)], col, 9, V3(1, 0, 0), seat: seat)
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
        let cy0 = r.bottom + (r.H - ch) / 2
        func P(_ u: Double, _ v: Double, _ l: Double) -> V3 { V3(-cw / 2 + u * cw, cy0 + v * ch, zS + l * 0.001) }
        let sky: [V3] = [V3(255, 196, 120), V3(247, 150, 110), V3(196, 98, 120), V3(110, 70, 130), V3(44, 44, 96)]
        for i in 0..<12 {
            let v0 = 0.25 + Double(i) * 0.0625, t = (Double(i) + 0.5) / 3, k = Int(t)
            quad([P(0, v0, 1), P(1, v0, 1), P(1, v0 + 0.0625, 1), P(0, v0 + 0.0625, 1)], sky[k] + (sky[k + 1] - sky[k]) * (t - Double(k)), 3, nil, emit: true)
        }
        quad([P(0, 0, 1), P(1, 0, 1), P(1, 0.25, 1), P(0, 0.25, 1)], V3(255, 214, 140), 3, nil, emit: true)
        let sun = (0..<24).map { k -> V3 in let t = Double(k) / 24 * 2 * .pi; return P(0.62 + 0.07 * cos(t) * (ch / cw), 0.38 + 0.07 * sin(t), 2) }
        quad(sun, V3(255, 236, 190), 4, nil, emit: true)
        func ridge(_ pts: [(Double, Double)], _ col: V3, _ l: Double) {
            quad([P(0, 0, l)] + pts.map { P($0.0, $0.1, l) } + [P(1, 0, l)], col, 4 + Int(l), nil, emit: true)
        }
        ridge([(0, 0.3), (0.12, 0.42), (0.22, 0.33), (0.35, 0.5), (0.5, 0.36), (0.66, 0.44), (0.8, 0.3), (0.9, 0.38), (1, 0.32)], V3(120, 70, 110), 1)
        ridge([(0, 0.18), (0.15, 0.26), (0.3, 0.16), (0.45, 0.24), (0.6, 0.12), (0.78, 0.22), (1, 0.14)], V3(40, 26, 52), 2)
        for (u0, u1, v) in [(0.25, 0.75, 0.085), (0.32, 0.68, 0.04)] {
            quad([P(u0, v, 5), P(u1, v, 5), P(u1, v + 0.028, 5), P(u0, v + 0.028, 5)], V3(250, 250, 250), 7, nil, emit: true)
        }
        // seats and people
        let seatC = hex(a.seatColor ?? "#35416b"), recl = a.seatWidth >= 0.8
        let person = V3(52, 48, 56)
        for s in r.seats {
            let w = a.seatWidth * 0.44, fl = s.floor, z = s.z
            box(s.x - w, s.x + w, fl + 0.28, fl + 0.48, z - (recl ? 0.45 : 0.32), z + 0.12, seatC, s.id)
            box(s.x - w, s.x + w, fl + 0.28, fl + (recl ? 1.08 : 0.98), z + 0.12, z + 0.24, seatC, s.id)
            if crowd && s.sold && s.id != selfID {
                out.append(Poly(p: [], col: person, layer: 9, seat: s.id, center: V3(s.x, s.eye + 0.04, z), radius: 0.11))
                quad([V3(s.x - 0.22, s.eye - 0.38, z + 0.02), V3(s.x + 0.22, s.eye - 0.38, z + 0.02), V3(s.x + 0.2, s.eye - 0.12, z + 0.02), V3(s.x - 0.2, s.eye - 0.12, z + 0.02)], person, 9, nil, seat: s.id)
            }
        }
        return out
    }

    // MARK: Render

    private static let light: V3 = { let v = V3(0.25, 0.6, -0.75); return v / (v * v).sum().squareRoot() }()

    static func render(_ g: inout GraphicsContext, size: CGSize, polys: [Poly], cam: Camera, highlight: String? = nil, hide: String? = nil) {
        let w = size.width, h = size.height
        let cy = cos(cam.yaw), sy = sin(cam.yaw), cp = cos(cam.pitch), sp = sin(cam.pitch)
        let fw = V3(sy * cp, sp, -cy * cp), rt = V3(cy, 0, sy)
        let up = V3(rt.y * fw.z - rt.z * fw.y, rt.z * fw.x - rt.x * fw.z, rt.x * fw.y - rt.y * fw.x)
        let f = min(w / 2 / tan(.pi / 4), h / 2 / tan(37 * .pi / 180)) * cam.zoom
        let pos = cam.pos
        func toCam(_ v: V3) -> V3 { let d = v - pos; return V3((d * rt).sum(), (d * up).sum(), (d * fw).sum()) }
        func proj(_ q: V3) -> CGPoint { CGPoint(x: w / 2 + f * q.x / q.z, y: h / 2 - f * q.y / q.z) }

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
            if let s = p.seat, s == highlight, p.center == nil { col = V3(255, 196, 60) }
            var k = 1.0
            if !p.emit {
                let lit = p.n.map { max(0, ($0 * light).sum()) } ?? 0.5
                k = (0.45 + 0.75 * lit) / (1 + it.d * 0.03)
            }
            let c = col * k / 255
            g.fill(it.path, with: .color(Color(red: min(1, c.x), green: min(1, c.y), blue: min(1, c.z))))
        }
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
