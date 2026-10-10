// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

import Foundation

/// Which links found in a QR code or barcode may be offered to the user.
enum LinkPolicy {
    /// The address to ask about opening, or nil if nothing should be offered. Only a single-line http or
    /// https address qualifies, and only when the user's choice is "ask": with "copy" nothing is offered.
    static func urlToConfirm(in text: String, action: String) -> URL? {
        guard action == "ask", !text.contains("\n"),
              let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        return url
    }

    /// What opening a link does once the user asked for it.
    enum Opening: Equatable {
        case open, ask, refuse
    }

    /// The schemes Nictate ever hands to the system. Anything else (file, javascript, an app's own scheme)
    /// could run or reveal something local, so it is refused at the sink whatever produced the URL.
    private static let openableSchemes: Set<String> = ["http", "https", "mailto"]

    /// A bare "mailto:" link for one address, built with URLComponents so nothing in `address` can become a
    /// query: a leading "mailto:" is dropped and anything from "?" or "#" on is ignored, so no extra recipient
    /// or body reaches the mail draft. Nil when no address is left.
    static func mailtoURL(for address: String) -> URL? {
        var bare = Substring(address.trimmingCharacters(in: .whitespacesAndNewlines))
        if bare.lowercased().hasPrefix("mailto:") { bare = bare.dropFirst("mailto:".count) }
        bare = bare.prefix { $0 != "?" && $0 != "#" }
        guard bare.contains("@"), !bare.contains(where: { $0.isWhitespace || $0 == "," || $0 == ";" }) else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = String(bare)
        return components.url
    }

    /// A link's menu title. A long address is shortened in the middle, keeping the scheme and host (never
    /// cut, so the destination is always visible) and as much of the end as fits within `limit`.
    static func menuTitle(for url: URL, limit: Int = 48) -> String {
        let full = url.absoluteString
        guard full.count > limit else { return full }
        guard let separator = full.range(of: "://") else { return String(full.prefix(limit - 1)) + "…" }
        let pathStart = full[separator.upperBound...].firstIndex(of: "/").map { full.index(after: $0) } ?? full.endIndex
        let head = full[..<pathStart]
        let room = limit - head.count - 1
        return String(head) + "…" + (room > 0 ? String(full.suffix(room)) : "")
    }

    /// An explicit click opens at once, unless the user chose "ask before opening" (D16).
    static func opening(_ url: URL, action: String) -> Opening {
        guard let scheme = url.scheme?.lowercased(), openableSchemes.contains(scheme) else { return .refuse }
        return action == "ask" ? .ask : .open
    }
}
