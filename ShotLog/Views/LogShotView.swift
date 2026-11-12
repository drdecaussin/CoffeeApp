import SwiftUI
import SwiftData
import PhotosUI

struct BeanInfo: Identifiable {
    let id: String
    let name: String
    let roaster: String
    let bean: String
    let roast: Roast?
    let count: Int
}

func knownBeans(_ shots: [Shot]) -> [BeanInfo] {
    var order: [String] = []
    var first: [String: Shot] = [:]
    var counts: [String: Int] = [:]
    for s in shots { // newest first
        let k = s.beanKey
        if first[k] == nil { first[k] = s; order.append(k) }
        counts[k, default: 0] += 1
    }
    return order.compactMap { k in
        guard let s = first[k] else { return nil }
        return BeanInfo(id: k, name: s.beanName, roaster: s.roaster, bean: s.bean, roast: s.roast, count: counts[k] ?? 0)
    }
}

enum PhotoTarget: String, Identifiable {
    case puck, bag
    var id: String { rawValue }
}

struct LogShotView: View {
    /// nil = logging a new shot.
    var editing: Shot?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Query(sort: \Shot.date, order: .reverse) private var shots: [Shot]
    @Query private var bags: [BeanBag]

    @State private var d = ShotDraft()
    @State private var loaded = false
    @State private var dateTouched = false
    @State private var cameraTarget: PhotoTarget?
    @State private var pickerItem: PhotosPickerItem?
    @State private var bagPickerItem: PhotosPickerItem?
    /// A bag photo picked in this form, saved with the shot.
    @State private var newBag: (photo: Data?, thumb: Data?)?
    @State private var flash: String?

