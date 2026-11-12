import SwiftUI
import UIKit

/// A labelled number with − / + buttons and a typed field.
struct NumberRow: View {
    let title: String
    let caption: String
    @Binding var value: Double?
    let step: Double
    let decimals: Int
    @State private var text = ""

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Button { bump(-step) } label: {
                Image(systemName: "minus.circle.fill").font(.title2)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Decrease \(title)")
            TextField("–", text: $text)
                .keyboardType(decimals > 0 ? .decimalPad : .numberPad)
                .multilineTextAlignment(.center)
                .font(.title3.monospacedDigit().weight(.semibold))
                .frame(width: 66)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: text) { _, new in
                    let cleaned = new.replacingOccurrences(of: ",", with: ".")
                    if cleaned.isEmpty { value = nil } else if let v = Double(cleaned) { value = v }
                }
            Button { bump(step) } label: {
                Image(systemName: "plus.circle.fill").font(.title2)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Increase \(title)")
        }
        .onAppear { text = format(value) }
        .onChange(of: value) { _, new in
            let current = Double(text.replacingOccurrences(of: ",", with: "."))
            if current != new { text = format(new) }
        }
    }

    private func bump(_ s: Double) {
        let v = max(0, (value ?? 0) + s)
        value = (v * 10).rounded() / 10
    }

    private func format(_ v: Double?) -> String {
        guard let v else { return "" }
        return decimals == 0 ? String(Int(v.rounded())) : String(format: "%.\(decimals)f", v)
    }
}

/// Start/stop shot timer. Keeps the screen awake while running.
struct ShotTimerRow: View {
    var onStop: (Double) -> Void
    @State private var start: Date?
    @State private var last: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if let s = start {
                    let elapsed = Date().timeIntervalSince(s)
                    last = elapsed
                    start = nil
                    UIApplication.shared.isIdleTimerDisabled = false
                    onStop(elapsed)
                } else {
                    last = 0
                    start = Date()
                    UIApplication.shared.isIdleTimerDisabled = true
                }
            } label: {
                Text(start == nil ? "Start timer" : "Stop")
                    .bold()
                    .frame(minWidth: 110)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(start == nil ? Color.accentColor : Color.red)

            Spacer(minLength: 0)

            TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                let v = start.map { ctx.date.timeIntervalSince($0) } ?? last
                Text(String(format: "%.1f s", v))
                    .font(.system(size: 32, weight: .semibold, design: .monospaced))
                    .contentTransition(.numericText())
            }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

struct PuckPicker: View {
    @Binding var selection: Puck?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Puck.allCases) { p in
                let on = selection == p
                Button {
                    selection = on ? nil : p
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .strokeBorder(p.color, lineWidth: 3)
                            .background(Circle().fill(p.color.opacity(on ? 0.45 : 0.15)))
                            .frame(width: 30, height: 30)
                        Text(p.label).font(.subheadline.weight(on ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(on ? p.color.opacity(0.12) : Color(.tertiarySystemFill))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? p.color : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(p.label): \(p.hint)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

struct PuckTag: View {
    let puck: Puck
    var body: some View {
        Text(puck.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(puck.color)
            .background(puck.color.opacity(0.15), in: Capsule())
    }
}

struct ShotThumb: View {
    let shot: Shot
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let data = shot.thumb, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                let c = shot.puck?.color ?? .gray
                Circle()
                    .strokeBorder(c, lineWidth: 4)
                    .background(Circle().fill(c.opacity(0.2)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// Wraps the system camera.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Multi-select chips that wrap onto new lines.
struct PrepChips: View {
    @Binding var selection: Set<Prep>

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Prep.allCases) { p in
                let on = selection.contains(p)
                Button {
                    if on { selection.remove(p) } else { selection.insert(p) }
                } label: {
                    Label(p.label, systemImage: on ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(on ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
