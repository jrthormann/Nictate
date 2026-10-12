// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import AppKit
import SwiftUI

/// Polls Screen Recording status so the welcome window reacts as soon as the user grants it, and notes
/// when the user comes back from System Settings.
@MainActor
final class PermissionMonitor: ObservableObject {
    @Published private(set) var granted = Permissions.isGranted
    @Published private(set) var returnedFromSettings = false
    // Both are touched only on the main actor and in deinit, which runs after the last reference is gone.
    nonisolated(unsafe) private var timer: Timer?
    private var openedSettings = false
    nonisolated(unsafe) private var activation: (any NSObjectProtocol)?

    init() {
        activation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.appBecameActive() }
        }
        guard !granted else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func settingsOpened() { openedSettings = true }

    private func appBecameActive() {
        if openedSettings { returnedFromSettings = true }
        refresh()
    }

    private func refresh() {
        granted = Permissions.isGranted
        if granted {
            timer?.invalidate()
            timer = nil
        }
    }

    deinit {
        timer?.invalidate()
        if let activation { NotificationCenter.default.removeObserver(activation) }
    }
}

struct WelcomeView: View {
    @StateObject private var monitor = PermissionMonitor()
    @ObservedObject private var settings = Settings.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let onDone: () -> Void

    private var look: AccessibilityLook {
        AccessibilityLook(reduceTransparency: reduceTransparency, increaseContrast: colorSchemeContrast == .increased)
    }

    private var captureShortcut: String { settings.shortcutLabel(for: .capture) ?? "" }

    var body: some View {
        VStack(spacing: Design.Space.page) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: Design.Size.welcomeIcon, height: Design.Size.welcomeIcon)
                .accessibilityHidden(true)

            VStack(spacing: Design.Space.compact) {
                Text("Welcome to Nictate").font(.title2.weight(.semibold))
                Text("Copy text from anywhere on your screen. Everything is recognized on your Mac, offline.")
                    .foregroundStyle(Design.Ink.text(look.contrast))
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: Design.Space.page) {
                screenRecordingStep
                step(symbol: "keyboard", tint: .accentColor,
                     title: "Press \(captureShortcut), then drag to select an area.",
                     detail: "You can change the shortcut in Settings.")
                step(symbol: "doc.on.clipboard", tint: .accentColor,
                     title: "Paste the text anywhere.",
                     detail: "The recognized text is already on your clipboard.")
            }

            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Design.Space.window)
        .frame(width: Design.Size.welcomeWidth)
    }

    /// The warning glyph keeps its colour while the permission is not confirmed, whatever the user's accent.
    @ViewBuilder private var screenRecordingStep: some View {
        switch ScreenRecordingStep.state(granted: monitor.granted, returnedFromSettings: monitor.returnedFromSettings) {
        case .pending:
            step(symbol: "exclamationmark.circle.fill", tint: ColorTokens.warningIcon,
                 title: "Allow screen recording",
                 detail: "Turn it on for Nictate in System Settings.") {
                Button("Open System Settings") {
                    monitor.settingsOpened()
                    Permissions.openSettings()
                }
            }
        case .notActiveYet:
            step(symbol: "exclamationmark.circle.fill", tint: ColorTokens.warningIcon,
                 title: "Allow screen recording",
                 detail: "Nictate can't see Screen Recording yet. If you turned it on, restart Nictate to apply it.") {
                HStack {
                    Button("Restart Nictate") { AppRestart.now() }
                        .buttonStyle(.borderedProminent)
                    Button("Open System Settings") {
                        monitor.settingsOpened()
                        Permissions.openSettings()
                    }
                }
            }
        case .granted:
            step(symbol: "record.circle.fill", tint: .accentColor,
                 title: "Allow screen recording", detail: nil)
        }
    }

    private func step<Trailing: View>(symbol: String, tint: Color, title: LocalizedStringKey,
                                      detail: LocalizedStringKey?,
                                      @ViewBuilder trailing: () -> Trailing = { EmptyView() }) -> some View {
        HStack(alignment: .top, spacing: Design.Space.cardGap) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: Design.Size.stepIcon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Design.Space.tight) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail).foregroundStyle(Design.Ink.text(look.contrast)).fixedSize(horizontal: false, vertical: true)
                }
                trailing().padding(.top, Design.Space.tight)
            }
        }
    }
}
