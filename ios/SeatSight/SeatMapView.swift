import SwiftUI

@main
struct SeatSightApp: App {
    var body: some Scene {
        WindowGroup { MoviesView().preferredColorScheme(.dark).tint(.yellow) }
    }
}

// MARK: - Flow model

struct Show: Hashable, Identifiable, Sendable {
    let movie: Movie, theatre: Theatre, format: String, time: String, day: Int
    var id: String { movie.id + theatre.id + String(day) + format + time }
    var seed: String { id }   // same seed as the web app, so sold seats match
    var auditorium: Auditorium { .find(theatre.rooms[format] ?? "") }
    var film: Double { movie.film(for: format) }

    static let formats = ["IMAX", "UltraAVX", "Regular", "VIP"]
    static let times = ["11:30", "13:15", "14:40", "16:10", "17:45", "19:00", "20:20", "21:40", "22:50"]
    static let why = [
        "IMAX": "Biggest, tallest screen and steep seating. Scenes shot for IMAX fill more of the frame.",
        "UltraAVX": "Wall-to-wall screen, reclining seats, big sound.",
        "Regular": "Standard screen and seats.",
        "VIP": "19+, full recliners, food to your seat. Smaller screen.",
    ]
    static func times(_ m: Movie, _ t: Theatre, _ day: Int, _ format: String) -> [String] {
        let h = Int(fnv(m.id + t.id + String(day) + format) % 4)
        return (0..<(format == "VIP" ? 2 : 3)).map { times[h + $0 * 2] }
    }
    static func dayLabel(_ k: Int) -> String {
        if k == 0 { return "Today" }
        if k == 1 { return "Tomorrow" }
        return Date(timeIntervalSinceNow: Double(k) * 86400).formatted(.dateTime.weekday(.abbreviated).day())
    }
}

struct Poster: View {
    let movie: Movie
    var small = false
    var body: some View {
        let c0 = Color(hex: movie.colors[0]), c1 = Color(hex: movie.colors[1])
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [c0, c0, c1.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { g in
                Circle().fill(c1.opacity(0.85)).frame(width: g.size.width * 0.7).offset(x: g.size.width * 0.45, y: g.size.height * 0.12)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
            Text(movie.title).font(.system(size: small ? 10 : 19, weight: .heavy)).padding(small ? 5 : 10).shadow(radius: 6)
            if !small && movie.film == "imax" {
                Text("FILMED FOR IMAX").font(.system(size: 9, weight: .bold)).padding(4).background(.black.opacity(0.6), in: .rect(cornerRadius: 5))
                    .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(.rect(cornerRadius: small ? 8 : 12))
    }
}

extension Color {
    init(hex: String) { let v = Engine.hex(hex) / 255; self.init(red: v.x, green: v.y, blue: v.z) }
}

// MARK: - 1. Movies

struct MoviesView: View {
    @AppStorage("theatre") private var theatreID = "harbourfront"
    private var theatre: Theatre { Catalog.shared.theatres.first { $0.id == theatreID } ?? Catalog.shared.theatres[0] }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 18) {
                    ForEach(Catalog.shared.movies) { m in
                        NavigationLink(value: m) {
                            VStack(alignment: .leading, spacing: 6) {
                                Poster(movie: m)
                                Text(m.meta).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                Text("Movies, theatres, showtimes and sold seats are made up. Room sizes are typical values. Not affiliated with any cinema chain.")
                    .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 16)
            }
            .navigationTitle("Now playing")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Theatre", selection: $theatreID) {
                        ForEach(Catalog.shared.theatres) { Text($0.name).tag($0.id) }
                    }
                }
            }
            .navigationDestination(for: Movie.self) { ShowtimesView(movie: $0, theatre: theatre) }
            .navigationDestination(for: Show.self) { SeatMapView(show: $0) }
        }
    }
}

// MARK: - 2. Showtimes

struct ShowtimesView: View {
    let movie: Movie
    let theatre: Theatre
    @State private var day = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Poster(movie: movie, small: true).frame(width: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(movie.title).font(.title2.bold())
                        Text("\(movie.meta) · \(movie.filmName)").font(.caption).foregroundStyle(.secondary)
                        Text(theatre.name).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<7, id: \.self) { k in
                            Button(Show.dayLabel(k)) { day = k }
                                .buttonStyle(.bordered)
                                .tint(k == day ? .yellow : .gray)
                        }
                    }
                }
                ForEach(movie.formats, id: \.self) { fmt in
                    formatCard(fmt, Auditorium.find(theatre.rooms[fmt] ?? ""))
                }
            }
            .padding(16)
        }
        .navigationTitle("Showtimes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatCard(_ fmt: String, _ a: Auditorium) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(a.name).font(.headline)
            Text("\(a.variant) · Auditorium \((Show.formats.firstIndex(of: fmt) ?? 0) + 1) · \(a.screen.width.formatted()) m screen")
                .font(.caption).foregroundStyle(.secondary)
            Text(Show.why[fmt] ?? "").font(.caption).foregroundStyle(.secondary)
            HStack {
                ForEach(Show.times(movie, theatre, day, fmt), id: \.self) { t in
                    NavigationLink(t, value: Show(movie: movie, theatre: theatre, format: fmt, time: t, day: day))
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.08), in: .rect(cornerRadius: 14))
    }
}

// MARK: - 3. Seats

