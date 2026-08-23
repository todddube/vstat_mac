//  AboutWindowController.swift
//  One About dialog carrying everything the popover's "…" menu used to spread
//  across several items: version, what is watched, the repository, and the
//  privacy position.

import AppKit
import SwiftUI

@MainActor
final class AboutWindowController {
    static let shared = AboutWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "About Vibe Stats")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 380, height: 430))
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.window = window
    }
}

enum AppLinks {
    static let repository = URL(string: "https://github.com/todddube/vstat_mac")!
    static let extensionRepository = URL(string: "https://github.com/todddube/vstat")!
    static let privacy = URL(string: "https://todddube.github.io/vstat/")!
    static let author = URL(string: "https://github.com/todddube")!
}

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HubMark(indicator: .operational, motion: .off)
                    .frame(width: 64, height: 64)

                Text("Vibe Stats")
                    .font(.system(size: 20, weight: .bold, design: .rounded))

                Text(version)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 18)

            Text("Component-accurate status for the AI tools you code with.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.bottom, 16)

            HStack(spacing: 14) {
                ForEach(ServiceRegistry.all) { service in
                    VStack(spacing: 5) {
                        Text(String(service.name.prefix(1)))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.accent(service.id))
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.accent(service.id).opacity(0.16))
                            )
                        Text(service.vendor.uppercased())
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.25))

            VStack(spacing: 0) {
                link("Project on GitHub", "chevron.left.forwardslash.chevron.right", AppLinks.repository)
                Divider().opacity(0.4)
                link("Browser extension", "puzzlepiece.extension", AppLinks.extensionRepository)
                Divider().opacity(0.4)
                link("Privacy policy", "hand.raised", AppLinks.privacy)
            }
            .padding(.vertical, 4)

            Divider().opacity(0.4)

            HStack(spacing: 4) {
                Text("Created by")
                    .foregroundStyle(.tertiary)
                Button("Todd Dube") { openURL(AppLinks.author) }
                    .buttonStyle(.link)
            }
            .font(.system(size: 11))
            .padding(.vertical, 12)
        }
        .frame(width: 380)
        .background(Color.surfaceRaised)
    }

    private func link(_ title: LocalizedStringKey, _ symbol: String, _ url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.vibe)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12))
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
