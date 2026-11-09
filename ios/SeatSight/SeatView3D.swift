import SwiftUI
import simd

struct SeatView3D: View {
    let room: Room
    @State var seat: Seat
    let show: Show
    let crowd: Bool
    var onSelect: (Seat) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var polys: [Poly] = []
    @State private var cam = Camera(pos: .zero, yaw: 0, pitch: 0)
    @State private var flight: (from: Camera, to: Camera, start: Date, duration: Double)?
    @State private var lastDrag: CGSize = .zero
    @State private var baseZoom = 1.0
    @State private var overview = false
    @State private var comparing = false
    @State private var toast: String?

    private static let compareIDs = ["imax-190", "ultraavx", "regular-large", "vip"]

    var body: some View {
        ZStack {
            Color(red: 7 / 255, green: 8 / 255, blue: 12 / 255).ignoresSafeArea()
            if comparing { compareGrid } else { scene3D; hud }
            if let toast {
                Text(toast).padding(10).background(.black.opacity(0.75), in: .rect(cornerRadius: 10)).transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) { tools }
        .onChange(of: seat.id, initial: true) { old, _ in
            let first = old == seat.id
            polys = Engine.scene(room, film: show.film, crowd: crowd, selfID: seat.id)
            overview = false
            onSelect(seat)
            fly(from: first ? Camera.over(room) : current(Date()), to: Camera.eye(room, seat), duration: first ? 1.3 : 0.7)
        }
    }

    // MARK: 3D

    private var scene3D: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: flight == nil)) { tl in
                Canvas { g, size in
                    let c = current(tl.date)
                    let near = simd_distance(c.pos, V3(seat.x, seat.eye, seat.z)) < 1
                    Engine.render(&g, size: size, polys: polys, cam: c, highlight: seat.id, hide: near ? seat.id : nil, map: overview)
                }
            }
            .contentShape(.rect)
            .onTapGesture(coordinateSpace: .local) { pt in tap(pt, size: geo.size) }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        if flight != nil { cam = current(Date()); flight = nil }
                        let d = CGSize(width: v.translation.width - lastDrag.width, height: v.translation.height - lastDrag.height)
                        lastDrag = v.translation
                        let k = 0.004 / cam.zoom
                        cam.yaw -= d.width * k
                        cam.pitch = min(1.3, max(-1.4, cam.pitch + d.height * k))
                    }
                    .onEnded { _ in lastDrag = .zero }
                    .simultaneously(with: MagnifyGesture()
                        .onChanged { v in
                            let z = baseZoom * v.magnification
                            if !overview && z < 0.7 { setOverview(true) } else if flight == nil { cam.zoom = min(4, max(0.6, z)) }
                        }
                        .onEnded { _ in baseZoom = cam.zoom })
            )
        }
        .ignoresSafeArea()
        .task(id: flight?.start) {
            guard let f = flight else { return }
            try? await Task.sleep(for: .seconds(f.duration))
            if flight?.start == f.start { cam = f.to; flight = nil; baseZoom = cam.zoom }
        }
    }

    private func tap(_ pt: CGPoint, size: CGSize) {
        guard let id = Engine.pick(pt, size: size, polys: polys, cam: current(Date())),
              let s = room.seats.first(where: { $0.id == id }), s.id != seat.id else { return }
        if s.sold { flash("Seat \(s.id) is taken") } else { seat = s }
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task { try? await Task.sleep(for: .seconds(1.4)); withAnimation { toast = nil } }
    }

    private func setOverview(_ on: Bool) {
        overview = on
        fly(from: current(Date()), to: on ? Camera.over(room) : Camera.eye(room, seat), duration: 0.9)
    }

    private func fly(from: Camera, to: Camera, duration: Double) {
        cam = from
        flight = (from, to, Date(), duration)
    }

    private func current(_ date: Date) -> Camera {
        guard let f = flight else { return cam }
        let t = min(1, date.timeIntervalSince(f.start) / f.duration)
        let e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        return f.from.lerp(f.to, e)
    }

    // MARK: HUD

    private var pictureNote: String {
        let aspect = room.a.screen.aspect, film = show.film
        if film == 0 { return "Filmed for IMAX, fills this \(aspect.formatted()):1 screen. \(Int(((2.39 / aspect - 1) * 100).rounded()))% more picture than a 2.39 room" }
        if abs(film - aspect) < 0.06 { return "\(film.formatted()):1 movie fills the screen" }
        return film > aspect ? "\(film.formatted()):1 movie, bars above and below" : "\(film.formatted()):1 movie, bars on the sides"
    }

    private var hud: some View {
        VStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Seat \(seat.id)").font(.headline)
                    Spacer()
                    Text("\(seat.m.score)").font(.title2.bold()).foregroundStyle(Color(hue: Double(seat.m.score) / 300, saturation: 0.7, brightness: 0.85))
                }
                Text("\(show.movie.title) · \(room.a.name) \(room.a.variant) · row \(seat.row + 1) of \(room.rows.count)").font(.caption).foregroundStyle(.secondary)
                if overview {
                    Text("Yellow is your seat, dark seats are taken. Tap an open seat to switch.").font(.caption)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
                        line("Screen fills", "\(Int(seat.m.h.rounded()))° of your view (ideal \(Int(room.a.idealAngle))°)")
                        line("Feels like", "a \(seat.m.tv)\" TV from your couch")
                        line("Picture", pictureNote)
                        line("Look up", "\(Int(seat.m.neck.rounded()))° to the top edge")
                        line("Distance", String(format: "%.1f m from the screen", seat.z))
                        line("Head in front", headText)
                    }
                    .font(.caption)
                    ForEach(seat.m.notes, id: \.self) { Text("• " + $0).font(.caption) }
                }
            }
            .padding(12)
            .frame(maxWidth: 380, alignment: .leading)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 56)
            Spacer()
            HStack(alignment: .bottom) {
                Text(overview ? "Tap a seat to switch" : "Drag to look · pinch out for the room view · tap a seat to switch")
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
                Spacer()
                nav
            }
            .padding(12)
        }
    }

    private var headText: String {
        guard let c = seat.m.c else { return "Front row, nobody ahead" }
        return c >= 0.09 ? "Clear view over heads" : c >= 0.06 ? "Just clears heads" : "May block the bottom"
    }

    private func line(_ k: String, _ v: String) -> some View {
        GridRow { Text(k).foregroundStyle(.secondary); Text(v) }
    }

    private var nav: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow { Color.clear.frame(width: 1, height: 1); arrow("chevron.up", "Row forward", 0, -1); Color.clear.frame(width: 1, height: 1) }
            GridRow { arrow("chevron.left", "Seat left", -1, 0); arrow("chevron.down", "Row back", 0, 1); arrow("chevron.right", "Seat right", 1, 0) }
        }
    }

    private func arrow(_ icon: String, _ label: String, _ dx: Int, _ dr: Int) -> some View {
        Button { move(dx, dr) } label: { Image(systemName: icon).frame(width: 40, height: 36) }
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
            .accessibilityLabel(label)
    }

    /// Next open seat in that direction, skipping taken ones.
    private func move(_ dx: Int, _ dr: Int) {
        if dr != 0 {
            var r = seat.row + dr
            while r >= 0 && r < room.rows.count {
                if let s = room.rows[r].seats.filter({ !$0.sold }).min(by: { abs($0.x - seat.x) < abs($1.x - seat.x) }) { seat = s; return }
                r += dr
            }
            return
        }
        let row = room.rows[seat.row].seats
        guard var i = row.firstIndex(where: { $0.id == seat.id }) else { return }
        i += dx
        while i >= 0 && i < row.count {
            if !row[i].sold { seat = row[i]; return }
            i += dx
        }
    }

    // MARK: Tools + compare

    private var shareURL: URL {
        var c = URLComponents(string: "https://alireza12t.github.io/seatsight/")!
        c.fragment = "t=\(show.theatre.id)&d=\(show.day)&m=\(show.movie.id)&fmt=\(show.format)&at=\(show.time)&seat=\(seat.id)"
        return c.url!
    }

    private var tools: some View {
        HStack(spacing: 8) {
            if !comparing {
                Button(overview ? "My seat" : "Room view") { setOverview(!overview) }
            }
            Button(comparing ? "Back" : "Compare") { comparing.toggle() }
            ShareLink(item: shareURL, message: Text("Seat \(seat.id) for \(show.movie.title) in \(room.a.name): the screen fills \(Int(seat.m.h.rounded()))° of my view, like a \(seat.m.tv)\" TV. Score \(seat.m.score)/100.")) {
                Image(systemName: "square.and.arrow.up")
            }
            Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Back to seat map")
        }
        .buttonStyle(.bordered)
        .padding(12)
    }

    private var compareGrid: some View {
        let rooms = Self.compareIDs.map { Room(.find($0), seed: show.seed) }
        return GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: wide ? 2 : 1)
            let h = (geo.size.height - 6) / (wide ? 2 : 4)
            LazyVGrid(columns: cols, spacing: 2) {
                ForEach(rooms, id: \.a.id) { r in
                    let s = r.similar(to: seat, from: room)
                    let p = Engine.scene(r, film: show.movie.film(for: r.a.format), crowd: crowd, selfID: s.id)
                    Canvas { g, size in Engine.render(&g, size: size, polys: p, cam: .eye(r, s), hide: s.id) }
                        .frame(height: h)
                        .overlay(alignment: .topLeading) {
                            Text("\(r.a.name) · seat \(s.id) · \(Int(s.m.h.rounded()))° · \(s.m.tv)\" TV · \(s.m.score)")
                                .font(.caption).padding(6).background(.black.opacity(0.6), in: .rect(cornerRadius: 8)).padding(6)
                        }
                }
            }
        }
        .padding(.top, 60)
    }
}