struct SeatMapView: View {
    let show: Show
    @State private var cfg: Auditorium
    @State private var room: Room
    @State private var selected: Seat?
    @State private var viewing: Seat?
    @State private var heat = false
    @State private var crowd = false
    @State private var showTweak = false

    init(show: Show) {
        self.show = show
        _cfg = State(initialValue: show.auditorium)
        _room = State(initialValue: Room(show.auditorium, seed: show.seed))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Poster(movie: show.movie, small: true).frame(width: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(show.movie.title).font(.headline)
                        Text("\(cfg.name) · \(cfg.variant)").font(.caption).foregroundStyle(.secondary)
                        Text("\(Show.dayLabel(show.day)) \(show.time) · \(show.theatre.name)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Toggle("Best seats", isOn: $heat).toggleStyle(.button)
                    Toggle("Crowd", isOn: $crowd).toggleStyle(.button)
                    Spacer()
                    Button("Best: \(room.best.id)", systemImage: "star.fill") { open(room.best) }
                }
                .buttonStyle(.bordered)
                seatMap
                legend
            }
            .padding(16)
        }
        .navigationTitle("Pick a seat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Adjust room", systemImage: "slider.horizontal.3") { showTweak = true } }
        }
        .safeAreaInset(edge: .bottom) { tray }
        .sheet(isPresented: $showTweak) { tweakSheet.presentationDetents([.medium]) }
        .fullScreenCover(item: $viewing) { seat in
            SeatView3D(room: room, seat: seat, show: show, crowd: crowd) { selected = $0 }
        }
    }

    @ViewBuilder private var tray: some View {
        if let s = selected {
            HStack {
                VStack(alignment: .leading) {
                    Text("Seat \(s.id)").font(.headline)
                    Text("Score \(s.m.score) · \(cfg.name) · \(show.time)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("See the view") { viewing = s }.buttonStyle(.borderedProminent).foregroundStyle(.black)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private var seatMap: some View {
        GeometryReader { geo in
            let cols = Double(room.rows.map { $0.seats.count + ($0.parts.count - 1) * 2 }.max() ?? 20) + 2
            let s = min(26, max(8, (geo.size.width - 8) / cols - 2))
            VStack(spacing: 3) {
                Text("\(cfg.name) screen · \(String(format: "%.1f", room.W)) m wide")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .overlay(alignment: .top) {
                        Capsule().fill(Color(white: 0.85)).frame(width: geo.size.width * min(0.92, 0.4 + room.W * 0.022), height: 3)
                    }
                    .padding(.bottom, 16)
                ForEach(room.rows, id: \.label) { row in
                    HStack(spacing: 2) {
                        Text(row.label).font(.system(size: 9)).foregroundStyle(.secondary).frame(width: s)
                        ForEach(row.seats) { seat in
                            if seat.num > 1, seat.section != row.seats[seat.num - 2].section { Color.clear.frame(width: s * 1.4, height: s) }
                            seatButton(seat, size: s)
                        }
                        Text(row.label).font(.system(size: 9)).foregroundStyle(.secondary).frame(width: s)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: CGFloat(room.rows.count) * 26 + 60)
        .padding(.vertical, 8)
        .background(Color(white: 0.08), in: .rect(cornerRadius: 16))
    }

    private func seatButton(_ seat: Seat, size: Double) -> some View {
        let color: Color = seat.id == selected?.id ? .yellow
            : seat.sold ? Color(white: 0.12)
            : heat ? Color(hue: Double(seat.m.score) / 300, saturation: 0.65, brightness: 0.7)
            : Color(red: 0.23, green: 0.25, blue: 0.34)
        return Button { open(seat) } label: {
            UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 5, bottomTrailingRadius: 5, topTrailingRadius: 3)
                .fill(color)
                .overlay { if seat.sold { Image(systemName: "xmark").font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(Color(white: 0.3)) } }
                .overlay { if seat.id == room.best.id { RoundedRectangle(cornerRadius: 4).stroke(.yellow, lineWidth: 1.5) } }
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .disabled(seat.sold)
        .accessibilityLabel("Seat \(seat.id), \(seat.sold ? "taken" : "score \(seat.m.score)")")
    }

    private var legend: some View {
        HStack(spacing: 14) {
            Label("Available", systemImage: "square.fill").foregroundStyle(Color(red: 0.23, green: 0.25, blue: 0.34))
            Label("Taken", systemImage: "xmark.square.fill").foregroundStyle(Color(white: 0.3))
            Label("Yours", systemImage: "square.fill").foregroundStyle(.yellow)
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
    }

    private func open(_ seat: Seat) {
        guard !seat.sold else { return }
        selected = seat
        viewing = seat
    }

    private var tweakSheet: some View {
        Form {
            Section("Match your theatre") {
                slider("Screen width", value: $cfg.screen.width, in: 6...30)
                slider("First row distance", value: $cfg.firstRow, in: 2...10)
                slider("Rake (step per row)", value: $cfg.riser, in: 0.1...0.8)
            }
            Button("Reset to typical") { cfg = show.auditorium; rebuild() }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(String(format: "%.2f", value.wrappedValue)) m")
            Slider(value: value, in: range) { _ in rebuild() }
        }
    }

    private func rebuild() {
        room = Room(cfg, seed: show.seed)
        if let s = selected { selected = room.seats.first { $0.id == s.id && !$0.sold } }
    }
}
