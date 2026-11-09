import SwiftUI

@main
struct SeatSightApp: App {
    var body: some Scene {
        WindowGroup { MoviesView().preferredColorScheme(.dark).tint(Theme.pick) }
    }
}

/// Debug-only demo mode for screen recordings: launch with -demo and the app taps through the flow itself.
enum Demo {
    static var on: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-demo")
        #else
        false
        #endif
    }
    static func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
}

enum Theme {
    static let bg = Color(red: 0.04, green: 0.043, blue: 0.06)
    static let surface = Color.white.opacity(0.06)
    static let surface2 = Color.white.opacity(0.1)
    static let open = Color(red: 0.15, green: 0.75, blue: 0.67)
    static let taken = Color(red: 0.17, green: 0.18, blue: 0.22)
    static let pick = Color(red: 1, green: 0.36, blue: 0.48)
    static func tone(_ t: String) -> Color {
        switch t {
        case "great": open
        case "good": Color(red: 0.5, green: 0.84, blue: 0.78)
        case "okay": Color(red: 0.96, green: 0.73, blue: 0.29)
        default: Color(red: 1, green: 0.42, blue: 0.42)
        }
    }
}

// MARK: - Flow model

struct Show: Hashable, Identifiable, Sendable {
    let movie: Movie, theatre: Theatre, format: String, time: String, day: Int
    var id: String { movie.id + theatre.id + String(day) + format + time }
    var seed: String { id }   // same seed as the web app, so sold seats match
    var auditorium: Auditorium { .find(theatre.rooms[format] ?? "") }
    var film: Double { movie.film(for: format) }

    static let times = ["11:30", "13:15", "14:40", "16:10", "17:45", "19:00", "20:20", "21:40", "22:50"]
    static let about = ["IMAX": "Biggest screen, steep seating", "UltraAVX": "Wall-to-wall screen, recliners", "Regular": "Classic screen", "VIP": "19+, recliners, food to your seat"]
    static func times(_ m: Movie, _ t: Theatre, _ day: Int, _ format: String) -> [String] {
        let h = Int(fnv(m.id + t.id + String(day) + format) % 4)
        return (0..<(format == "VIP" ? 2 : 3)).map { times[h + $0 * 2] }
    }
    static func date(_ k: Int) -> Date { Date(timeIntervalSinceNow: Double(k) * 86400) }
    static func dayName(_ k: Int) -> String { k == 0 ? "Today" : k == 1 ? "Tomorrow" : date(k).formatted(.dateTime.weekday(.wide)) }
}