    var body: some View {
        Form {
            beansSection
            dialSection
            grindSection
            extractionSection
            resultSection
            photoSection
            moreSection
            Section {
                Button(action: save) {
                    Text(editing == nil ? "Save shot" : "Save changes")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!d.hasBean)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                if !d.hasBean { Text("Add the roaster or bean so you can compare shots later.") }
            }
        }
        .navigationTitle(editing == nil ? "Log shot" : "Edit shot")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            if editing != nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
            }
        }
        .overlay(alignment: .bottom) {
            if let flash {
                Text(flash)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear(perform: load)
        .onChange(of: app.templateStamp) { _, _ in applyTemplate() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    setPhoto(img)
                }
                pickerItem = nil
            }
        }
        .onChange(of: bagPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    setBag(img)
                }
                bagPickerItem = nil
            }
        }
        .fullScreenCover(item: $cameraTarget) { target in
            CameraPicker { img in
                if target == .bag { setBag(img) } else { setPhoto(img) }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Sections

    private var beansSection: some View {
        Section("Beans") {
            TextField("Roaster", text: $d.roaster)
                .textInputAutocapitalization(.words)
            TextField("Bean or blend", text: $d.bean)
                .textInputAutocapitalization(.words)
            let beans = knownBeans(shots)
            if !beans.isEmpty {
                Menu {
                    ForEach(beans) { b in
                        Button("\(b.name) (\(b.count))") {
                            d.roaster = b.roaster
                            d.bean = b.bean
                            newBag = nil
                            if let r = b.roast { d.roast = r }
                        }
                    }
                } label: {
                    Label("Pick a bean you've used", systemImage: "list.bullet")
                }
            }
            Picker("Roast", selection: $d.roast) {
                Text("Not set").tag(Roast?.none)
                ForEach(Roast.allCases) { r in Text(r.label).tag(Roast?.some(r)) }
            }
            if d.hasBean { bagRow }
        }
    }

    private var currentBagThumb: Data? {
        if let nb = newBag { return nb.thumb }
        return bags.first(where: { $0.key == d.beanKey })?.thumb
    }

    private var bagRow: some View {
        HStack(spacing: 12) {
            if let data = currentBagThumb, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 56, height: 56)
                    .overlay(Image(systemName: "bag").foregroundStyle(.secondary))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Bag photo").font(.subheadline)
                HStack(spacing: 8) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { cameraTarget = .bag } label: { Label("Camera", systemImage: "camera") }
                            .buttonStyle(.bordered)
                    }
                    PhotosPicker(selection: $bagPickerItem, matching: .images) {
                        Label("Library", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.small)
            }
        }
    }

    private var beanShots: [Shot] {
        let key = d.beanKey
        let editingID = editing?.persistentModelID
        return shots.filter { $0.beanKey == key && $0.persistentModelID != editingID }
    }

    @ViewBuilder private var dialSection: some View {
        if d.hasBean {
            let list = beanShots
            Section {
                if let last = list.first {
                    let sug = DialIn.suggest(after: last)
                    let best = DialIn.best(of: list)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Last shot, \(last.date.formatted(.dateTime.weekday(.abbreviated).day().month()))")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            if let p = last.puck { PuckTag(puck: p) }
                        }
                        Text(shotLine(last)).font(.subheadline.monospaced())
                        Text(sug.why).font(.subheadline.weight(.semibold))
                        if let best, best.persistentModelID != last.persistentModelID {
                            Text("Best so far: ").font(.subheadline) + Text(shotLine(best)).font(.subheadline.monospaced())
                        }
                        HStack(spacing: 10) {
                            if sug.grind != nil || sug.dose != nil {
                                Button(useLabel(sug)) {
                                    if let g = sug.grind { d.grind = g }
                                    if let dose = sug.dose { d.doseIn = dose }
                                    show("Settings filled in")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            if let best, best.persistentModelID != last.persistentModelID {
                                Button("Use best") {
                                    d.grind = best.grind
                                    d.innerBurr = best.innerBurr
                                    d.doseIn = best.doseIn
                                    show("Best settings filled in")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                } else {
                    let start = (d.roast ?? .medium).startGrind
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No shots with this bean yet. A good first shot on the Barista Pro: grind \(fmt(start)), 18 g in, aim for 36 g out in 25–30 s.")
                            .font(.subheadline)
                        if d.roast == nil {
                            Text("Set the roast and the starting grind adjusts.").font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Use grind \(fmt(start)), 18 g") {
                            d.grind = start
                            d.doseIn = 18
                            show("Starting settings filled in")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(list.isEmpty ? "New bean" : "Dial-in · \(list.count) shot\(list.count == 1 ? "" : "s") with this bean")
            }
        }
    }

    private var grindSection: some View {
        Section {
            NumberRow(title: "Grind setting", caption: "lower = finer", value: $d.grind, step: 1, decimals: 0)
            NumberRow(title: "Beans in", caption: "g, weighed", value: $d.doseIn, step: 0.1, decimals: 1)
            NumberRow(title: "Out of grinder", caption: "g, in portafilter", value: $d.groundOut, step: 0.1, decimals: 1)
            NumberRow(title: "Inner burr", caption: "optional", value: $d.innerBurr, step: 1, decimals: 0)
            Picker("Basket", selection: $d.basket) {
                Text("Not set").tag(Basket?.none)
                ForEach(Basket.allCases) { b in Text(b.label).tag(Basket?.some(b)) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Puck prep")
                PrepChips(selection: $d.prep)
            }
            if let dose = d.doseIn, let out = d.groundOut {
                LabeledContent("Grinder retention", value: "\(fmt(dose - out)) g")
            }
        } header: {
            Text("Grind & dose")
        }
    }

    private var extractionSection: some View {
        Section("Extraction") {
            ShotTimerRow { secs in d.time = (secs * 10).rounded() / 10 }
            NumberRow(title: "Extraction time", caption: "seconds", value: $d.time, step: 1, decimals: 1)
            NumberRow(title: "Espresso out", caption: "g in cup", value: $d.yieldOut, step: 1, decimals: 1)
            if let r = d.ratio {
                LabeledContent("Ratio", value: ratioText(r))
            }
            if let dose = d.doseIn {
                LabeledContent("1:2 target", value: "\(fmt(dose * 2)) g")
            }
            if let t = d.time {
                if t < DialIn.fastBelow {
                    Text("Fast for a 1:2 shot").foregroundStyle(.blue)
                } else if t > DialIn.slowAbove {
                    Text("Slow for a 1:2 shot").foregroundStyle(.orange)
                } else {
                    Text("In the 25–33 s window").foregroundStyle(.green)
                }
            }
        }
    }

    private var resultSection: some View {
        Section {
            PuckPicker(selection: $d.puck)
            Picker("Taste", selection: $d.taste) {
                Text("–").tag(Taste?.none)
                ForEach(Taste.allCases) { t in Text(t.label).tag(Taste?.some(t)) }
            }
            .pickerStyle(.segmented)
            Picker("Drink made", selection: $d.drink) {
                Text("Not set").tag(Drink?.none)
                ForEach(Drink.allCases) { dr in Text(dr.label).tag(Drink?.some(dr)) }
            }
            TextField("Notes: channeling, crema, what you changed…", text: $d.notes, axis: .vertical)
                .lineLimit(2...6)
        } header: {
            Text("Puck & cup")
        } footer: {
            Text("Taste is optional, but it sharpens the suggestions.")
        }
    }

    private var photoSection: some View {
        Section("Puck photo") {
            if let data = d.photo, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                Button("Remove photo", role: .destructive) {
                    d.photo = nil
                    d.thumb = nil
                }
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    cameraTarget = .puck
                } label: {
                    Label(d.photo == nil ? "Take photo" : "Retake photo", systemImage: "camera")
                }
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose from library", systemImage: "photo.on.rectangle")
            }
        }
    }

    private var moreSection: some View {
        Section("Machine & date") {
            TextField("Machine", text: $d.machine)
            DatePicker("When", selection: Binding(get: { d.date }, set: { d.date = $0; dateTouched = true }))
            Toggle("Roast date", isOn: $d.hasRoastDate)
            if d.hasRoastDate {
                DatePicker("Roasted on", selection: $d.roastDate, displayedComponents: .date)
                let days = daysBetween(d.roastDate, d.date)
                LabeledContent("Days off roast", value: "\(days)")
                if days < 5 {
                    Text("Very fresh beans gas a lot and can run unevenly. Many roasts settle after 5–7 days.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if days > 45 {
                    Text("Older beans usually need a finer grind.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Actions

    private func useLabel(_ s: Suggestion) -> String {
        var parts: [String] = []
        if let g = s.grind { parts.append("G\(fmt(g))") }
        if let dose = s.dose { parts.append("\(fmt(dose)) g") }
        return "Use " + parts.joined(separator: ", ")
    }

    private func load() {
        if !loaded {
            loaded = true
            if let e = editing {
                d = ShotDraft(from: e, full: true)
                dateTouched = true
                return
            }
            if app.template != nil { applyTemplate(); return }
            if let last = shots.first {
                d = ShotDraft(from: last, full: false)
            } else {
                d.machine = defaultMachine
                d.grind = 15
                d.doseIn = 18
                d.drink = .espresso
            }
        }
        if editing == nil && !dateTouched { d.date = Date() }
    }

    private func applyTemplate() {
        guard editing == nil, let t = app.template else { return }
        d = t
        dateTouched = false
        app.template = nil
        show("Settings copied. Pull the shot, then fill in the results.")
    }

    private func setPhoto(_ img: UIImage) {
        d.photo = ImageTools.jpeg(img, maxSide: 1600, quality: 0.8)
        d.thumb = ImageTools.jpeg(img, maxSide: 200, quality: 0.7)
    }

    private func setBag(_ img: UIImage) {
        newBag = (ImageTools.jpeg(img, maxSide: 1600, quality: 0.8), ImageTools.jpeg(img, maxSide: 200, quality: 0.7))
    }

    private func saveBag() {
        guard let nb = newBag, d.hasBean else { return }
        let key = d.beanKey
        let bag = bags.first(where: { $0.key == key }) ?? {
            let b = BeanBag(key: key)
            context.insert(b)
            return b
        }()
        bag.photo = nb.photo
        bag.thumb = nb.thumb
        bag.updated = Date()
        newBag = nil
    }

    private func save() {
        hideKeyboard()
        saveBag()
        if editing == nil && !dateTouched { d.date = Date() }
        let shot = editing ?? Shot()
        d.apply(to: shot)
        if editing == nil { context.insert(shot) }
        try? context.save()
        if editing != nil {
            dismiss()
            return
        }
        // Keep this shot's settings ready for tomorrow.
        d = ShotDraft(from: shot, full: false)
        dateTouched = false
        show("Shot saved")
        app.tab = .history
    }

    private func show(_ msg: String) {
        withAnimation { flash = msg }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { withAnimation { if flash == msg { flash = nil } } }
        }
    }
}
