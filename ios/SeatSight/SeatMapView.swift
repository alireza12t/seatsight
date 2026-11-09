import SwiftUI

@main
struct SeatSightApp: App {
    var body: some Scene {
        WindowGroup { SeatMapView().preferredColorScheme(.dark).tint(.yellow) }
    }
}

struct SeatMapView: View {
    @State private var preset = Auditorium.all.first!
    @State private var cfg = Auditorium.all.first!
    @State private var room = Room(Auditorium.all.first!)
    @State private var film = 0.0
    @State private var heat = false
    @State private var crowd = false
    @State private var picked: Seat?
    @State private var showTweak = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    controls
                    seatMap
                    Text("Room sizes are typical values, not measured plans. Fake sold seats. Not affiliated with any cinema chain.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .navigationTitle("SeatSight")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Adjust", systemImage: "slider.horizontal.3") { showTweak = true }
                }
            }
            .sheet(isPresented: $showTweak) { tweakSheet.presentationDetents([.medium]) }
            .fullScreenCover(item: $picked) { seat in
                SeatView3D(room: room, seat: seat, film: film, crowd: crowd)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick a seat, see the screen from it.").foregroundStyle(.secondary)
            Picker("Room", selection: $preset) {
                ForEach(Auditorium.all) { Text("\($0.name) · \($0.variant)").tag($0) }
            }
            .pickerStyle(.menu)
            .onChange(of: preset) { cfg = preset; rebuild() }
            HStack {
                Picker("Movie", selection: $film) {
                    Text("Movie fills screen").tag(0.0)
                    Text("Scope 2.39").tag(2.39)
                    Text("Flat 1.85").tag(1.85)
                }
                .pickerStyle(.menu)
                Toggle("Best seats", isOn: $heat).toggleStyle(.button)
                Toggle("Crowd", isOn: $crowd).toggleStyle(.button)
            }
            Button("Best seat: \(room.best.id) (\(room.best.m.score))", systemImage: "star.fill") { picked = room.best }
                .buttonStyle(.bordered)
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
        let color: Color = heat
            ? Color(hue: Double(seat.m.score) / 300, saturation: 0.65, brightness: seat.sold ? 0.3 : 0.7)
            : seat.sold ? Color(white: 0.13) : Color(red: 0.23, green: 0.25, blue: 0.34)
        return Button { picked = seat } label: {
            UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 5, bottomTrailingRadius: 5, topTrailingRadius: 3)
                .fill(color)
                .overlay { if seat.id == room.best.id { RoundedRectangle(cornerRadius: 4).stroke(.yellow, lineWidth: 1.5) } }
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Seat \(seat.id), score \(seat.m.score)\(seat.sold ? ", sold" : "")")
    }

    private var tweakSheet: some View {
        Form {
            Section("Match your theatre") {
                slider("Screen width", value: $cfg.screen.width, in: 6...30)
                slider("First row distance", value: $cfg.firstRow, in: 2...10)
                slider("Rake (step per row)", value: $cfg.riser, in: 0.1...0.8)
            }
            Button("Reset to typical") { cfg = preset; rebuild() }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(String(format: "%.2f", value.wrappedValue)) m")
            Slider(value: value, in: range) { _ in rebuild() }
        }
    }

    private func rebuild() { room = Room(cfg) }
}
