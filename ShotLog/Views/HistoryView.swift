import SwiftUI
import SwiftData

struct DayGroup: Identifiable {
    let day: Date
    var shots: [Shot]
    var id: Date { day }
}

struct DetailRow: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Shot.date, order: .reverse) private var shots: [Shot]
    @State private var filter = ""

    private var filtered: [Shot] {
        filter.isEmpty ? shots : shots.filter { $0.beanKey == filter }
    }

    private var groups: [DayGroup] {
        var out: [DayGroup] = []
        let cal = Calendar.current
        for s in filtered {
            let day = cal.startOfDay(for: s.date)
            if let last = out.last, last.day == day {
                out[out.count - 1].shots.append(s)
            } else {
                out.append(DayGroup(day: day, shots: [s]))
            }
        }
        return out
    }

    var body: some View {
        Group {
            if shots.isEmpty {
                ContentUnavailableView {
                    Label("No shots yet", systemImage: "cup.and.saucer")
                } description: {
                    Text("Pull your morning shot, then log it on the Log shot tab. Every shot you save shows up here, newest first.")
                }
            } else {
                List {
                    Section {
                        Picker("Show", selection: $filter) {
                            Text("All beans (\(shots.count))").tag("")
                            ForEach(knownBeans(shots)) { b in
                                Text("\(b.name) (\(b.count))").tag(b.id)
                            }
                        }
                    }
                    ForEach(groups) { group in
                        Section(group.day.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
                            ForEach(group.shots) { s in
                                NavigationLink {
                                    ShotDetailView(shot: s)
                                } label: {
                                    ShotRow(shot: s)
                                }
                            }
                            .onDelete { idx in
                                for i in idx { context.delete(group.shots[i]) }
                                try? context.save()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
    }
}

struct ShotRow: View {
    let shot: Shot

    var body: some View {
        HStack(spacing: 12) {
            ShotThumb(shot: shot)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(shot.drink?.label ?? "Shot") · \(shot.beanName)")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(shotLine(shot))
                    .font(.footnote.monospaced())
                    .lineLimit(1)
                Text(shot.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let p = shot.puck { PuckTag(puck: p) }
        }
        .padding(.vertical, 2)
    }
}

struct ShotDetailView: View {
    let shot: Shot
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var editing = false
    @State private var confirmDelete = false
    @Query private var bags: [BeanBag]

    private var bagImage: UIImage? {
        let key = shot.beanKey
        guard let data = bags.first(where: { $0.key == key })?.photo else { return nil }
        return UIImage(data: data)
    }

    private var rows: [DetailRow] {
        var r: [DetailRow] = []
        func add(_ k: String, _ v: String?) { if let v, !v.isEmpty { r.append(DetailRow(label: k, value: v)) } }
        add("Grind", shot.grind.map(fmt))
        add("Inner burr", shot.innerBurr.map(fmt))
        add("Beans in", shot.doseIn.map { "\(fmt($0)) g" })
        add("Out of grinder", shot.groundOut.map { "\(fmt($0)) g" })
        add("Retention", shot.retention.map { "\(fmt($0)) g" })
        add("Time", shot.time.map { "\(fmt($0)) s" })
        add("Espresso out", shot.yieldOut.map { "\(fmt($0)) g" })
        add("Ratio", shot.ratio.map { ratioText($0) })
        add("Puck", shot.puck?.label)
        add("Taste", shot.taste?.label)
        add("Basket", shot.basket?.label)
        add("Puck prep", shot.prep.isEmpty ? nil : shot.prep.joined(separator: ", "))
        add("Drink", shot.drink?.label)
        add("Roast", shot.roast?.label)
        add("Roast date", shot.roastDate?.formatted(date: .abbreviated, time: .omitted))
        add("Days off roast", shot.daysOffRoast.map { "\($0)" })
        add("Machine", shot.machine)
        return r
    }

    var body: some View {
        List {
            if let data = shot.photo, let img = UIImage(data: data) {
                Section {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
            }
            Section(shot.date.formatted(date: .complete, time: .shortened)) {
                ForEach(rows) { row in
                    LabeledContent(row.label) {
                        Text(row.value).font(.body.monospacedDigit())
                    }
                }
            }
            if !shot.notes.isEmpty {
                Section("Notes") { Text(shot.notes) }
            }
            if let bag = bagImage {
                Section("Bag") {
                    Image(uiImage: bag)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
            }
            Section {
                Button {
                    app.brewAgain(shot)
                } label: {
                    Label("Brew again with these settings", systemImage: "arrow.clockwise")
                }
                Button {
                    editing = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete shot", systemImage: "trash")
                }
            }
        }
        .navigationTitle(shot.beanName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) {
            NavigationStack { LogShotView(editing: shot) }
                .environment(app)
        }
        .confirmationDialog("Delete this shot?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(shot)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("It's removed from your history and stats. This can't be undone.")
        }
    }
}
