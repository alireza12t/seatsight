import SwiftUI
import simd

struct SeatView3D: View {
    let room: Room
    @State var seat: Seat
    let show: Show
    var onChoose: (Seat) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var polys: [Poly] = []
    @State private var cam = Camera(pos: .zero, yaw: 0, pitch: 0)
    @State private var flight: (from: Camera, to: Camera, start: Date, duration: Double)?
    @State private var lastDrag: CGSize = .zero
    @State private var baseZoom = 1.0
    @State private var roomMode = false
    @State private var comparing = false
    @State private var expanded = false
    @State private var message: String?

    private static let compareIDs = ["imax-190", "ultraavx", "regular-large", "vip"]
    private var compact: Bool { sizeClass == .compact }
    private var centerY: Double { compact && !roomMode ? 0.36 : 0.5 }

    var body: some View {
        ZStack {
            Color(red: 0.024, green: 0.027, blue: 0.04).ignoresSafeArea()
            if comparing { compareGrid } else { scene3D; sheet }
            if let message {
                Text(message).font(.subheadline).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.black.opacity(0.7), in: .capsule).transition(.opacity)
            }
        }
        .overlay(alignment: .top) { topBar }
        .task { if Demo.on { await demo() } }
        .onChange(of: seat.id, initial: true) { old, _ in
            let first = old == seat.id
            polys = Engine.scene(room, film: show.film, selfID: seat.id)
            roomMode = false
            expanded = !compact
            fly(from: first ? Camera.over(room) : current(Date()), to: Camera.eye(room, seat), duration: first ? 1.3 : 0.7)
            if first { flash("Drag to look around. Pinch out to see the whole room.", 3) }
        }
    }

    // MARK: 3D

    private var scene3D: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: flight == nil)) { tl in
                Canvas { g, size in
                    let c = current(tl.date)
                    let near = simd_distance(c.pos, V3(seat.x, seat.eye, seat.z)) < 1
                    Engine.render(&g, size: size, polys: polys, cam: c, highlight: seat.id, hide: near ? seat.id : nil,
                                  map: roomMode, pin: roomMode ? V3(seat.x, seat.eye + 0.9, seat.z) : nil, centerY: centerY)
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
                            if !roomMode && z < 0.7 { setRoom(true) } else if flight == nil { cam.zoom = min(4, max(0.6, z)) }
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
        guard let id = Engine.pick(pt, size: size, polys: polys, cam: current(Date()), centerY: centerY),
              let s = room.seats.first(where: { $0.id == id }), s.id != seat.id else { return }
        if s.sold { flash("\(room.name(s)) is taken") } else { seat = s }
    }

    private func flash(_ text: String, _ seconds: Double = 1.4) {
        withAnimation { message = text }
        Task { try? await Task.sleep(for: .seconds(seconds)); withAnimation { if message == text { message = nil } } }
    }

    private func setRoom(_ on: Bool) {
        guard on != roomMode else { return }
        roomMode = on
        fly(from: current(Date()), to: on ? Camera.over(room) : Camera.eye(room, seat), duration: 0.9)
        if on { flash("Tap any teal seat to move there", 2.5) }
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

    /// Scripted walkthrough for screen recordings (Demo.on only).
    private func demo() async {
        await Demo.wait(3.2)
        let base = cam
        var look = base; look.yaw -= 0.45
        fly(from: base, to: look, duration: 1.4); await Demo.wait(1.8)
        fly(from: look, to: base, duration: 1.4); await Demo.wait(1.8)
        withAnimation(.snappy) { expanded = true }; await Demo.wait(3)
        setRoom(true); await Demo.wait(2.6)
        if let s = room.seats.first(where: { !$0.sold && $0.row == seat.row + 2 && $0.m.score > 70 && $0.id != seat.id }) { seat = s }
        await Demo.wait(3.4)
        withAnimation(.snappy) { expanded = true }; await Demo.wait(2.5)
        comparing = true; await Demo.wait(4)
        comparing = false; await Demo.wait(1.5)
        onChoose(seat); dismiss()
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 8) {
            circle("xmark", "Close") { dismiss() }
            Spacer()
            if !comparing {
                Picker("View", selection: Binding(get: { roomMode }, set: { setRoom($0) })) {
                    Text("My view").tag(false)
                    Text("Room").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            Spacer()
            circle(comparing ? "rectangle" : "square.grid.2x2", "Compare screen types") { comparing.toggle() }
            ShareLink(item: shareURL, message: Text("\(room.name(seat)) for \(show.movie.title) in \(show.format): \(seat.m.verdict.lowercased()), like a \(seat.m.tv)\" TV.")) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .semibold)).frame(width: 38, height: 38).background(.ultraThinMaterial, in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.top, 6)
    }

    private func circle(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).frame(width: 38, height: 38).background(.ultraThinMaterial, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private static let icons = ["screen": "tv", "neck": "arrow.up", "heads": "person.fill", "center": "scope"]

    private var sheet: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(room.name(seat)).font(.title3.bold())
                        Text("\(show.format) · \(show.movie.title) · \(show.time)").font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(seat.m.verdict).font(.footnote.bold()).foregroundStyle(Theme.tone(seat.m.tone))
                        .padding(.horizontal, 10).padding(.vertical, 5).background(.white.opacity(0.08), in: .capsule)
                }
                if !roomMode {
                    if expanded {
                        ForEach(seat.m.facts, id: \.self) { f in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: Self.icons[f.k] ?? "circle").font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(f.ok ? Theme.open : Theme.tone("okay"))
                                    .frame(width: 30, height: 30).background(.white.opacity(0.06), in: .rect(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(f.t).font(.subheadline)
                                    if !f.sub.isEmpty { Text(f.sub).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                        Text("An estimate from a typical room and average height. Real rooms and people vary.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    } else {
                        let warn = seat.m.facts.filter { !$0.ok }.count
                        Button { withAnimation(.snappy) { expanded = true } } label: {
                            Text((warn > 0 ? "\(warn) thing\(warn > 1 ? "s" : "") to know · " : "") + "See details ›").font(.footnote).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    onChoose(seat)
                    dismiss()
                } label: {
                    Text("Choose this seat").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .foregroundStyle(.white).background(Theme.pick, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .frame(maxWidth: 420)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 26))
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            .padding(12)
        }
    }

    private var shareURL: URL {
        var c = URLComponents(string: "https://alireza12t.github.io/seatsight/")!
        c.fragment = "t=\(show.theatre.id)&d=\(show.day)&m=\(show.movie.id)&fmt=\(show.format)&at=\(show.time)&seat=\(seat.id)"
        return c.url!
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
                    let p = Engine.scene(r, film: show.movie.film(for: r.a.format), selfID: s.id)
                    Canvas { g, size in Engine.render(&g, size: size, polys: p, cam: .eye(r, s), hide: s.id) }
                        .frame(height: h)
                        .overlay(alignment: .bottomLeading) {
                            HStack(spacing: 6) {
                                Text(r.a.format).bold()
                                Text(s.m.verdict).foregroundStyle(Theme.tone(s.m.tone))
                                Text("· like a \(s.m.tv)\" TV").foregroundStyle(.secondary)
                            }
                            .font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.black.opacity(0.65), in: .rect(cornerRadius: 10)).padding(10)
                        }
                }
            }
        }
        .padding(.top, 60)
    }
}
