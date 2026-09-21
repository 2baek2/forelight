import Foundation

enum PowerSource: String, Codable, CaseIterable, Identifiable {
    case battery
    case adapter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .battery: return "Battery"
        case .adapter: return "Power adapter"
        }
    }
}

struct TimeWindow: Codable, Equatable {
    /// 1 = Sunday ... 7 = Saturday, matching Calendar's weekday component.
    var days: [Int]
    var startMinutes: Int
    var endMinutes: Int

    static let weekdayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var summary: String {
        let dayText = days.count == 7 ? "Every day" : days.sorted().map { Self.weekdayLabels[$0 - 1] }.joined(separator: " ")
        return "\(dayText) \(Self.timeText(startMinutes))–\(Self.timeText(endMinutes))"
    }

    static func timeText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }
}

enum RuleActionKind: String, CaseIterable, Identifiable {
    case enable
    case disable
    case intensity
    case group
    case snooze
    case spotlight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .enable: return "Turn dimming on"
        case .disable: return "Turn dimming off"
        case .intensity: return "Set intensity"
        case .group: return "Apply group"
        case .snooze: return "Snooze"
        case .spotlight: return "Set spotlight"
        }
    }
}

enum RuleAction: Codable, Equatable {
    case enable
    case disable
    case intensity(Double)
    case group(String)
    case snooze(minutes: Int)
    case spotlight(SpotlightMode)

    var kind: RuleActionKind {
        switch self {
        case .enable: return .enable
        case .disable: return .disable
        case .intensity: return .intensity
        case .group: return .group
        case .snooze: return .snooze
        case .spotlight: return .spotlight
        }
    }

    var summary: String {
        switch self {
        case .enable: return "Turn dimming on"
        case .disable: return "Turn dimming off"
        case .intensity(let value): return "Set intensity to \(Int((value * 100).rounded()))%"
        case .group(let name): return "Apply group “\(name)”"
        case .snooze(let minutes): return "Snooze for \(minutes) min"
        case .spotlight(let mode): return "Spotlight: \(mode.label)"
        }
    }
}

struct Rule: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var isEnabled: Bool

    // Conditions. nil means "don't care".
    var frontmostApps: [String]?
    var timeWindow: TimeWindow?
    var powerSource: PowerSource?
    var externalDisplay: Bool?
    var idleMinutes: Int?
    var microphoneInUse: Bool?

    var action: RuleAction

    init(id: UUID = UUID(), name: String, isEnabled: Bool = true, action: RuleAction = .enable) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.action = action
    }

    var conditionSummary: String {
        var parts: [String] = []
        if let apps = frontmostApps, !apps.isEmpty {
            parts.append("frontmost app (\(apps.count))")
        }
        if let timeWindow {
            parts.append(timeWindow.summary)
        }
        if let powerSource {
            parts.append(powerSource.label)
        }
        if let externalDisplay {
            parts.append(externalDisplay ? "external display" : "no external display")
        }
        if let idleMinutes {
            parts.append("idle ≥ \(idleMinutes) min")
        }
        if let microphoneInUse {
            parts.append(microphoneInUse ? "microphone in use" : "microphone idle")
        }
        return parts.isEmpty ? "Always" : parts.joined(separator: " · ")
    }
}

struct RuleContext {
    var frontmostBundleID: String?
    var date: Date
    var onBattery: Bool?
    var externalDisplayConnected: Bool
    var idleSeconds: TimeInterval
    var microphoneInUse: Bool
    var calendar: Calendar = .current
}

enum RuleEvaluator {
    static func matches(_ rule: Rule, context: RuleContext) -> Bool {
        guard rule.isEnabled else { return false }

        if let apps = rule.frontmostApps, !apps.isEmpty {
            guard let bundleID = context.frontmostBundleID, apps.contains(bundleID) else { return false }
        }

        if let timeWindow = rule.timeWindow {
            guard isWithin(timeWindow, date: context.date, calendar: context.calendar) else { return false }
        }

        if let powerSource = rule.powerSource {
            guard let onBattery = context.onBattery else { return false }
            if (powerSource == .battery) != onBattery { return false }
        }

        if let externalDisplay = rule.externalDisplay {
            guard context.externalDisplayConnected == externalDisplay else { return false }
        }

        if let idleMinutes = rule.idleMinutes {
            guard context.idleSeconds >= TimeInterval(idleMinutes * 60) else { return false }
        }

        if let microphoneInUse = rule.microphoneInUse {
            guard context.microphoneInUse == microphoneInUse else { return false }
        }

        return true
    }

    /// The last matching enabled rule wins, so more specific rules go lower.
    static func matchedRule(in rules: [Rule], context: RuleContext) -> Rule? {
        rules.last { matches($0, context: context) }
    }

    static func isWithin(_ window: TimeWindow, date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        guard window.days.contains(weekday) else { return false }

        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        if window.startMinutes <= window.endMinutes {
            return minutes >= window.startMinutes && minutes < window.endMinutes
        }
        // Overnight window, for example 22:00–06:00.
        return minutes >= window.startMinutes || minutes < window.endMinutes
    }
}
