//  PopoverView.swift
//  A pure renderer, exactly as the extension's popup is: it reads the
//  coordinator and asks it to refresh. It never touches StatusEngine.

import SwiftUI

struct PopoverView: View {
    @Bindable var coordinator: MonitorCoordinator
    @Bindable var preferences: Preferences
    @Bindable var session: PopoverSession

    @State private var history: [ServiceID: [HistorySample]] = [:]
    @Environment(\.openURL) private var openURL

    private var motion: MotionLevel { Motion.effectiveLevel(preferences.motionLevel) }

    var body: some View {
        VStack(spacing: 0) {
            header
            countdownRail

            ScrollView {
                PopoverContentView(
                    coordinator: coordinator,
                    preferences: preferences,
                    history: history,
                    motion: motion
                )
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider().opacity(0.5)
            footer
        }
        .frame(width: 420)
        .frame(minHeight: 300, maxHeight: 620)
        // The exit animation. Scale from the top edge so it collapses back
        // toward the menu bar item it came from rather than shrinking to the
        // middle of nowhere.
        .scaleEffect(session.isDismissing ? 0.94 : 1, anchor: .top)
        .opacity(session.isDismissing ? 0 : 1)
        .blur(radius: session.isDismissing ? 6 : 0)
        .animation(
            motion == .off ? nil : .easeIn(duration: 0.26),
            value: session.isDismissing
        )
        // Any pointer inside the panel means the user is still reading.
        .onHover { inside in
            if inside { session.pause() } else { session.resume() }
        }
        .task {
            await coordinator.refreshIfStale()
            history = await coordinator.recentHistory()
        }
        .onChange(of: coordinator.snapshot?.updatedAt) { _, _ in
            Task { history = await coordinator.recentHistory() }
        }
    }

    /// A hairline that visibly depletes, so the auto-dismiss is something the
    /// user can see coming and interrupt — not a panel that vanishes mid-read.
    private var countdownRail: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(.separator.opacity(0.5))
                .frame(height: 1)

            if session.remaining != nil {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: session.isWarning
                                    ? [Color.status(.minor), Color.status(.major)]
                                    : [Color.vibe.opacity(0.7), Color.vibe],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * session.progress)
                        .animation(.linear(duration: 0.06), value: session.progress)
                }
                .frame(height: 2)
                .opacity(session.isPaused ? 0.25 : 1)
                .animation(.easeOut(duration: 0.15), value: session.isPaused)
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            HubMark(indicator: coordinator.combined.indicator, motion: motion)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: -1) {
                Text("VIBE STATS")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .kerning(0.6)
                Text(Bundle.main.shortVersion)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if session.remaining != nil || session.isPinned {
                Button {
                    withAnimation(Motion.animation(.transition, level: motion)) {
                        session.isPinned.toggle()
                    }
                } label: {
                    Image(systemName: session.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(session.isPinned ? Color.vibe : Color.secondary)
                        .rotationEffect(.degrees(session.isPinned ? 0 : 35))
                }
                .buttonStyle(.plain)
                .help(session.isPinned
                      ? String(localized: "Unpin — resume the auto-close countdown")
                      : String(localized: "Pin open — stop the auto-close countdown"))
                .accessibilityLabel(session.isPinned
                                    ? String(localized: "Unpin popover")
                                    : String(localized: "Pin popover open"))
            }

            Button {
                Task { await coordinator.refresh(reason: .manual) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .rotationEffect(.degrees(coordinator.isChecking ? 360 : 0))
                    .animation(
                        coordinator.isChecking && motion != .off
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: coordinator.isChecking
                    )
            }
            .buttonStyle(.plain)
            .disabled(coordinator.isChecking)
            .keyboardShortcut("r", modifiers: .command)
            .help(String(localized: "Refresh (⌘R)"))
            .accessibilityLabel(String(localized: "Refresh"))

            Menu {
                Button(String(localized: "Settings…")) { SettingsLauncher.open() }
                    .keyboardShortcut(",", modifiers: .command)
                Divider()
                // One dialog rather than three menu items: the repository and
                // the privacy policy live inside About, where people look.
                Button(String(localized: "About Vibe Stats")) {
                    AboutWindowController.shared.show()
                }
                Divider()
                Button(String(localized: "Quit Vibe Stats")) { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .help(String(localized: "More"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(String(localized: "Settings…")) { SettingsLauncher.open() }
                .buttonStyle(.link)
                .font(.system(size: 10))

            Spacer()

            if coordinator.combined.unresolvedCount > 0 {
                Label(
                    String(localized: "\(coordinator.combined.unresolvedCount) unresolved"),
                    systemImage: "questionmark.circle"
                )
                .font(.system(size: 10))
                .foregroundStyle(Color.status(.unknown))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}


/// The scrolling body: banner + card grid.
///
/// Extracted from PopoverView so it can be rendered offscreen for review —
/// ImageRenderer lays a ScrollView out to nothing, so anything inside one is
/// invisible in a snapshot.
struct PopoverContentView: View {
    let coordinator: MonitorCoordinator
    let preferences: Preferences
    let history: [ServiceID: [HistorySample]]
    let motion: MotionLevel

    var body: some View {
        VStack(spacing: 12) {
            banner
            grid
        }
        .padding(12)
    }

    // MARK: - Banner

    private var banner: some View {
        HStack(spacing: 10) {
            StatusDot(indicator: bannerIndicator, size: 10)
                .modifier(PulseModifier(active: bannerIndicator == .critical && motion != .off))

            VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.isOffline
                     ? String(localized: "Offline — will resume automatically")
                     : coordinator.combined.description)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subline)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.status(bannerIndicator).opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.status(bannerIndicator).opacity(0.3), lineWidth: 1)
        )
        .animation(Motion.animation(.transition, level: motion), value: bannerIndicator)
        .accessibilityElement(children: .combine)
    }

    private var bannerIndicator: StatusIndicator {
        coordinator.isOffline ? .unknown : coordinator.combined.indicator
    }

    private var subline: String {
        guard let snapshot = coordinator.snapshot else {
            return String(localized: "no data yet")
        }
        let services = snapshot.services.count
        let components = snapshot.services.reduce(0) { $0 + $1.componentsWatched }
        let updated = Format.relative(snapshot.updatedAt)
        return String(localized: "\(services) services · \(components) components · updated \(updated)")
    }

    // MARK: - Grid

    private var grid: some View {
        LazyVGrid(
            // `.top` matters: GridItem defaults to centring its cell
            // vertically, which leaves short cards floating in the middle of a
            // tall row instead of lining up with their neighbours.
            columns: [
                GridItem(.flexible(), spacing: 10, alignment: .top),
                GridItem(.flexible(), spacing: 10, alignment: .top)
            ],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(preferences.enabledServices) { definition in
                ServiceCardView(
                    definition: definition,
                    snapshot: coordinator.snapshot?[definition.id],
                    history: history[definition.id] ?? [],
                    motion: motion
                )
            }
        }
    }

}

/// The header mark: the same four-spoke hub as the menu bar glyph, with the
/// core coloured by the combined verdict.
struct HubMark: View {
    let indicator: StatusIndicator
    let motion: MotionLevel

    @State private var breathing = false

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let side = min(size.width, size.height)
            let centre = CGPoint(x: rect.midX, y: rect.midY)

            var spokes = Path()
            for index in 0..<4 {
                let node = VibeHubGeometry.node(index, in: rect)
                let vector = CGVector(dx: node.x - centre.x, dy: node.y - centre.y)
                let length = max(hypot(vector.dx, vector.dy), 0.0001)
                let unit = CGVector(dx: vector.dx / length, dy: vector.dy / length)
                let inner = (VibeHubGeometry.coreRadius + VibeHubGeometry.gap) * side
                let outer = (VibeHubGeometry.nodeRadius + VibeHubGeometry.gap) * side

                spokes.move(to: CGPoint(x: centre.x + unit.dx * inner, y: centre.y + unit.dy * inner))
                spokes.addLine(to: CGPoint(x: node.x - unit.dx * outer, y: node.y - unit.dy * outer))
            }
            context.stroke(
                spokes,
                with: .color(.vibe),
                style: StrokeStyle(lineWidth: VibeHubGeometry.spokeWidth * side, lineCap: .round)
            )

            for index in 0..<4 {
                let node = VibeHubGeometry.node(index, in: rect)
                let radius = VibeHubGeometry.nodeRadius * side
                context.fill(
                    Path(ellipseIn: CGRect(x: node.x - radius, y: node.y - radius,
                                           width: radius * 2, height: radius * 2)),
                    with: .color(.vibe)
                )
            }

            let coreRadius = VibeHubGeometry.coreRadius * side
            context.fill(
                Path(ellipseIn: CGRect(x: centre.x - coreRadius, y: centre.y - coreRadius,
                                       width: coreRadius * 2, height: coreRadius * 2)),
                with: .color(.status(indicator))
            )
        }
        .scaleEffect(breathing ? 1.04 : 1)
        .onAppear {
            guard motion == .full else { return }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// M2 — the critical pulse, applied to the banner dot.
private struct PulseModifier: ViewModifier {
    let active: Bool
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? 1.18 : 1)
            .opacity(pulsing ? 0.65 : 1)
            .onChange(of: active, initial: true) { _, isActive in
                pulsing = false
                guard isActive else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

extension Bundle {
    var shortVersion: String {
        "v" + ((object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev")
    }
}
