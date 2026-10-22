// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import AppKit
import SwiftUI

/// `TurboFan --shots <dir> [--light]` saves real screenshots of every panel tab and the About window,
/// with live data, then quits. Each view is drawn into an off-screen window with real AppKit
/// controls, so no screen-recording permission is needed.
@MainActor
enum Screenshots {
    static func run(dir: URL, model: AppModel, light: Bool) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tabs = PanelView.builtIn + (Extensions.edition?.tabs.map(\.id) ?? [])
        var jobs: [(String, AnyView)] = tabs.map { tab in
            (tab.lowercased(), AnyView(PanelView(tab: tab).environmentObject(model)))
        }
        jobs.append(("about", AnyView(AboutView())))
        capture(jobs, dir: dir, appearance: NSAppearance(named: light ? .aqua : .darkAqua)!)
    }

    private static func capture(_ jobs: [(String, AnyView)], dir: URL, appearance: NSAppearance) {
        guard let (name, view) = jobs.first else { NSApp.terminate(nil); return }
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 400, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        window.orderFrontRegardless()
        // Give onAppear loaders (fan status, history, sensors) time to fill in, then fit and draw.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            MainActor.assumeIsolated {
                window.setContentSize(host.fittingSize)
                host.layoutSubtreeIfNeeded()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    MainActor.assumeIsolated {
                        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                            host.cacheDisplay(in: host.bounds, to: rep)
                            try? rep.representation(using: .png, properties: [:])?
                                .write(to: dir.appendingPathComponent("\(name).png"))
                        }
                        window.orderOut(nil)
                        capture(Array(jobs.dropFirst()), dir: dir, appearance: appearance)
                    }
                }
            }
        }
    }
}
