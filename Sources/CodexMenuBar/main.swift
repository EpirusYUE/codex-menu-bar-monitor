import AppKit
import CodexStatusCore

@MainActor
@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: 30)
    private let reader = CodexActivityReader()
    private let quotaReader = CodexRateLimitReader()
    private var runningTasks: [CodexTask] = []
    private var quota: CodexQuota?
    private var lastRunningIDs: Set<String>?
    private var pollTimer: Timer?
    private var quotaTimer: Timer?
    private var quotaRetryTimer: Timer?
    private var animationTimer: Timer?
    private var rotation: CGFloat = 0
    private var lastAnimationTick = Date()
    private var flashDeadline: Date?
    private var queuedFlashes = 0
    private var lastError: String?
    private var isRefreshing = false
    private var isQuotaRefreshing = false
    private var quotaRetryDelay: TimeInterval = 5

    static func main() {
        if CommandLine.arguments.contains("--status") {
            do {
                let snapshot = try CodexActivityReader().readSnapshot()
                print("running=\(snapshot.runningTasks.count)")
                for task in snapshot.runningTasks {
                    print("\(task.id)\t\(task.title)")
                }
            } catch {
                print("error=\(error.localizedDescription)")
            }
            return
        }
        if CommandLine.arguments.contains("--quota") {
            if let quota = CodexRateLimitReader().readQuota() {
                print("remaining=\(quota.remainingPercent) window=\(quota.windowLabel)")
            } else {
                print("quota=unavailable")
            }
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        loadCachedQuota()
        configureStatusItem()
        refresh()
        refreshQuota()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        quotaTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshQuota() }
        }
    }

    private func configureStatusItem() {
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "Codex 任务状态"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        renderIcon()
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let reader = self.reader
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                let snapshot = try reader.readSnapshot()
                DispatchQueue.main.async {
                    self?.isRefreshing = false
                    self?.accept(snapshot)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isRefreshing = false
                    self?.lastError = error.localizedDescription
                    self?.renderIcon()
                }
            }
        }
    }

    private func accept(_ snapshot: CodexActivitySnapshot) {
        let tasks = snapshot.runningTasks
        let ids = Set(tasks.map(\.id))
        if lastRunningIDs != nil, snapshot.newlyCompletedEventCount > 0 {
            enqueueFlashes(snapshot.newlyCompletedEventCount)
        }
        lastRunningIDs = ids
        runningTasks = tasks
        lastError = nil
        updateAnimationTimer()
        renderIcon()
    }

    private func refreshQuota() {
        guard !isQuotaRefreshing else { return }
        isQuotaRefreshing = true
        let quotaReader = self.quotaReader
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let quota = quotaReader.readQuota()
            DispatchQueue.main.async {
                self?.isQuotaRefreshing = false
                if let quota {
                    self?.quota = quota
                    self?.cacheQuota(quota)
                    self?.quotaRetryDelay = 5
                    self?.quotaRetryTimer?.invalidate()
                    self?.quotaRetryTimer = nil
                } else {
                    self?.scheduleQuotaRetry()
                }
                self?.renderIcon()
            }
        }
    }

    private func scheduleQuotaRetry() {
        guard quotaRetryTimer == nil else { return }
        let delay = quotaRetryDelay
        quotaRetryDelay = min(quotaRetryDelay * 2, 300)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.quotaRetryTimer = nil
                self?.refreshQuota()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        quotaRetryTimer = timer
    }

    private func loadCachedQuota() {
        let defaults = UserDefaults.standard
        guard
            defaults.object(forKey: "quota.remainingPercent") != nil,
            let label = defaults.string(forKey: "quota.windowLabel")
        else { return }
        quota = CodexQuota(
            remainingPercent: defaults.integer(forKey: "quota.remainingPercent"),
            windowLabel: label,
            windowDurationMinutes: defaults.integer(forKey: "quota.windowDurationMinutes")
        )
    }

    private func cacheQuota(_ quota: CodexQuota) {
        let defaults = UserDefaults.standard
        defaults.set(quota.remainingPercent, forKey: "quota.remainingPercent")
        defaults.set(quota.windowLabel, forKey: "quota.windowLabel")
        defaults.set(quota.windowDurationMinutes, forKey: "quota.windowDurationMinutes")
    }

    private func enqueueFlashes(_ count: Int) {
        queuedFlashes += count
        if flashDeadline == nil { beginNextFlash() }
    }

    private func beginNextFlash() {
        guard queuedFlashes > 0 else {
            flashDeadline = nil
            updateAnimationTimer()
            return
        }
        queuedFlashes -= 1
        flashDeadline = Date().addingTimeInterval(0.9)
        updateAnimationTimer()
    }

    private func updateAnimationTimer() {
        let needsAnimation = !runningTasks.isEmpty || flashDeadline != nil
        if needsAnimation, animationTimer == nil {
            lastAnimationTick = Date()
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.animateFrame() }
            }
            RunLoop.main.add(timer, forMode: .common)
            animationTimer = timer
        } else if !needsAnimation {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private func animateFrame() {
        let now = Date()
        let elapsed = min(0.1, max(0, now.timeIntervalSince(lastAnimationTick)))
        lastAnimationTick = now
        if !runningTasks.isEmpty {
            // Treat rotation as distance along the border. Time-based motion stays
            // smooth if the run loop occasionally drops a frame.
            rotation += CGFloat(elapsed * 72)
        }
        if let deadline = flashDeadline, now >= deadline {
            flashDeadline = nil
            beginNextFlash()
        }
        renderIcon()
    }

    private func renderIcon() {
        let flashProgress: CGFloat
        if let deadline = flashDeadline {
            let remaining = max(0, deadline.timeIntervalSinceNow)
            flashProgress = CGFloat((sin(remaining * .pi * 7) + 1) / 2)
        } else {
            flashProgress = 0
        }
        let idleLabel = quota?.compactLabel ?? "--"
        let image = StatusIconRenderer.image(
            isRunning: !runningTasks.isEmpty,
            count: runningTasks.count,
            rotation: rotation,
            flash: flashProgress,
            idleLabel: idleLabel
        )
        statusItem.length = image.size.width
        statusItem.button?.image = image
        let idleText = quota.map { "Codex 当前空闲，\($0.windowLabel) 剩余 \($0.remainingPercent)%" }
            ?? "Codex 当前空闲"
        let text = runningTasks.isEmpty ? idleText : "Codex 正在运行 \(runningTasks.count) 个任务"
        statusItem.button?.toolTip = lastError ?? text
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let statusTitle: String
        if let lastError {
            statusTitle = "⚠︎ \(lastError)"
        } else if runningTasks.isEmpty {
            statusTitle = "Codex 当前空闲"
        } else {
            statusTitle = "Codex 正在运行 \(runningTasks.count) 个任务"
        }
        let header = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if let quota {
            let windowName = quota.windowLabel == "5h" ? "5 小时" : "本周"
            let quotaItem = NSMenuItem(
                title: "\(windowName)剩余 \(quota.remainingPercent)%",
                action: nil,
                keyEquivalent: ""
            )
            quotaItem.isEnabled = false
            menu.addItem(quotaItem)
        }

        if !runningTasks.isEmpty {
            menu.addItem(.separator())
            for task in runningTasks.prefix(6) {
                let title = task.title.isEmpty ? "未命名任务" : task.title
                let item = NSMenuItem(title: "◌ \(title)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.toolTip = title
                menu.addItem(item)
            }
            if runningTasks.count > 6 {
                let more = NSMenuItem(title: "还有 \(runningTasks.count - 6) 个…", action: nil, keyEquivalent: "")
                more.isEnabled = false
                menu.addItem(more)
            }
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "打开 Codex", action: #selector(openCodex), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "立即刷新", action: #selector(refreshFromMenu), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "测试完成闪烁", action: #selector(testFlash), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Codex Monitor", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
    }

    @objc private func openCodex() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/Applications/Codex.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    @objc private func refreshFromMenu() {
        refresh()
        refreshQuota()
    }
    @objc private func testFlash() { enqueueFlashes(1) }
    @objc private func quit() { NSApp.terminate(nil) }
}

@MainActor
enum StatusIconRenderer {
    static func image(
        isRunning: Bool,
        count: Int,
        rotation: CGFloat,
        flash: CGFloat,
        idleLabel: String
    ) -> NSImage {
        let idleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let idleTextWidth = idleLabel.size(withAttributes: idleAttributes).width
        let quotaWidth = max(28, ceil(idleTextWidth) + 12)
        let size = NSSize(width: quotaWidth + 6, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            let badgeColor = NSColor(calibratedWhite: 0.14, alpha: 1)
            let badgeRect = NSRect(x: 3, y: 4, width: quotaWidth, height: 14)
            let fillColor = flash > 0.02
                ? (badgeColor.blended(withFraction: flash * 0.75, of: .systemYellow) ?? badgeColor)
                : badgeColor
            fillColor.setFill()
            NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4).fill()

            let textSize = idleLabel.size(withAttributes: idleAttributes)
            idleLabel.draw(
                at: NSPoint(
                    x: badgeRect.midX - textSize.width / 2,
                    y: badgeRect.midY - textSize.height / 2 + 0.5
                ),
                withAttributes: idleAttributes
            )

            if isRunning {
                let borderRect = badgeRect.insetBy(dx: -1, dy: -1)
                let radius: CGFloat = 5
                let perimeter = 2 * (borderRect.width + borderRect.height - 4 * radius) + 2 * .pi * radius

                let base = NSBezierPath(roundedRect: borderRect, xRadius: radius, yRadius: radius)
                base.lineWidth = 1
                NSColor.white.withAlphaComponent(0.12).setStroke()
                base.stroke()

                func point(on rect: NSRect, radius: CGFloat, distance: CGFloat) -> NSPoint {
                    var d = distance.truncatingRemainder(dividingBy: perimeter)
                    if d < 0 { d += perimeter }

                    let horizontal = rect.width - 2 * radius
                    let vertical = rect.height - 2 * radius
                    let corner = .pi * radius / 2

                    if d < horizontal {
                        return NSPoint(x: rect.minX + radius + d, y: rect.maxY)
                    }
                    d -= horizontal
                    if d < corner {
                        let angle = .pi / 2 - d / radius
                        return NSPoint(
                            x: rect.maxX - radius + cos(angle) * radius,
                            y: rect.maxY - radius + sin(angle) * radius
                        )
                    }
                    d -= corner
                    if d < vertical {
                        return NSPoint(x: rect.maxX, y: rect.maxY - radius - d)
                    }
                    d -= vertical
                    if d < corner {
                        let angle = -d / radius
                        return NSPoint(
                            x: rect.maxX - radius + cos(angle) * radius,
                            y: rect.minY + radius + sin(angle) * radius
                        )
                    }
                    d -= corner
                    if d < horizontal {
                        return NSPoint(x: rect.maxX - radius - d, y: rect.minY)
                    }
                    d -= horizontal
                    if d < corner {
                        let angle = -.pi / 2 - d / radius
                        return NSPoint(
                            x: rect.minX + radius + cos(angle) * radius,
                            y: rect.minY + radius + sin(angle) * radius
                        )
                    }
                    d -= corner
                    if d < vertical {
                        return NSPoint(x: rect.minX, y: rect.minY + radius + d)
                    }
                    d -= vertical
                    let angle = .pi - d / radius
                    return NSPoint(
                        x: rect.minX + radius + cos(angle) * radius,
                        y: rect.maxY - radius + sin(angle) * radius
                    )
                }

                // Overlapping samples form a continuous gradient. Draw the tail
                // first so the leading point is always the brightest layer.
                let sampleCount = 44
                let spacing: CGFloat = 0.72
                for index in stride(from: sampleCount - 1, through: 0, by: -1) {
                    let tailProgress = CGFloat(index) / CGFloat(sampleCount - 1)
                    let strength = pow(1 - tailProgress, 1.65)
                    let center = point(
                        on: borderRect,
                        radius: radius,
                        distance: rotation - CGFloat(index) * spacing
                    )
                    let coreRadius: CGFloat = 0.72 + strength * 0.48
                    let glowRadius = coreRadius * 2.25

                    NSColor.white.withAlphaComponent(strength * 0.07).setFill()
                    NSBezierPath(ovalIn: NSRect(
                        x: center.x - glowRadius,
                        y: center.y - glowRadius,
                        width: glowRadius * 2,
                        height: glowRadius * 2
                    )).fill()

                    NSColor.white.withAlphaComponent(strength * 0.9).setFill()
                    NSBezierPath(ovalIn: NSRect(
                        x: center.x - coreRadius,
                        y: center.y - coreRadius,
                        width: coreRadius * 2,
                        height: coreRadius * 2
                    )).fill()
                }
            }

            if count > 0 {
                let badgeText = count > 9 ? "9+" : String(count)
                let countSize: CGFloat = count > 9 ? 12 : 10
                let countRect = NSRect(
                    x: size.width - countSize - 1,
                    y: 22 - countSize,
                    width: countSize,
                    height: countSize
                )
                NSColor.systemBlue.setFill()
                NSBezierPath(ovalIn: countRect).fill()
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: count > 9 ? 6 : 7.5, weight: .bold),
                    .foregroundColor: NSColor.white
                ]
                let textSize = badgeText.size(withAttributes: attributes)
                badgeText.draw(
                    at: NSPoint(
                        x: countRect.midX - textSize.width / 2,
                        y: countRect.midY - textSize.height / 2 + 0.5
                    ),
                    withAttributes: attributes
                )
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
