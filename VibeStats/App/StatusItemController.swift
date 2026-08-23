//  StatusItemController.swift
//  The menu bar surface.
//
//  Left click toggles the popover; right- or control-click opens the menu.
//  Both come through one button action with NSApp.currentEvent inspected —
//  assigning `statusItem.menu` instead would steal the left click entirely,
//  which is the usual way this gets built wrong.

import AppKit

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let coordinator: MonitorCoordinator
    private let preferences: Preferences

    private var popoverController: PopoverController?
    private var currentState = IconState()
    private var phase: CGFloat = 0
    private var ticker: Timer?
    /// Frames for the handful of static states, so a steady app draws nothing.
    private var staticFrames: [IconState: NSImage] = [:]

    init(coordinator: MonitorCoordinator, preferences: Preferences) {
        self.coordinator = coordinator
        self.preferences = preferences
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }

    func install() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        render()
    }

    func render() {
        guard let button = statusItem.button else { return }

        let state = makeState()
        currentState = state

        button.image = frame(for: state)
        button.imagePosition = state.titleText == nil ? .imageOnly : .imageLeading
        button.title = state.titleText.map { " \($0)" } ?? ""
        button.toolTip = tooltip(state)
        button.setAccessibilityLabel(accessibilityLabel(state))

        retimeAnimation(for: state)
    }

    private func makeState() -> IconState {
        var services: [ServiceID: StatusIndicator] = [:]
        for service in coordinator.snapshot?.services ?? [] {
            services[service.id] = service.indicator
        }

        var state = IconState()
        state.indicator = coordinator.combined.indicator
        state.services = services
        state.affectedCount = coordinator.combined.affectedCount
        state.isOffline = coordinator.isOffline
        state.isChecking = coordinator.isChecking
        state.style = preferences.iconStyle
        state.renderMode = preferences.iconRenderMode
        state.showBadge = preferences.showBadgeCount
        state.motion = Motion.effectiveLevel(preferences.motionLevel)
        return state
    }

    /// Static states are cached; animated ones are drawn per frame.
    private func frame(for state: IconState) -> NSImage {
        guard state.animation == .none else {
            return VibeIconRenderer.image(for: state, phase: phase)
        }
        if let cached = staticFrames[state] { return cached }
        let image = VibeIconRenderer.image(for: state)
        staticFrames[state] = image
        return image
    }

    // MARK: - Animation

    private static let framesPerSecond: Double = 30

    private func retimeAnimation(for state: IconState) {
        guard state.animation != .none else {
            ticker?.invalidate()
            ticker = nil
            phase = 0
            return
        }
        guard ticker == nil else { return }

        let period = Double(state.animationPeriod.components.seconds)
            + Double(state.animationPeriod.components.attoseconds) / 1e18

        let timer = Timer(timeInterval: 1 / Self.framesPerSecond, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let button = self.statusItem.button else { return }
                // Never animate into a dark screen or a hidden app: the frames
                // would be drawn and thrown away.
                guard NSApp.occlusionState.contains(.visible) else { return }

                self.phase = (self.phase + CGFloat(1 / (Self.framesPerSecond * period)))
                    .truncatingRemainder(dividingBy: 1)
                button.image = VibeIconRenderer.image(for: self.currentState, phase: self.phase)
            }
        }
        // .common so the glyph keeps moving while a menu is tracking.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    // MARK: - Presentation

    private func tooltip(_ state: IconState) -> String {
        if state.isOffline {
            return String(localized: "Vibe Stats — Offline, will resume automatically")
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let suffix = state.affectedCount > 0
            ? String(localized: " (\(state.affectedCount) affected)") : ""
        return "Vibe Stats v\(version) — \(state.indicator.title)\(suffix)\n\(coordinator.combined.description)"
    }

    private func accessibilityLabel(_ state: IconState) -> String {
        if state.isOffline { return String(localized: "Vibe Stats, offline") }
        return state.affectedCount > 0
            ? String(localized: "Vibe Stats, \(state.indicator.title), \(state.affectedCount) affected")
            : String(localized: "Vibe Stats, \(state.indicator.title)")
    }

    // MARK: - Interaction

    @objc private func handleClick() {
        let isSecondary = NSApp.currentEvent.map { event in
            event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        } ?? false

        if isSecondary {
            showMenu()
        } else {
            togglePopover()
        }
    }

    /// Built lazily: constructing the SwiftUI hosting controller at launch
    /// would put the whole view tree on the cold-start path for a window the
    /// user may never open.
    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popoverController == nil {
            popoverController = PopoverController(coordinator: coordinator, preferences: preferences)
        }
        popoverController?.toggle(relativeTo: button)
    }

    func closePopover() {
        popoverController?.close()
    }

    /// Opens the popover programmatically — used when a notification is
    /// activated, where there is no click to respond to.
    func revealPopover() {
        guard let button = statusItem.button else { return }
        if popoverController == nil {
            popoverController = PopoverController(coordinator: coordinator, preferences: preferences)
        }
        guard popoverController?.isShown != true else { return }
        popoverController?.show(relativeTo: button)
    }

    #if DEBUG
    /// Opens the popover without a click, so it can be screenshotted and
    /// reviewed during development. Set VIBESTATS_OPEN_POPOVER=1.
    func openPopoverForDebug() {
        guard let button = statusItem.button else { return }
        if popoverController == nil {
            popoverController = PopoverController(coordinator: coordinator, preferences: preferences)
        }
        popoverController?.pinOpenForDebug()
        popoverController?.show(relativeTo: button)
    }
    #endif

    private func showMenu() {
        let menu = NSMenu()

        let refresh = NSMenuItem(title: String(localized: "Refresh Now"),
                                 action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = !coordinator.isChecking
        menu.addItem(refresh)

        menu.addItem(.separator())

        for service in ServiceRegistry.all where preferences.isEnabled(service.id) {
            let snapshot = coordinator.snapshot?[service.id]
            let state = snapshot?.indicator.title ?? String(localized: "Unknown")
            let item = NSMenuItem(title: "\(service.name) — \(state)",
                                  action: #selector(openStatusPage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = service.statusURL
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: String(localized: "Settings…"),
                                  action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let about = NSMenuItem(title: String(localized: "About Vibe Stats"),
                               action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit Vibe Stats"),
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Attaching the menu only for this click keeps the left click ours.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshNow() {
        Task { await coordinator.refresh(reason: .manual) }
    }

    @objc private func openStatusPage(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openSettings() {
        SettingsLauncher.open()
    }

    @objc private func openAbout() {
        AboutWindowController.shared.show()
    }
}
