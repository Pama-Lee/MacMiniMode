// 检查更新：每天向 GitHub 查一次最新版本，有新版就下载、校验签名，然后提示安装。
// 安装本身交给系统安装器，这里不碰管理员权限。

import AppKit
import Security

final class Updater {
    static let repo = "Pama-Lee/MacMiniMode"
    static let assetName = "MacMiniMode.pkg"
    static let autoCheckKey = "autoCheckUpdates"
    static let lastCheckKey = "lastUpdateCheck"
    static let promptedKey = "promptedUpdateVersion"

    let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    /// 已下载并通过校验、等待安装的版本。
    private(set) var ready: (version: String, pkg: URL)?
    var onChange: () -> Void = {}
    private var busy = false
    private var timer: Timer?

    var autoCheck: Bool {
        get { UserDefaults.standard.object(forKey: Self.autoCheckKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.autoCheckKey) }
    }

    private var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.macminimode.menubar/updates", isDirectory: true)
    }

    func start() {
        try? FileManager.default.removeItem(at: cacheDir)
        // 刚登录时网络可能还没好，稍等再查；之后每小时看一眼是否已满一天。
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.checkIfDue() }
    }

    private func checkIfDue() {
        guard autoCheck else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        check(manual: false)
    }

    /// manual 为 true 时是用户点的「检查更新」，无论结果如何都给反馈；自动检查只在有新版时出声。
    func check(manual: Bool) {
        if let ready {
            if manual { prompt(ready.version, ready.pkg) }
            return
        }
        guard !busy else { return }
        busy = true
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!,
                                 timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacMiniMode/\(current)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async { self.handleRelease(data, response, error, manual: manual) }
        }.resume()
    }

    private func handleRelease(_ data: Data?, _ response: URLResponse?, _ error: Error?, manual: Bool) {
        guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            NSLog("[update] check failed: %@", error?.localizedDescription ?? "unexpected response")
            return finish(manual, failure: L("无法连接 GitHub 检查更新，请稍后再试。", "Could not reach GitHub to check for updates. Try again later."))
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard Self.isNewer(latest, than: current) else {
            NSLog("[update] up to date (%@, latest %@)", current, latest)
            return finish(manual, info: L("已是最新版本（\(current)）。", "You're up to date (\(current))."))
        }
        // 只接受本仓库发布页上的那个固定文件名，别的地址一律不下。
        let prefix = "https://github.com/\(Self.repo)/releases/download/"
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let asset = assets.first(where: { $0["name"] as? String == Self.assetName }),
              let link = asset["browser_download_url"] as? String, link.hasPrefix(prefix),
              let url = URL(string: link) else {
            NSLog("[update] %@ has no %@ asset", tag, Self.assetName)
            return finish(manual, failure: L("新版本 \(latest) 还没有可下载的安装包。", "Version \(latest) has no installer to download yet."))
        }
        NSLog("[update] downloading %@", latest)
        URLSession.shared.downloadTask(with: url) { temp, _, error in
            var pkg: URL?
            if let temp {
                let dest = self.cacheDir.appendingPathComponent("MacMiniMode-\(latest).pkg")
                try? FileManager.default.createDirectory(at: self.cacheDir, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: dest)
                if (try? FileManager.default.moveItem(at: temp, to: dest)) != nil {
                    if Self.isTrusted(dest) {
                        pkg = dest
                    } else {
                        try? FileManager.default.removeItem(at: dest)
                    }
                }
            }
            DispatchQueue.main.async {
                guard let pkg else {
                    NSLog("[update] download or verification failed: %@", error?.localizedDescription ?? "signature not trusted")
                    return self.finish(manual, failure: L("新版本 \(latest) 下载失败或未通过签名校验。", "Version \(latest) could not be downloaded or failed signature verification."))
                }
                NSLog("[update] %@ downloaded and verified", latest)
                self.busy = false
                self.ready = (latest, pkg)
                self.onChange()
                // 自动检查时，同一个版本只弹一次；之后可以从菜单里安装。
                let prompted = UserDefaults.standard.string(forKey: Self.promptedKey)
                if manual || prompted != latest {
                    UserDefaults.standard.set(latest, forKey: Self.promptedKey)
                    self.prompt(latest, pkg)
                }
            }
        }.resume()
    }

    private func finish(_ manual: Bool, info: String? = nil, failure: String? = nil) {
        busy = false
        guard manual, let text = info ?? failure else { return }
        let alert = NSAlert()
        alert.alertStyle = failure == nil ? .informational : .warning
        alert.messageText = text
        if failure != nil {
            alert.addButton(withTitle: L("好", "OK"))
            alert.addButton(withTitle: L("打开下载页", "Open Downloads"))
        }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://github.com/\(Self.repo)/releases/latest")!)
        }
    }

    func installReady() {
        if let ready { prompt(ready.version, ready.pkg) }
    }

    private func prompt(_ version: String, _ pkg: URL) {
        let alert = NSAlert()
        alert.messageText = L("Mac mini 模式 \(version) 可以安装了", "Mac mini Mode \(version) is ready to install")
        alert.informativeText = L(
            "新版本已下载并通过签名校验，当前版本是 \(current)。点「安装」会打开系统安装器，按提示完成即可。",
            "The update is downloaded and its signature verified. You have \(current). Install opens the system installer.")
        alert.addButton(withTitle: L("安装", "Install"))
        alert.addButton(withTitle: L("稍后", "Later"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(pkg)
        }
    }

    static func isNewer(_ candidate: String, than base: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = base.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - 签名校验

    /// 我们自己下载的文件不带隔离标记，系统打开时不会再做 Gatekeeper 检查，所以这里自己查：
    /// 必须通过 Apple 公证，并且签名团队和正在运行的这个应用是同一个。
    static func isTrusted(_ pkg: URL) -> Bool {
        guard let team = ownTeamID() else {
            NSLog("[update] this build has no signing team, cannot verify updates")
            return false
        }
        guard run("/usr/sbin/spctl", ["--assess", "--type", "install", pkg.path]).status == 0 else { return false }
        let signature = run("/usr/sbin/pkgutil", ["--check-signature", pkg.path]).output
        let pattern = #"(?m)^\s*1\. Developer ID Installer: .+ \(([A-Z0-9]{10})\)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: signature, range: NSRange(signature.startIndex..., in: signature)),
              let range = Range(match.range(at: 1), in: signature) else { return false }
        return signature[range] == team
    }

    static func ownTeamID() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = args
        task.standardOutput = pipe
        task.standardError = pipe
        do { try task.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
