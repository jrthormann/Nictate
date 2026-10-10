// Nictate: a macOS menu bar app that copies text from anywhere on your screen.
// Copyright (C) 2026  jrthormann
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import AppKit

/// The newest published release, as GitHub's release API describes it. Drafts are never returned by that API.
struct ReleaseInfo: Decodable, Equatable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

/// Check for Updates. It runs only when the user asks: one request to GitHub's public release API, nothing
/// else, and no cookies or cache.
enum UpdateCheck {
    enum Outcome: Equatable {
        case upToDate
        case available(version: String, page: URL)
        case busy
        case failed
    }

    static let endpoint = URL(string: "https://api.github.com/repos/jrthormann/Nictate/releases/latest")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// `1.0.1` is newer than `1.0.0`; a leading "v" is ignored, and missing parts count as zero. A prerelease such as
    /// `1.0.0-beta.2` is older than its release `1.0.0`, and newer than `1.0.0-beta.1`.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let new = split(candidate), old = split(current)
        let newCore = numbers(new.core), oldCore = numbers(old.core)
        for index in 0..<max(newCore.count, oldCore.count) {
            let a = index < newCore.count ? newCore[index] : 0
            let b = index < oldCore.count ? oldCore[index] : 0
            if a != b { return a > b }
        }
        switch (new.prerelease, old.prerelease) {
        case (nil, nil): return false
        case (nil, _?): return true
        case (_?, nil): return false
        case let (a?, b?): return comparePrerelease(a, b) > 0
        }
    }

    /// The core numbers and the prerelease part, split at the first "-".
    private static func split(_ version: String) -> (core: String, prerelease: String?) {
        let trimmed = version.drop(while: { $0 == "v" || $0 == "V" })
        guard let dash = trimmed.firstIndex(of: "-") else { return (String(trimmed), nil) }
        return (String(trimmed[..<dash]), String(trimmed[trimmed.index(after: dash)...]))
    }

    /// Dot-separated identifiers in order: numbers compare as numbers, anything else as text, and a longer list is newer.
    private static func comparePrerelease(_ a: String, _ b: String) -> Int {
        let left = a.split(separator: "."), right = b.split(separator: ".")
        for (x, y) in zip(left, right) where x != y {
            if let nx = Int(x), let ny = Int(y) { return nx < ny ? -1 : 1 }
            return x < y ? -1 : 1
        }
        return left.count == right.count ? 0 : (left.count < right.count ? -1 : 1)
    }

    /// Only a release page on github.com is ever offered, so a changed response cannot point elsewhere.
    static func accepts(_ release: ReleaseInfo) -> Bool {
        release.htmlURL.scheme == "https" && release.htmlURL.host == "github.com"
    }

    static func outcome(current: String, release: ReleaseInfo) -> Outcome {
        guard accepts(release) else { return .failed }
        guard isNewer(release.tagName, than: current) else { return .upToDate }
        return .available(version: String(release.tagName.drop(while: { $0 == "v" || $0 == "V" })), page: release.htmlURL)
    }

    static func fetchLatest() async -> Outcome {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Nictate/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // 403 and 429 are GitHub's rate limit for unauthenticated requests: a different message than a failure.
            if status == 403 || status == 429 { return .busy }
            guard status == 200, data.count < 1_000_000 else { return .failed }
            return outcome(current: currentVersion, release: try JSONDecoder().decode(ReleaseInfo.self, from: data))
        } catch {
            Log.app.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    private static func numbers(_ version: String) -> [Int] {
        version.drop(while: { $0 == "v" || $0 == "V" }).split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}

/// The result of a check, in an alert. A newer release offers its page; the page opens only on the user's click.
@MainActor
enum UpdateAlert {
    private static var checking = false

    static func run() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        let outcome = await UpdateCheck.fetchLatest()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        let current = UpdateCheck.currentVersion
        switch outcome {
        case .upToDate:
            alert.messageText = tr("Nictate is up to date")
            alert.informativeText = tr("Version %@ is the newest release.", current)
            alert.addButton(withTitle: tr("OK"))
            alert.runModal()
        case .available(let version, let page):
            alert.messageText = tr("Nictate %@ is available", version)
            alert.informativeText = tr("You have version %@.", current)
            alert.addButton(withTitle: tr("Open Release Page"))
            alert.addButton(withTitle: tr("Later"))
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
        case .busy:
            alert.messageText = tr("GitHub is busy right now")
            alert.informativeText = tr("Too many update checks were made from this network. Try again in a few minutes.")
            alert.addButton(withTitle: tr("OK"))
            alert.runModal()
        case .failed:
            alert.messageText = tr("Could not check for updates")
            alert.informativeText = tr("Check your connection and try again.")
            alert.addButton(withTitle: tr("OK"))
            alert.runModal()
        }
    }
}
