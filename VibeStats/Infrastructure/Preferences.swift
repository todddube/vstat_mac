//  Preferences.swift
//  Every user-facing setting, backed by UserDefaults. Phase 6 builds the UI;
//  the model lives here so the coordinator can read it from day one.

import AppKit
import Foundation
import Observation

enum RefreshInterval: Int, CaseIterable, Identifiable, Sendable, Codable {
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    var id: Int { rawValue }
    var duration: Duration { .seconds(rawValue) }

    /// 10% leeway lets the system coalesce our wake-ups with others. On a
    /// laptop that is the difference between a timer and a battery complaint.
    var tolerance: Duration { .seconds(max(5, rawValue / 10)) }

    var title: String {
        Duration.seconds(rawValue).formatted(
            .units(allowed: [.minutes], width: .wide)
        )
    }
}

/// How long the popover stays open with no interaction. `.never` pins it open
/// until the user dismisses it.
enum PopoverAutoClose: Int, CaseIterable, Identifiable, Sendable, Codable {
    case never = 0
    case fiveSeconds = 5
    case tenSeconds = 10
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case oneMinute = 60

    var id: Int { rawValue }
    var isEnabled: Bool { self != .never }
    var interval: TimeInterval { TimeInterval(rawValue) }

    var title: String {
        guard isEnabled else { return String(localized: "Stay open") }
        return Duration.seconds(rawValue).formatted(.units(allowed: [.seconds, .minutes], width: .wide))
    }
}

enum MenuBarIconStyle: String, CaseIterable, Identifiable, Sendable, Codable {
    case hub, pulse, minimal
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hub:     return String(localized: "Hub")
        case .pulse:   return String(localized: "Pulse")
        case .minimal: return String(localized: "Minimal")
        }
    }

    /// What the shape actually says, so the choice is not three bare nouns.
    var subtitle: String {
        switch self {
        case .hub:     return String(localized: "One node per service")
        case .pulse:   return String(localized: "A trace that deflects with severity")
        case .minimal: return String(localized: "A single dot; a ring when degraded")
        }
    }
}

enum IconRenderMode: String, CaseIterable, Identifiable, Sendable, Codable {
    /// Template glyph tinted by the system, with a coloured status pip. The
    /// native-looking default, and the only rendering guaranteed legible
    /// against a transparent menu bar over an arbitrary wallpaper.
    case monochromeWithPip
    /// Fully coloured glyph: louder, more informative, less native.
    case colour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monochromeWithPip: return String(localized: "Monochrome with status dot")
        case .colour:            return String(localized: "Full colour")
        }
    }
}

enum MotionLevel: String, CaseIterable, Identifiable, Sendable, Codable {
    case full, subtle, off
    var id: String { rawValue }

    var title: String {
        switch self {
        case .full:   return String(localized: "Full")
        case .subtle: return String(localized: "Subtle")
        case .off:    return String(localized: "Off")
        }
    }
}

enum MenuBarTextMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case none, shortLabel, affectedCount
    var id: String { rawValue }
}

/// The sound a notification carries. Cases map to the alert sounds in
/// `/System/Library/Sounds`; `.default` defers to whatever the system alert
/// sound is set to, which is the behaviour this app shipped with.
enum AlertSound: String, CaseIterable, Identifiable, Sendable, Codable {
    case `default`
    case basso, blow, bottle, frog, funk, glass, hero, morse, ping, pop, purr, sosumi, submarine, tink

    var id: String { rawValue }

    /// The file name in `/System/Library/Sounds`, or nil for the system default.
    /// `UNNotificationSound(named:)` and `NSSound(named:)` both take this name.
    var systemName: String? {
        guard self != .default else { return nil }
        return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    var title: String {
        guard let systemName else { return String(localized: "System default") }
        return systemName
    }
}

enum NotificationSeverity: String, CaseIterable, Identifiable, Sendable, Codable {
    case minor, major, critical
    var id: String { rawValue }

    var threshold: StatusIndicator {
        switch self {
        case .minor:    return .minor
        case .major:    return .major
        case .critical: return .critical
        }
    }
}

@MainActor @Observable
final class Preferences {
    static let shared = Preferences()

    private let defaults: UserDefaults

