import AppKit
import SwiftUI

final class DesktopPanel: NSPanel {
    init<Content: View>(contentView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 243),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        for btn in [.closeButton, .miniaturizeButton, .zoomButton] as [NSWindow.ButtonType] {
            standardWindowButton(btn)?.isHidden = true
        }
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        // 层级高于菜单栏，允许窗口进入顶部菜单栏区域
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)

        let hosting = NSHostingView(rootView: contentView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        self.contentView = hosting
    }

    func applyLevel(_ pref: WindowLevelPref) {
        if pref == .desktop {
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        } else {
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        }
    }

    /// 固定位置：锁定后禁止背景拖动、窗口移动与调整大小。
    func applyMovable(_ locked: Bool) {
        isMovableByWindowBackground = !locked
        isMovable = !locked
        if locked {
            styleMask.remove(.resizable)
        } else {
            styleMask.insert(.resizable)
        }
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let scr = screen ?? NSScreen.main else { return frameRect }
        let r = scr.frame
        var f = frameRect
        f.origin.x = max(r.minX, min(f.origin.x, r.maxX - f.width))
        f.origin.y = max(r.minY, min(f.origin.y, r.maxY - f.height))
        return f
    }

    func show() {
        if let saved = UserDefaults.standard.string(forKey: "panelFrame") {
            setFrame(NSRectFromString(saved), display: true)
        } else if let scr = NSScreen.main {
            var f = self.frame
            f.origin.x = scr.frame.minX
            f.origin.y = scr.frame.maxY - f.height
            setFrame(f, display: true)
        }
        orderFrontRegardless()
    }
}