struct Poster: View {
    let movie: Movie
    var small = false
    var body: some View {
        let c0 = Color(hex: movie.colors[0]), c1 = Color(hex: movie.colors[1])
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [c0, c0, c1.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { g in
                Circle().fill(c1.opacity(0.9)).frame(width: g.size.width * 0.75).offset(x: g.size.width * 0.43, y: g.size.height * 0.1)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            Text(movie.title).font(.system(size: small ? 11 : 21, weight: .heavy)).tracking(-0.4).padding(small ? 7 : 14)
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(.rect(cornerRadius: small ? 12 : 18))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 8)
    }
}

extension Color {
    init(hex: String) { let v = Engine.hex(hex) / 255; self.init(red: v.x, green: v.y, blue: v.z) }
}

extension Room {
    func name(_ s: Seat) -> String { "Row \(rows[s.row].label) · Seat \(s.num)" }
}

// MARK: - 1. Movies

struct MoviesView: View {
    @AppStorage("theatre") private var theatreID = "harbourfront"
    @State private var path = NavigationPath()
    private var theatre: Theatre { Catalog.shared.theatres.first { $0.id == theatreID } ?? Catalog.shared.theatres[0] }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 22) {
                    ForEach(Catalog.shared.movies) { m in
                        NavigationLink(value: m) {
                            VStack(alignment: .leading, spacing: 8) {
                                Poster(movie: m)
                                Text(m.meta).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                Text("Demo with made-up movies, theatres and sold seats. Room sizes are typical, not measured. Not affiliated with any cinema chain.")
                    .font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(Theme.bg)
            .navigationTitle("Now playing")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Theatre", selection: $theatreID) {
                            ForEach(Catalog.shared.theatres) { Text($0.name).tag($0.id) }
                        }
                    } label: {
                        Label(theatre.name, systemImage: "mappin.and.ellipse").labelStyle(.titleAndIcon).font(.subheadline)
                    }
                }
            }
            .navigationDestination(for: Movie.self) { ShowtimesView(movie: $0, theatre: theatre) }
            .navigationDestination(for: Show.self) { SeatMapView(show: $0) }
        }
        .task {
            guard Demo.on, let m = Catalog.shared.movies.first else { return }
            await Demo.wait(2); path.append(m)
            await Demo.wait(2); path.append(Show(movie: m, theatre: theatre, format: "IMAX", time: Show.times(m, theatre, 0, "IMAX")[0], day: 0))
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
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    Poster(movie: movie, small: true).frame(width: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(movie.title).font(.title2.bold())
                        Text(movie.meta).font(.subheadline).foregroundStyle(.secondary)
                        if movie.film == "imax" { Text("Filmed for IMAX").font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<7, id: \.self) { k in
                            Button { day = k } label: {
                                VStack(spacing: 2) {
                                    Text(k < 2 ? Show.dayName(k) : Show.date(k).formatted(.dateTime.weekday(.abbreviated))).font(.caption)
                                    Text(Show.date(k).formatted(.dateTime.day())).font(.headline)
                                }
                                .frame(minWidth: 58).padding(.vertical, 10).padding(.horizontal, 8)
                                .foregroundStyle(k == day ? .black : .primary)
                                .background(k == day ? Color.white : Theme.surface, in: .rect(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ForEach(movie.formats, id: \.self) { fmt in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fmt).font(.headline)
                        Text(Show.about[fmt] ?? "").font(.footnote).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(Show.times(movie, theatre, day, fmt), id: \.self) { t in
                                NavigationLink(value: Show(movie: movie, theatre: theatre, format: fmt, time: t, day: day)) {
                                    Text(t).font(.subheadline.weight(.semibold).monospacedDigit())
                                        .padding(.horizontal, 16).padding(.vertical, 10)
                                        .background(Theme.surface2, in: .rect(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: .rect(cornerRadius: 18))
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle(theatre.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 3. Seats

struct SeatMapView: View {
    let show: Show
    @State private var room: Room
    @State private var chosen: Seat?
    @State private var viewing: Seat?
    @State private var bestOnly = false

    init(show: Show) {
        self.show = show
        _room = State(initialValue: Room(show.auditorium, seed: show.seed))
    }

    var body: some View {
        GeometryReader { geo in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    capsule(bestOnly ? "Showing best seats" : "Show best seats", on: bestOnly) { bestOnly.toggle() }
                    capsule("Pick the best seat for me", on: false) { open(room.best) }
                }
                seatMap(width: geo.size.width - 32)
            }
            .padding(16)
            .padding(.bottom, 90)
        }
        }
        .background(Theme.bg)
        .navigationTitle(show.movie.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(show.movie.title).font(.headline)
                    Text("\(show.format) · \(Show.dayName(show.day)) \(show.time)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { dock }
        .task {
            guard Demo.on else { return }
            await Demo.wait(2.5); open(room.best)
        }
        .fullScreenCover(item: $viewing) { seat in
            SeatView3D(room: room, seat: seat, show: show) { chosen = $0 }
        }
    }

    private func capsule(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline).padding(.horizontal, 14).padding(.vertical, 9)
                .foregroundStyle(on ? .black : .primary)
                .background(on ? Color.white : Theme.surface, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private var dock: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let s = chosen {
                    Text(room.name(s)).font(.headline)
                    Text(s.m.verdict).font(.caption.bold()).foregroundStyle(Theme.tone(s.m.tone))
                        .padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.08), in: .capsule)
                } else {
                    Text("Pick a seat").font(.headline)
                    Text("Tap any open seat to see your view").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("View from seat") { viewing = chosen }
                .font(.headline)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 18).padding(.vertical, 12)
                .foregroundStyle(chosen == nil ? Color.secondary : Color.white)
                .background(chosen == nil ? Theme.surface : Theme.pick, in: .rect(cornerRadius: 14))
                .disabled(chosen == nil)
        }
        .padding(.leading, 18).padding(.trailing, 12).padding(.vertical, 12)
        .background(.thinMaterial, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 16).padding(.bottom, 6)
    }

    /// Seats are sized to fit the card width, so the whole room is always visible.
    private func seatMap(width: Double) -> some View {
        let gaps = Double(room.rows.map { $0.parts.count - 1 }.max() ?? 2)
        let most = Double(room.rows.map(\.seats.count).max() ?? 20)
        let spacing = 2.5
        // row = 2 labels (14 each) + seats + gaps (1.2 seat each) + spacing between items
        let s = max(7, min(24, (width - 20 - 28 - spacing * (most + gaps + 2)) / (most + gaps * 1.2)))
        return VStack(spacing: 18) {
                VStack(spacing: spacing + 1) {
                    VStack(spacing: 6) {
                        Capsule().fill(.white.opacity(0.9)).frame(height: 3).shadow(color: .indigo, radius: 8, y: -4)
                        Text("SCREEN").font(.caption2).tracking(4).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 40).padding(.bottom, 18)
                    ForEach(room.rows, id: \.label) { row in
                        HStack(spacing: spacing) {
                            Text(row.label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary).frame(width: 14)
                            ForEach(row.seats) { seat in
                                if seat.num > 1, seat.section != row.seats[seat.num - 2].section { Color.clear.frame(width: s * 1.2, height: s) }
                                seatButton(seat, size: s)
                            }
                            Text(row.label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary).frame(width: 14)
                        }
                    }
                }
                .padding(.horizontal, 10)
            HStack(spacing: 16) {
                legend(Theme.open, "Open"); legend(Theme.taken, "Taken"); legend(Theme.pick, "Your seat")
            }
        }
        .padding(.vertical, 22)
        .background(Theme.surface, in: .rect(cornerRadius: 24))
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) { RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 11, height: 11); Text(t) }
            .font(.caption).foregroundStyle(.secondary)
    }

    private func seatButton(_ seat: Seat, size: Double) -> some View {
        let mine = seat.id == chosen?.id
        let color = mine ? Theme.pick : seat.sold ? Theme.taken : Theme.open
        let dim = bestOnly && !mine && !seat.sold && seat.m.score < 85
        return Button { open(seat) } label: {
            UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 4, bottomTrailingRadius: 4, topTrailingRadius: 7)
                .fill(color)
                .opacity(dim ? 0.28 : 1)
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .disabled(seat.sold)
        .accessibilityLabel("\(room.name(seat)), \(seat.sold ? "taken" : seat.m.verdict)")
    }

    private func open(_ seat: Seat) {
        guard !seat.sold else { return }
        chosen = seat
        viewing = seat
    }
}
