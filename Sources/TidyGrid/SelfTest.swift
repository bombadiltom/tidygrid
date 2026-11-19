import AppKit

/// Diagnostic: `TidyGrid --self-test <bundle id>` moves that app's focused window through every
/// layout on every screen and writes wanted vs. actual frames to ~/Library/Logs/TidyGrid-selftest.log.
enum SelfTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--self-test"), args.count > i + 1 else { return }
        let bundleID = args[i + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { run(bundleID: bundleID) }
    }

    private static func run(bundleID: String) {
        var lines = ["TidyGrid self-test \(Date())"]
        for s in NSScreen.screens {
            lines.append("screen \(s.localizedName) ax=\(s.axFrame) visible=\(s.axVisibleFrame)")
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              let w = AX.focusedWindow(pid: app.processIdentifier) else {
            lines.append("no window for \(bundleID)")
            write(lines)
            return
        }
        let start = AX.frame(w)
        var failures = 0
        for screen in NSScreen.screens {
            for layout in AppSettings.shared.prefs.layouts {
                let target = layout.frame(in: screen.axVisibleFrame)
                AX.setFrame(w, target)
                usleep(250_000)
                let got = AX.frame(w) ?? .null
                let ok = abs(got.minX - target.minX) <= 2 && abs(got.minY - target.minY) <= 2
                    && abs(got.width - target.width) <= 2 && abs(got.height - target.height) <= 2
                if !ok { failures += 1 }
                lines.append("\(ok ? "OK  " : "FAIL") \(screen.localizedName) / \(layout.name): want \(target) got \(got)")
            }
        }
        lines.append("\(failures) failures")
        if let start { AX.setFrame(w, start) }
        write(lines)
    }

    private static func write(_ lines: [String]) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/TidyGrid-selftest.log")
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
