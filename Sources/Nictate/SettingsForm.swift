// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.
import AppKit
import SwiftUI

/// One settings tab: a native grouped `Form`, the System Settings idiom. Its sections, switches and pickers are
/// the system's own controls, so they take the user's accent, text sizes and appearance without extra styling.
struct SettingsPage<Content: View>: View {
    private let content: Content
    /// The tallest a tab may be: 80 % of the visible screen. Taller tabs scroll inside the form.
    private let maxHeight: CGFloat

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
        let visible = (NSScreen.main?.visibleFrame.height ?? 800)
        maxHeight = visible * Design.Size.settingsMaxHeightShare
    }

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .frame(width: Design.Size.settingsWidth)
            .frame(maxHeight: maxHeight)
    }
}

/// A titled group of settings rows (a native `Section`).
struct SettingsSection<Content: View>: View {
    private let title: LocalizedStringKey
    private let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Section {
            content
        } header: {
            Text(title)
        }
    }
}

/// Label on the left, switch on the right (the System Settings layout).
struct SettingToggle: View {
    private let title: LocalizedStringKey
    private let isOn: Binding<Bool>

    init(_ title: LocalizedStringKey, isOn: Binding<Bool>) {
        self.title = title
        self.isOn = isOn
    }

    var body: some View {
        Toggle(title, isOn: isOn).toggleStyle(.switch)
    }
}

/// A small explanatory line under a setting. Secondary text takes the Increase Contrast variant when it is on.
struct SettingCaption: View {
    private let text: LocalizedStringKey
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Design.Ink.text(colorSchemeContrast == .increased ? .increased : .standard))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Title on the left, control on the right: a native `LabeledContent`.
struct SettingRow<Control: View>: View {
    private let title: LocalizedStringKey
    private let control: Control

    init(_ title: LocalizedStringKey, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        LabeledContent(title) { control }
    }
}

extension Animation {
    /// Spring for settings changes; a short fade when Reduce Motion is on.
    static func settingsChange(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.8)
    }
}

private struct Dimmed: ViewModifier {
    let condition: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .disabled(condition)
            .opacity(condition ? 0.4 : 1)
            .animation(.settingsChange(reduceMotion: reduceMotion), value: condition)
    }
}

/// Rows that belong to the switch above them: indented, and present only while that switch is on.
/// They enter and leave with the transition below; pair it with `Binding.animated` on the switch.
private struct Disclosure: ViewModifier {
    let isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if isOn {
            content
                .padding(.leading, Design.Space.inset)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        }
    }
}

extension Binding {
    /// The same binding, but a change animates with the settings spring (a short fade with Reduce Motion),
    /// so rows disclosed by this value ease in and out instead of jumping.
    func animated(reduceMotion: Bool) -> Binding<Value> {
        // SwiftUI calls both closures on the main thread; the binding itself is not marked Sendable.
        nonisolated(unsafe) let base = self
        return Binding(get: { base.wrappedValue },
                       set: { newValue in withAnimation(.settingsChange(reduceMotion: reduceMotion)) { base.wrappedValue = newValue } })
    }
}

extension View {
    /// Shows the view, indented, only while `isOn` holds.
    func disclosed(by isOn: Bool) -> some View {
        modifier(Disclosure(isOn: isOn))
    }

    /// Disables the view and fades it while `condition` holds.
    func dimmed(when condition: Bool) -> some View {
        modifier(Dimmed(condition: condition))
    }
}
