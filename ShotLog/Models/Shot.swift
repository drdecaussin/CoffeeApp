import Foundation
import SwiftData
import SwiftUI

let defaultMachine = "Breville Barista Pro"

enum Puck: String, CaseIterable, Identifiable {
    case soupy, wet, firm, dry
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var hint: String {
        switch self {
        case .soupy: return "Water pooled on top"
        case .wet: return "Damp and sloppy"
        case .firm: return "Knocks out whole"
        case .dry: return "Dry or cracked"
        }
    }
    var color: Color {
        switch self {
        case .soupy: return .blue
        case .wet: return .teal
        case .firm: return .green
        case .dry: return .orange
        }
    }
}

enum Taste: String, CaseIterable, Identifiable {
    case sour, balanced, bitter
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum Roast: String, CaseIterable, Identifiable {
    case light = "Light"
    case mediumLight = "Medium-light"
    case medium = "Medium"
    case mediumDark = "Medium-dark"
    case dark = "Dark"
    var id: String { rawValue }
    var label: String { rawValue }
    /// A reasonable first grind setting on a Barista Pro (lower = finer).
    var startGrind: Double {
        switch self {
        case .light: return 11
        case .mediumLight: return 12
        case .medium: return 14
        case .mediumDark: return 15
        case .dark: return 16
        }
    }
}

enum Basket: String, CaseIterable, Identifiable {
    case single = "Single"
    case double = "Double"
    case singlePressurized = "Single, pressurized"
    case doublePressurized = "Double, pressurized"
    var id: String { rawValue }
    var label: String { rawValue }
}

enum Prep: String, CaseIterable, Identifiable {
    case wdt = "WDT"
    case distributor = "Distributor"
    case funnel = "Dosing funnel"
    case puckScreen = "Puck screen"
    case paperFilter = "Paper filter"
    var id: String { rawValue }
    var label: String { rawValue }
}

enum Drink: String, CaseIterable, Identifiable {
    case espresso = "Espresso"
    case double = "Double"
    case americano = "Americano"
    case latte = "Latte"
    case cappuccino = "Cappuccino"
    case flatWhite = "Flat white"
    case cortado = "Cortado"
    case icedLatte = "Iced latte"
    case other = "Other"
    var id: String { rawValue }
    var label: String { rawValue }
}

@Model
final class Shot {
    var date: Date = Date()
    var machine: String = defaultMachine
    var roaster: String = ""
    var bean: String = ""
    var roastRaw: String?
    var roastDate: Date?
    var grind: Double?
    var innerBurr: Double?
    var doseIn: Double?
    var groundOut: Double?
    var time: Double?
    var yieldOut: Double?
    var puckRaw: String?
    var tasteRaw: String?
    var drinkRaw: String?
    var basketRaw: String?
    var prep: [String] = []
    var notes: String = ""
    @Attribute(.externalStorage) var photo: Data?
    var thumb: Data?

    init() {}

    var basket: Basket? { basketRaw.flatMap(Basket.init(rawValue:)) }
    var prepItems: [Prep] { prep.compactMap(Prep.init(rawValue:)) }
    var daysOffRoast: Int? { roastDate.map { daysBetween($0, date) } }

    var puck: Puck? { puckRaw.flatMap(Puck.init(rawValue:)) }
    var taste: Taste? { tasteRaw.flatMap(Taste.init(rawValue:)) }
    var roast: Roast? { roastRaw.flatMap(Roast.init(rawValue:)) }
    var drink: Drink? { drinkRaw.flatMap(Drink.init(rawValue:)) }

    var ratio: Double? {
        guard let d = doseIn, let y = yieldOut, d > 0 else { return nil }
        return y / d
    }
    var retention: Double? {
        guard let d = doseIn, let g = groundOut else { return nil }
        return d - g
    }
    var beanKey: String { makeBeanKey(roaster, bean) }
    var beanName: String { makeBeanName(roaster, bean) }
}

/// Photo of a bag of beans, one per bean (keyed like `Shot.beanKey`).
@Model
final class BeanBag {
    var key: String = ""
    @Attribute(.externalStorage) var photo: Data?
    var thumb: Data?
    var updated: Date = Date()

    init(key: String) { self.key = key }
}

func daysBetween(_ from: Date, _ to: Date) -> Int {
    let cal = Calendar.current
    return cal.dateComponents([.day], from: cal.startOfDay(for: from), to: cal.startOfDay(for: to)).day ?? 0
}

func makeBeanKey(_ roaster: String, _ bean: String) -> String {
    roaster.trimmingCharacters(in: .whitespaces).lowercased() + "|" + bean.trimmingCharacters(in: .whitespaces).lowercased()
}

func makeBeanName(_ roaster: String, _ bean: String) -> String {
    let parts = [roaster, bean].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    return parts.isEmpty ? "Unnamed bean" : parts.joined(separator: " · ")
}

/// Editable copy of a shot used by the log form.
struct ShotDraft {
    var date = Date()
    var machine = defaultMachine
    var roaster = ""
    var bean = ""
    var roast: Roast?
    var hasRoastDate = false
    var roastDate = Date()
    var grind: Double?
    var innerBurr: Double?
    var doseIn: Double?
    var groundOut: Double?
    var time: Double?
    var yieldOut: Double?
    var puck: Puck?
    var taste: Taste?
    var drink: Drink?
    var basket: Basket?
    var prep: Set<Prep> = []
    var notes = ""
    var photo: Data?
    var thumb: Data?

    init() {}

    /// `full: false` copies only the settings (machine, bean, grind, dose, drink), for the next shot.
    init(from s: Shot, full: Bool) {
        machine = s.machine
        roaster = s.roaster
        bean = s.bean
        roast = s.roast
        if let rd = s.roastDate { hasRoastDate = true; roastDate = rd }
        grind = s.grind
        innerBurr = s.innerBurr
        doseIn = s.doseIn
        drink = s.drink
        basket = s.basket
        prep = Set(s.prepItems)
        if full {
            date = s.date
            groundOut = s.groundOut
            time = s.time
            yieldOut = s.yieldOut
            puck = s.puck
            taste = s.taste
            notes = s.notes
            photo = s.photo
            thumb = s.thumb
        }
    }

    func apply(to s: Shot) {
        s.date = date
        s.machine = machine.trimmingCharacters(in: .whitespaces).isEmpty ? defaultMachine : machine.trimmingCharacters(in: .whitespaces)
        s.roaster = roaster.trimmingCharacters(in: .whitespaces)
        s.bean = bean.trimmingCharacters(in: .whitespaces)
        s.roastRaw = roast?.rawValue
        s.roastDate = hasRoastDate ? roastDate : nil
        s.grind = grind
        s.innerBurr = innerBurr
        s.doseIn = doseIn
        s.groundOut = groundOut
        s.time = time
        s.yieldOut = yieldOut
        s.puckRaw = puck?.rawValue
        s.tasteRaw = taste?.rawValue
        s.drinkRaw = drink?.rawValue
        s.basketRaw = basket?.rawValue
        s.prep = Prep.allCases.filter { prep.contains($0) }.map(\.rawValue)
        s.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        s.photo = photo
        s.thumb = thumb
    }

    var ratio: Double? {
        guard let d = doseIn, let y = yieldOut, d > 0 else { return nil }
        return y / d
    }
    var beanKey: String { makeBeanKey(roaster, bean) }
    var hasBean: Bool {
        !roaster.trimmingCharacters(in: .whitespaces).isEmpty || !bean.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
