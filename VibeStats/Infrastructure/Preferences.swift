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
        static let notifyCooldownMinutes = "notifyCooldownMinutes"
        static let quietHoursEnabled = "quietHoursEnabled"
        static let quietHoursStart = "quietHoursStart"
        static let quietHoursEnd = "quietHoursEnd"
    }

    // MARK: - General

    var refreshInterval: RefreshInterval {
        get { RefreshInterval(rawValue: defaults.integer(forKey: Key.refreshInterval)) ?? .fiveMinutes }
        set { defaults.set(newValue.rawValue, forKey: Key.refreshInterval) }
    }

    var checkOnWake: Bool {
        get { defaults.bool(forKey: Key.checkOnWake) }
        set { defaults.set(newValue, forKey: Key.checkOnWake) }
    }

    var popoverAutoClose: PopoverAutoClose {
        get { PopoverAutoClose(rawValue: defaults.integer(forKey: Key.popoverAutoClose)) ?? .fifteenSeconds }
        set { defaults.set(newValue.rawValue, forKey: Key.popoverAutoClose) }
    }

    var showInDock: Bool {
        get { defaults.bool(forKey: Key.showInDock) }
        set {
            defaults.set(newValue, forKey: Key.showInDock)
            NSApp.setActivationPolicy(newValue ? .regular : .accessory)
        }
    }

    // MARK: - Services

    private var disabledServices: Set<ServiceID> {
        get {
            let raw = defaults.stringArray(forKey: Key.disabledServices) ?? []
            return Set(raw.compactMap(ServiceID.init(rawValue:)))
        }
        set {
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
        get { enumValue(Key.iconStyle) ?? .hub }
        set { defaults.set(newValue.rawValue, forKey: Key.iconStyle) }
    }

    var iconRenderMode: IconRenderMode {
        get { enumValue(Key.iconRenderMode) ?? .monochromeWithPip }
        set { defaults.set(newValue.rawValue, forKey: Key.iconRenderMode) }
    }

    var showBadgeCount: Bool {
        get { defaults.bool(forKey: Key.showBadgeCount) }
        set { defaults.set(newValue, forKey: Key.showBadgeCount) }
    }

    var menuBarTextMode: MenuBarTextMode {
        get { enumValue(Key.menuBarTextMode) ?? .none }
        set { defaults.set(newValue.rawValue, forKey: Key.menuBarTextMode) }
    }

    var motionLevel: MotionLevel {
        get { enumValue(Key.motionLevel) ?? .full }
        set { defaults.set(newValue.rawValue, forKey: Key.motionLevel) }
    }

    // MARK: - Notifications

    var notifyOnDegradation: Bool {
        get { defaults.bool(forKey: Key.notifyOnDegradation) }
        set { defaults.set(newValue, forKey: Key.notifyOnDegradation) }
    }

    var notifyOnRecovery: Bool {
        get { defaults.bool(forKey: Key.notifyOnRecovery) }
        set { defaults.set(newValue, forKey: Key.notifyOnRecovery) }
    }

    var notifyMinimumSeverity: NotificationSeverity {
        get { enumValue(Key.notifyMinimumSeverity) ?? .minor }
        set { defaults.set(newValue.rawValue, forKey: Key.notifyMinimumSeverity) }
    }

    var notifyPrimaryOnly: Bool {
        get { defaults.bool(forKey: Key.notifyPrimaryOnly) }
        set { defaults.set(newValue, forKey: Key.notifyPrimaryOnly) }
    }

    var notifySound: Bool {
        get { defaults.bool(forKey: Key.notifySound) }
        set { defaults.set(newValue, forKey: Key.notifySound) }
    }

    var notifyCooldown: Duration {
        get { .seconds(defaults.integer(forKey: Key.notifyCooldownMinutes) * 60) }
        set { defaults.set(Int(newValue.components.seconds / 60), forKey: Key.notifyCooldownMinutes) }
    }

    var quietHoursEnabled: Bool {
        get { defaults.bool(forKey: Key.quietHoursEnabled) }
        set { defaults.set(newValue, forKey: Key.quietHoursEnabled) }
    }

    /// Minutes past midnight, local time.
    var quietHoursStart: Int {
        get { defaults.integer(forKey: Key.quietHoursStart) }
        set { defaults.set(newValue, forKey: Key.quietHoursStart) }
    }

    var quietHoursEnd: Int {
        get { defaults.integer(forKey: Key.quietHoursEnd) }
        set { defaults.set(newValue, forKey: Key.quietHoursEnd) }
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
