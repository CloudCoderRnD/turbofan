// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import AppKit
import SwiftUI
import UserNotifications

/// One message from the CloudCoder feed: an update notice, news, a tip or an alert.
public struct FeedMessage: Codable, Identifiable, Equatable {
    public enum Kind: String, Codable { case alert, update, promo, news, tip }

    public struct Action: Codable, Equatable {
        public var label: String
        public var url: URL
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var body: String
    /// Banner image, shown 2:1 at the top of the card and attached to the macOS notification.
    public var image: URL?
    public var action: Action?
    /// Only show to these versions (inclusive). Use maxVersion for "please update" notices.
    public var minVersion: String?
    public var maxVersion: String?
    /// "free", "pro"; missing = everyone.
    public var editions: [String]?
    public var start: Date?
    public var end: Date?
    /// Also post a macOS notification.
    public var notify: Bool?

    /// The feed comes from the network, so only follow https links and images from it.
    /// Anything else (file:, custom app schemes, plain http) is dropped from the message.
    var httpsOnly: FeedMessage {
        var m = self
        if !Self.isHTTPS(m.action?.url) { m.action = nil }
        if !Self.isHTTPS(m.image) { m.image = nil }
        return m
    }

    static func isHTTPS(_ url: URL?) -> Bool { url?.scheme?.lowercased() == "https" }

    var priority: Int {
        switch kind {
        case .alert: return 0
        case .update: return 1
        case .promo: return 2
        case .news: return 3
        case .tip: return 4
        }
    }
}

struct Feed: Codable { var messages: [FeedMessage] }

/// Fetches the CloudCoder message feed (on launch and every 6 hours) and decides what to show.
/// Sends only the app version and edition in the URL; no identifiers. Can be turned off.
@MainActor
public final class MessageCenter: ObservableObject {
    public static let shared = MessageCenter()

    public static let defaultFeed = URL(string: "https://turbo.cloud-coder.com/messages.json")!
    static let enabledKey = "messagesEnabled"

    @Published public private(set) var messages: [FeedMessage] = []
    @Published private var dismissed: Set<String>

    private var timer: Timer?
    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [Self.enabledKey: true])
        dismissed = Set(defaults.stringArray(forKey: "dismissedMessages") ?? [])
    }

    public var enabled: Bool { defaults.bool(forKey: Self.enabledKey) }

    /// The message to show as a card in the panel, if any.
    public var banner: FeedMessage? {
        guard enabled else { return nil }
        return messages.filter { !dismissed.contains($0.id) }.sorted { $0.priority < $1.priority }.first
    }

    public func start() {
        guard timer == nil else { return }
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in await MessageCenter.shared.refresh() }
        }
    }

    public func dismiss(_ message: FeedMessage) {
        dismissed.insert(message.id)
        defaults.set(Array(dismissed), forKey: "dismissedMessages")
    }

    /// Feed URL, overridable for testing: `defaults write com.cloudcoder.TurboFan messagesFeedURL <url>`.
    var feedURL: URL {
        let base = defaults.string(forKey: "messagesFeedURL").flatMap(URL.init(string:)) ?? Self.defaultFeed
        guard base.isFileURL == false, var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        parts.queryItems = (parts.queryItems ?? []) + [
            URLQueryItem(name: "v", value: Brand.version),
            URLQueryItem(name: "edition", value: Edition.isPro ? "pro" : "free"),
        ]
        return parts.url ?? base
    }

    public func refresh() async {
        guard enabled else { messages = []; return }
        do {
            let (data, response) = try await URLSession.shared.data(from: feedURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let feed = try decoder.decode(Feed.self, from: data)
            messages = feed.messages.filter(applies).map(\.httpsOnly)
            for m in messages where m.notify == true && !dismissed.contains(m.id) { await postNotification(m) }
        } catch {
            // Offline or no feed: keep what we had.
        }
    }

    private func applies(_ m: FeedMessage) -> Bool {
        let now = Date()
        if let s = m.start, now < s { return false }
        if let e = m.end, now > e { return false }
        if let editions = m.editions, !editions.contains(Edition.isPro ? "pro" : "free") { return false }
        if let min = m.minVersion, Self.compare(Brand.version, min) < 0 { return false }
        if let max = m.maxVersion, Self.compare(Brand.version, max) > 0 { return false }
        return true
    }

    /// Compares dotted versions numerically ("1.0.10" > "1.0.9"). "dev" sorts last.
    static func compare(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? Int.max }
        let pb = b.split(separator: ".").map { Int($0) ?? Int.max }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    // MARK: macOS notifications

    private func postNotification(_ m: FeedMessage) async {
        let key = "notified-\(m.id)"
        guard !defaults.bool(forKey: key) else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = m.title
        content.body = m.body
        content.userInfo = ["url": m.action?.url.absoluteString ?? ""]
        if let image = m.image, let attachment = await Self.attachment(for: image, id: m.id) {
            content.attachments = [attachment]
        }
        try? await center.add(UNNotificationRequest(identifier: m.id, content: content, trigger: nil))
        defaults.set(true, forKey: key)
    }

    private static func attachment(for url: URL, id: String) async -> UNNotificationAttachment? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tf-msg-\(id).\(ext)")
        guard (try? data.write(to: file)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: id, url: file)
    }
}

/// Opens a message's link when its macOS notification is clicked.
final class NotificationOpener: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationOpener()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let s = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: s),
           FeedMessage.isHTTPS(url) {
            await MainActor.run { _ = NSWorkspace.shared.open(url) }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// The in-panel card for a feed message.
struct MessageCard: View {
    let message: FeedMessage
    let onDismiss: () -> Void

    private var tint: Color {
        switch message.kind {
        case .alert: return .red
        case .update: return Color(red: 0.31, green: 0.72, blue: 1.0) // CloudCoder accent
        case .promo: return Color(red: 0.94, green: 0.64, blue: 0.29) // CloudCoder amber
        case .news: return .teal
        case .tip: return .green
        }
    }

    private var label: String {
        switch message.kind {
        case .alert: return "Important"
        case .update: return "Update"
        case .promo: return "Offer"
        case .news: return "News"
        case .tip: return "Tip"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = message.image {
                AsyncImage(url: image) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(2, contentMode: .fill)
                    } else {
                        Rectangle().fill(tint.opacity(0.15)).aspectRatio(2, contentMode: .fit)
                    }
                }
                .frame(maxWidth: .infinity)
                .clipped()
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label.uppercased())
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(tint.opacity(0.2)))
                        .foregroundStyle(tint)
                    Spacer()
                    Button(action: onDismiss) { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Dismiss")
                }
                Text(message.title).font(.headline)
                Text(message.body).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = message.action {
                    Link(action.label, destination: action.url)
                        .buttonStyle(.borderedProminent)
                        .tint(tint)
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }
            .padding(10)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
