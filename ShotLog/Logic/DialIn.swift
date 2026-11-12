import Foundation
import UIKit

struct Suggestion {
    var grind: Double?
    var dose: Double?
    var why: String
}

enum DialIn {
    static let fastBelow: Double = 25
    static let slowAbove: Double = 33

    /// Higher is better. A firm puck, 25–33 s, balanced taste and a 1:1.8–1:2.5 ratio mark a dialed-in shot.
    static func score(_ s: Shot) -> Int {
        var p = 0
        switch s.puck {
        case .firm: p += 2
        case .dry: p += 1
        case .soupy: p -= 2
        default: break
        }
        if let t = s.time, t >= fastBelow, t <= slowAbove { p += 2 }
        if s.taste == .balanced { p += 2 } else if s.taste != nil { p -= 1 }
        if let r = s.ratio, r >= 1.8, r <= 2.5 { p += 1 }
        return p
    }

    /// Best shot in the list (newest wins ties), or nil when none is good enough.
    static func best(of shots: [Shot]) -> Shot? {
        var best: Shot?
        var bestScore = Int.min
        for s in shots {
            let sc = score(s)
            if sc > bestScore { bestScore = sc; best = s }
        }
        return bestScore >= 3 ? best : nil
    }

    /// What to change after `s`, the last shot with this bean. Barista Pro: lower grind number = finer.
    static func suggest(after s: Shot) -> Suggestion {
        var g = s.grind
        var d = s.doseIn
        var why: String
        let fast = (s.time ?? fastBelow) < fastBelow
        let slow = (s.time ?? slowAbove) > slowAbove

        switch s.puck {
        case .soupy:
            if fast {
                g = g.map { $0 - 2 }
                why = "Soupy puck and a fast shot. Grind 2 steps finer."
            } else {
                d = d.map { $0 + 0.5 }
                why = "Soupy puck means too much headspace above the coffee. Add 0.5 g to the basket."
            }
        case .wet:
            if fast {
                g = g.map { $0 - 1 }
                why = "Wet puck and fast. Grind 1 step finer."
            } else {
                d = d.map { $0 + 0.3 }
                why = "Slightly wet puck. Add about 0.3 g."
            }
        default:
            if fast {
                g = g.map { $0 - 1 }
                why = "Ran fast (under 25 s). Grind 1 step finer."
            } else if slow {
                g = g.map { $0 + 1 }
                why = "Ran slow (over 33 s). Grind 1 step coarser."
            } else if s.taste == .sour {
                g = g.map { $0 - 1 }
                why = "Tasted sour. Grind 1 step finer to extract more."
            } else if s.taste == .bitter {
                g = g.map { $0 + 1 }
                why = "Tasted bitter. Grind 1 step coarser."
            } else {
                why = "Last shot landed well. Repeat it."
            }
        }
        if s.puck == .soupy, s.basket == .single || s.basket == .singlePressurized, (s.doseIn ?? 0) > 14 {
            why += " Also check the basket: a single basket holds about 9–12 g."
        }
        if let gg = g { g = min(30, max(1, gg)) }
        if let dd = d { d = (dd * 10).rounded() / 10 }
        return Suggestion(grind: g, dose: d, why: why)
    }
}

// MARK: - Formatting

func fmt(_ v: Double?) -> String {
    guard let v, v.isFinite else { return "–" }
    let r = (v * 10).rounded() / 10
    return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
}

func ratioText(_ r: Double?) -> String {
    guard let r else { return "–" }
    return "1:" + String(format: "%.1f", r)
}

func shotLine(_ s: Shot) -> String {
    var parts: [String] = []
    if let g = s.grind { parts.append("G" + fmt(g) + (s.innerBurr.map { "/" + fmt($0) } ?? "")) }
    if s.doseIn != nil || s.yieldOut != nil { parts.append("\(fmt(s.doseIn)) → \(fmt(s.yieldOut)) g") }
    if let t = s.time { parts.append(fmt(t) + " s") }
    if let r = s.ratio { parts.append(ratioText(r)) }
    return parts.joined(separator: " · ")
}

// MARK: - Images

enum ImageTools {
    static func jpeg(_ img: UIImage, maxSide: CGFloat, quality: CGFloat) -> Data? {
        let longest = max(img.size.width, img.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        let size = CGSize(width: (img.size.width * scale).rounded(), height: (img.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
        return out.jpegData(compressionQuality: quality)
    }
}

// MARK: - CSV export

enum CSV {
    static func make(_ shots: [Shot]) -> String {
        let iso = ISO8601DateFormatter()
        let header = ["date", "machine", "roaster", "bean", "roast", "roast_date", "grind", "inner_burr", "dose_in_g", "ground_out_g", "time_s", "yield_g", "ratio", "puck", "taste", "basket", "prep", "drink", "notes"]
        func cell(_ s: String) -> String {
            s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        func n(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "" }
        var lines = [header.joined(separator: ",")]
        for s in shots.sorted(by: { $0.date < $1.date }) {
            let row = [iso.string(from: s.date), s.machine, s.roaster, s.bean, s.roastRaw ?? "", s.roastDate.map { iso.string(from: $0) } ?? "",
                       n(s.grind), n(s.innerBurr), n(s.doseIn), n(s.groundOut), n(s.time), n(s.yieldOut), s.ratio.map { String(format: "%.2f", $0) } ?? "",
                       s.puckRaw ?? "", s.tasteRaw ?? "", s.basketRaw ?? "", s.prep.joined(separator: "; "), s.drinkRaw ?? "", s.notes]
            lines.append(row.map(cell).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}
