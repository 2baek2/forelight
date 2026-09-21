import Foundation
import Testing
@testable import Forelight

struct RuleEvaluatorTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-09-21 is a Monday (weekday 2).
    private func date(day: Int = 21, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private func context(
        bundleID: String? = "com.apple.Safari",
        date: Date? = nil,
        onBattery: Bool? = true,
        externalDisplay: Bool = false,
        idleSeconds: TimeInterval = 0,
        microphoneInUse: Bool = false
    ) -> RuleContext {
        RuleContext(
            frontmostBundleID: bundleID,
            date: date ?? self.date(hour: 10),
            onBattery: onBattery,
            externalDisplayConnected: externalDisplay,
            idleSeconds: idleSeconds,
            microphoneInUse: microphoneInUse,
            calendar: calendar
        )
    }

    @Test func ruleWithNoConditionsAlwaysMatches() {
        let rule = Rule(name: "Always")
        #expect(RuleEvaluator.matches(rule, context: context()))
    }

    @Test func disabledRuleNeverMatches() {
        var rule = Rule(name: "Off")
        rule.isEnabled = false
        #expect(!RuleEvaluator.matches(rule, context: context()))
    }

    @Test func frontmostAppFilter() {
        var rule = Rule(name: "In Xcode")
        rule.frontmostApps = ["com.apple.dt.Xcode"]
        #expect(RuleEvaluator.matches(rule, context: context(bundleID: "com.apple.dt.Xcode")))
        #expect(!RuleEvaluator.matches(rule, context: context(bundleID: "com.apple.Safari")))
        #expect(!RuleEvaluator.matches(rule, context: context(bundleID: nil)))
    }

    @Test func emptyAppListIsIgnored() {
        var rule = Rule(name: "Empty")
        rule.frontmostApps = []
        #expect(RuleEvaluator.matches(rule, context: context(bundleID: nil)))
    }

    @Test func powerSourceFilter() {
        var rule = Rule(name: "On battery")
        rule.powerSource = .battery
        #expect(RuleEvaluator.matches(rule, context: context(onBattery: true)))
        #expect(!RuleEvaluator.matches(rule, context: context(onBattery: false)))
        #expect(!RuleEvaluator.matches(rule, context: context(onBattery: nil)))
    }

    @Test func externalDisplayFilter() {
        var rule = Rule(name: "Docked")
        rule.externalDisplay = true
        #expect(RuleEvaluator.matches(rule, context: context(externalDisplay: true)))
        #expect(!RuleEvaluator.matches(rule, context: context(externalDisplay: false)))
    }

    @Test func idleFilter() {
        var rule = Rule(name: "Idle")
        rule.idleMinutes = 5
        #expect(RuleEvaluator.matches(rule, context: context(idleSeconds: 600)))
        #expect(!RuleEvaluator.matches(rule, context: context(idleSeconds: 60)))
    }

    @Test func microphoneFilter() {
        var rule = Rule(name: "Meeting")
        rule.microphoneInUse = true
        #expect(RuleEvaluator.matches(rule, context: context(microphoneInUse: true)))
        #expect(!RuleEvaluator.matches(rule, context: context(microphoneInUse: false)))
    }

    @Test func timeWindowDayAndTime() {
        let window = TimeWindow(days: [2], startMinutes: 9 * 60, endMinutes: 18 * 60)
        #expect(RuleEvaluator.isWithin(window, date: date(day: 21, hour: 10), calendar: calendar))
        #expect(!RuleEvaluator.isWithin(window, date: date(day: 21, hour: 20), calendar: calendar))
        // Tuesday is weekday 3.
        #expect(!RuleEvaluator.isWithin(window, date: date(day: 22, hour: 10), calendar: calendar))
    }

    @Test func overnightTimeWindow() {
        let window = TimeWindow(days: [2], startMinutes: 22 * 60, endMinutes: 6 * 60)
        #expect(RuleEvaluator.isWithin(window, date: date(day: 21, hour: 23), calendar: calendar))
        #expect(RuleEvaluator.isWithin(window, date: date(day: 21, hour: 3), calendar: calendar))
        #expect(!RuleEvaluator.isWithin(window, date: date(day: 21, hour: 12), calendar: calendar))
    }

    @Test func lastMatchingEnabledRuleWins() {
        var first = Rule(name: "First")
        first.frontmostApps = ["com.apple.Safari"]

        var second = Rule(name: "Second")
        second.frontmostApps = ["com.apple.Safari"]
        second.powerSource = .battery

        var disabled = Rule(name: "Disabled")
        disabled.isEnabled = false
        disabled.frontmostApps = ["com.apple.Safari"]

        let rules = [first, second, disabled]
        let matched = RuleEvaluator.matchedRule(in: rules, context: context(bundleID: "com.apple.Safari", onBattery: true))
        #expect(matched?.name == "Second")

        let safariOnPower = RuleEvaluator.matchedRule(in: rules, context: context(bundleID: "com.apple.Safari", onBattery: false))
        #expect(safariOnPower?.name == "First")

        let noMatch = RuleEvaluator.matchedRule(in: rules, context: context(bundleID: "com.apple.Notes"))
        #expect(noMatch == nil)
    }
}