    /// The `@Observable` macro only instruments STORED properties, and every
    /// setting here is computed over UserDefaults — so without this, a write
    /// reached disk but no view or `onChange` ever heard of it, and the menu
    /// bar glyph kept its old style until the next status check. Every getter
    /// reads it and every setter bumps it: coarse, but each `onChange` still
    /// compares its own value, so only the right handlers fire.
    private var revision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Self.registrationDefaults)
    }

    private static let registrationDefaults: [String: Any] = [
        Key.refreshInterval: RefreshInterval.fiveMinutes.rawValue,
        Key.checkOnWake: true,
        Key.popoverAutoClose: PopoverAutoClose.fifteenSeconds.rawValue,
        Key.showInDock: false,
        Key.disabledServices: [String](),
        Key.iconStyle: MenuBarIconStyle.hub.rawValue,
        Key.iconRenderMode: IconRenderMode.monochromeWithPip.rawValue,
        Key.showBadgeCount: true,
        Key.menuBarTextMode: MenuBarTextMode.none.rawValue,
        Key.motionLevel: MotionLevel.full.rawValue,
        Key.notifyOnDegradation: true,
        Key.notifyOnRecovery: true,
        Key.notifyMinimumSeverity: NotificationSeverity.minor.rawValue,
        Key.notifyPrimaryOnly: true,
        Key.notifySound: false,
        Key.notifyAlertSound: AlertSound.default.rawValue,
        Key.launchSound: true,
        Key.notifyCooldownMinutes: 15,
        Key.quietHoursEnabled: false,
        Key.quietHoursStart: 22 * 60,
        Key.quietHoursEnd: 8 * 60
    ]

    enum Key {
        static let refreshInterval = "refreshInterval"
        static let checkOnWake = "checkOnWake"
        static let popoverAutoClose = "popoverAutoClose"
        static let showInDock = "showInDock"
        static let disabledServices = "disabledServices"
        static let iconStyle = "iconStyle"
        static let iconRenderMode = "iconRenderMode"
        static let showBadgeCount = "showBadgeCount"
        static let menuBarTextMode = "menuBarTextMode"
        static let motionLevel = "motionLevel"
        static let notifyOnDegradation = "notifyOnDegradation"
        static let notifyOnRecovery = "notifyOnRecovery"
        static let notifyMinimumSeverity = "notifyMinimumSeverity"
        static let notifyPrimaryOnly = "notifyPrimaryOnly"
        static let notifySound = "notifySound"
        static let notifyAlertSound = "notifyAlertSound"
        static let launchSound = "launchSound"
        static let notifyCooldownMinutes = "notifyCooldownMinutes"
        static let quietHoursEnabled = "quietHoursEnabled"
        static let quietHoursStart = "quietHoursStart"
        static let quietHoursEnd = "quietHoursEnd"
    }

    // MARK: - General

    var refreshInterval: RefreshInterval {
        get { _ = revision; return RefreshInterval(rawValue: defaults.integer(forKey: Key.refreshInterval)) ?? .fiveMinutes }
        set { defer { revision &+= 1 }; defaults.set(newValue.rawValue, forKey: Key.refreshInterval) }
    }

    var checkOnWake: Bool {
        get { _ = revision; return defaults.bool(forKey: Key.checkOnWake) }
        set { defer { revision &+= 1 }; defaults.set(newValue, forKey: Key.checkOnWake) }
    }

    var popoverAutoClose: PopoverAutoClose {
        get { _ = revision; return PopoverAutoClose(rawValue: defaults.integer(forKey: Key.popoverAutoClose)) ?? .fifteenSeconds }
        set { defer { revision &+= 1 }; defaults.set(newValue.rawValue, forKey: Key.popoverAutoClose) }
    }

    var showInDock: Bool {
        get { _ = revision; return defaults.bool(forKey: Key.showInDock) }
        set {
            defer { revision &+= 1 }
            defaults.set(newValue, forKey: Key.showInDock)
            NSApp.setActivationPolicy(newValue ? .regular : .accessory)
        }
    }

    // MARK: - Services

    private var disabledServices: Set<ServiceID> {
        get {
            _ = revision
            let raw = defaults.stringArray(forKey: Key.disabledServices) ?? []
            return Set(raw.compactMap(ServiceID.init(rawValue:)))
        }
        set {
            defer { revision &+= 1 }
            defaults.set(newValue.map(\.rawValue).sorted(), forKey: Key.disabledServices)
        }
    }

    func isEnabled(_ service: ServiceID) -> Bool {
        !disabledServices.contains(service)
    }

    func setEnabled(_ enabled: Bool, for service: ServiceID) {
        var disabled = disabledServices
        if enabled { disabled.remove(service) } else { disabled.insert(service) }
        disabledServices = disabled
    }

    /// A disabled service is not fetched and does not feed the roll-up.
    var enabledServices: [ServiceDefinition] {
        ServiceRegistry.all.filter { isEnabled($0.id) }
    }

    // MARK: - Appearance

    var iconStyle: MenuBarIconStyle {
        get { _ = revision; return enumValue(Key.iconStyle) ?? .hub }
        set { defer { revision &+= 1 }; defaults.set(newValue.rawValue, forKey: Key.iconStyle) }
    }

    var iconRenderMode: IconRenderMode {
        get { _ = revision; return enumValue(Key.iconRenderMode) ?? .monochromeWithPip }
        set { defer { revision &+= 1 }; defaults.set(newValue.rawValue, forKey: Key.iconRenderMode) }
    }

    var showBadgeCount: Bool {
        get { _ = revision; return defaults.bool(forKey: Key.showBadgeCount) }
        set { defer { revision &+= 1 }; defaults.set(newValue, forKey: Key.showBadgeCount) }
    }

    var menuBarTextMode: MenuBarTextMode {
        get { _ = revision; return enumValue(Key.menuBarTextMode) ?? .none }
        set { defer { revision &+= 1 }; defaults.set(newValue.rawValue, forKey: Key.menuBarTextMode) }
    }

    var motionLevel: MotionLevel {
        get { _ = revision; return enumValue(Key.motionLevel) ?? .full }
        set { defer { revision &+= 1 }; defaults.set(newValue.rawValue, forKey: Key.motionLevel) }
    }

    // MARK: - Notifications

    var notifyOnDegradation: Bool {
        get { _ = revision; return defaults.bool(forKey: Key.notifyOnDegradation) }
        set { defer { revision &+= 1 }; defaults.set(newValue, forKey: Key.notifyOnDegradation) }
    }

    var notifyOnRecovery: Bool {
        get { _ = revision; return defaults.bool(forKey: Key.notifyOnRecovery) }
        set { defer { revision &+= 1 }; defaults.set(newValue, forKey: Key.notifyOnRecovery) }
    }

    var notifyMinimumSeverity: NotificationSeverity {
        get { _ = revision; return enumValue(Key.notifyMinimumSeverity) ?? .minor }
        set { defer { revision &+= 1 }; defaults.set(newValue.rawValue, forKey: Key.notifyMinimumSeverity) }
    }

    var notifyPrimaryOnly: Bool {
        get { _ = revision; return defaults.bool(forKey: Key.notifyPrimaryOnly) }
        set { defer { revision &+= 1 }; defaults.set(newValue, forKey: Key.notifyPrimaryOnly) }
    }

    var notifySound: Bool {
        get { _ = revision; return defaults.bool(forKey: Key.notifySound) }
        set { defer { revision &+= 1 }; defaults.set(newValue, forKey: Key.notifySound) }
    }

    /// Which sound. Only consulted when `notifySound` is on.
    var notifyAlertSound: AlertSound {
        get { _ = revision; return enumValue(Key.notifyAlertSound) ?? .default }
        set { defer { revision &+= 1 }; defaults.set(newValue.rawValue, forKey: Key.notifyAlertSound) }
    }

    /// What a notification should actually play: nil when sound is switched off.
    var alertSound: AlertSound? {
        notifySound ? notifyAlertSound : nil
    }

    /// A menu bar app starts with no window and no Dock bounce, so without this
    /// there is nothing at all to say it came up.
    var launchSound: Bool {
        get { _ = revision; return defaults.bool(forKey: Key.launchSound) }
        set { defer { revision &+= 1 }; defaults.set(newValue, forKey: Key.launchSound) }
    }

    /// The sound to play at launch, or nil to stay silent. Quiet hours win: a
    /// chime whose whole purpose is to call attention is the last thing wanted
    /// at 3am, and login items launch at exactly the hour you booted.
    func launchChime(at date: Date = .now) -> AlertSound? {
        guard launchSound else { return nil }
        guard !quietHoursEnabled || !isQuietHour(date) else { return nil }
        return notifyAlertSound
    }

    var notifyCooldown: Duration {
        get { _ = revision; return .seconds(defaults.integer(forKey: Key.notifyCooldownMinutes) * 60) }
        set { defer { revision &+= 1 }; defaults.set(Int(newValue.components.seconds / 60), forKey: Key.notifyCooldownMinutes) }
    }

    var quietHoursEnabled: Bool {
        get { _ = revision; return defaults.bool(forKey: Key.quietHoursEnabled) }
        set { defer { revision &+= 1 }; defaults.set(newValue, forKey: Key.quietHoursEnabled) }
    }

    /// Minutes past midnight, local time.
    var quietHoursStart: Int {
        get { _ = revision; return defaults.integer(forKey: Key.quietHoursStart) }
        set { defer { revision &+= 1 }; defaults.set(newValue, forKey: Key.quietHoursStart) }
    }

    var quietHoursEnd: Int {
        get { _ = revision; return defaults.integer(forKey: Key.quietHoursEnd) }
        set { defer { revision &+= 1 }; defaults.set(newValue, forKey: Key.quietHoursEnd) }
    }

    /// Handles a window that wraps past midnight (22:00 → 08:00).
    func isQuietHour(_ date: Date) -> Bool {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if quietHoursStart == quietHoursEnd { return false }
        return quietHoursStart < quietHoursEnd
            ? (minutes >= quietHoursStart && minutes < quietHoursEnd)
            : (minutes >= quietHoursStart || minutes < quietHoursEnd)
    }

    // MARK: -

    private func enumValue<T: RawRepresentable>(_ key: String) -> T? where T.RawValue == String {
        // Written out rather than `.flatMap(T.init(rawValue:))`: passing the
        // initialiser as a function value crosses an isolation boundary the
        // compiler cannot prove is safe.
        guard let raw = defaults.string(forKey: key) else { return nil }
        return T(rawValue: raw)
    }
}
