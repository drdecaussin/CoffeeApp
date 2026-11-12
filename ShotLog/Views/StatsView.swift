import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

struct CSVExport: Transferable {
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("shot-log.csv")
            try export.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

struct DrinkCount: Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}

struct StatsView: View {
    @Query(sort: \Shot.date, order: .reverse) private var shots: [Shot]
    @Query private var bags: [BeanBag]
    @State private var beanKey = ""

    var body: some View {
        Group {
            if shots.isEmpty {
                ContentUnavailableView {
                    Label("No stats yet", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Log a few shots and this shows which grind and dose worked for each bean.")
                }
            } else {
                List {
                    Section { tiles }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    beanSection
                    allBeansSection
                    drinksSection
                }
            }
        }
        .navigationTitle("Stats")
        .toolbar {
            if !shots.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: CSVExport(text: CSV.make(shots)), preview: SharePreview("Shot log.csv")) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    // MARK: Tiles

    private var streak: Int {
        let cal = Calendar.current
        let days = Set(shots.map { cal.startOfDay(for: $0.date) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var n = 0
        while days.contains(day) {
            n += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return n
    }

    private var tiles: some View {
        let now = Date()
        let week = shots.filter { now.timeIntervalSince($0.date) < 7 * 86400 }.count
        let recent = shots.filter { now.timeIntervalSince($0.date) < 14 * 86400 && $0.puck != nil }
        let firm = recent.isEmpty ? "–" : "\(Int((100.0 * Double(recent.filter { $0.puck == .firm }.count) / Double(recent.count)).rounded()))%"
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            tile("\(shots.count)", "shots logged")
            tile("\(week)", "in the last 7 days")
            tile("\(streak)", "day streak")
            tile(firm, "firm pucks, last 14 days")
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.monospacedDigit().weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Per bean

    private var beans: [BeanInfo] { knownBeans(shots) }

    private var selectedKey: String {
        let all = beans
        return all.contains(where: { $0.id == beanKey }) ? beanKey : (all.first?.id ?? "")
    }

    @ViewBuilder private var beanSection: some View {
        let key = selectedKey
        let list = shots.filter { $0.beanKey == key }
        let best = DialIn.best(of: list)
        Section {
            Picker("Bean", selection: Binding(get: { selectedKey }, set: { beanKey = $0 })) {
                ForEach(beans) { b in Text("\(b.name) (\(b.count))").tag(b.id) }
            }
            if let data = bags.first(where: { $0.key == key })?.thumb, let img = UIImage(data: data) {
                HStack {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    if let r = list.first?.roast { Text(r.label).foregroundStyle(.secondary) }
                }
            }
            if let best {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Best settings (\(best.date.formatted(.dateTime.day().month())))")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        bestCell(fmt(best.grind) + (best.innerBurr.map { "/" + fmt($0) } ?? ""), "grind")
                        bestCell("\(fmt(best.doseIn)) g", "in")
                        bestCell("\(fmt(best.yieldOut)) g", "out")
                        bestCell("\(fmt(best.time)) s", "time")
                    }
                    if let b = best.basket { Text("Basket: \(b.label)").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.vertical, 4)
            } else {
                Text("No dialed-in shot yet. A firm puck at 25–33 s marks one.")
                    .foregroundStyle(.secondary)
            }
            let soupy = list.filter { $0.puck == .soupy }.count
            let ratios = list.compactMap(\.ratio)
            let avg = ratios.isEmpty ? nil : ratios.reduce(0, +) / Double(ratios.count)
            Text("\(list.count) shot\(list.count == 1 ? "" : "s") · \(soupy) soupy · avg ratio \(ratioText(avg))")
                .font(.footnote).foregroundStyle(.secondary)
            scatter(list)
            ForEach(list.prefix(15)) { s in
                HStack {
                    Text(s.date.formatted(.dateTime.day().month())).font(.footnote).frame(width: 56, alignment: .leading)
                    Text(shotLine(s)).font(.footnote.monospaced()).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    if let p = s.puck { PuckTag(puck: p) }
                }
            }
        } header: {
            Text("Dial-in by bean")
        }
    }

    private func bestCell(_ v: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func scatter(_ list: [Shot]) -> some View {
        let pts = list.filter { $0.grind != nil && $0.time != nil }
        if pts.isEmpty {
            Text("Shots with both a grind setting and a time show up on a chart here.")
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            let gs = pts.compactMap(\.grind)
            let lo = (gs.min() ?? 10) - 1, hi = (gs.max() ?? 20) + 1
            let tmax = max(45, (pts.compactMap(\.time).max() ?? 40) + 5)
            VStack(alignment: .leading, spacing: 6) {
                Text("Grind vs extraction time").font(.subheadline).foregroundStyle(.secondary)
                Chart {
                    RectangleMark(xStart: .value("From", lo), xEnd: .value("To", hi),
                                  yStart: .value("Fast", DialIn.fastBelow), yEnd: .value("Slow", DialIn.slowAbove))
                        .foregroundStyle(Color.green.opacity(0.12))
                    ForEach(pts) { s in
                        PointMark(x: .value("Grind", s.grind ?? 0), y: .value("Seconds", s.time ?? 0))
                            .foregroundStyle(by: .value("Puck", s.puck?.label ?? "Not set"))
                            .symbolSize(90)
                    }
                }
                .chartForegroundStyleScale([
                    "Soupy": Puck.soupy.color, "Wet": Puck.wet.color, "Firm": Puck.firm.color,
                    "Dry": Puck.dry.color, "Not set": Color.gray
                ])
                .chartXScale(domain: lo...hi)
                .chartYScale(domain: 0...tmax)
                .chartXAxisLabel("Grind setting (finer ← → coarser)")
                .chartYAxisLabel("Seconds")
                .frame(height: 230)
                Text("Green band: 25–33 s target").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: All beans

    private var allBeansSection: some View {
        Section("All beans") {
            ForEach(beans) { b in
                let list = shots.filter { $0.beanKey == b.id }
                let best = DialIn.best(of: list)
                let soupy = list.isEmpty ? 0 : Int((100.0 * Double(list.filter { $0.puck == .soupy }.count) / Double(list.count)).rounded())
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.name).font(.body.weight(.semibold))
                    Text("\(b.roast?.label ?? "Roast not set") · \(b.count) shot\(b.count == 1 ? "" : "s") · \(soupy)% soupy")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(best.map { "Best: G\(fmt($0.grind)), \(fmt($0.doseIn)) g in" } ?? "Not dialed in yet")
                        .font(.footnote.monospaced())
                }
            }
        }
    }

    // MARK: Drinks

    private var drinksSection: some View {
        let counts = Dictionary(grouping: shots, by: { $0.drink?.label ?? "Not set" }).mapValues(\.count)
        let rows = counts.map { DrinkCount(name: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
        return Section("Drinks") {
            Chart(rows) { row in
                BarMark(x: .value("Shots", row.count), y: .value("Drink", row.name))
                    .foregroundStyle(Color.accentColor)
                    .annotation(position: .trailing) {
                        Text("\(row.count)").font(.caption).foregroundStyle(.secondary)
                    }
            }
            .frame(height: CGFloat(max(1, rows.count)) * 34 + 20)
            .padding(.vertical, 6)
        }
    }
}
