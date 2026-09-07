import AppKit
import SwiftUI
import os.log

final class DesktopPanel: NSPanel {
    /// 拖动状态。窗口位置拖动用系统 isMovableByWindowBackground（window server 层处理，
    /// accessory/nonactivating 面板未激活时也可靠）；本地 monitor 只负责四角 resize。
    private enum DragMode {
        case idle
        case resize(ResizeHandle.Edge)
    }
    private var dragMonitor: Any?
    private var dragMode: DragMode = .idle
    private var dragStartLocationInWindow: NSPoint = .zero
    private var dragStartFrame: NSRect = .zero

    /// applyMovable 控制。false 时点哪都不动。
    private var panEnabled = false

    /// 4 个角的隐形把手。仅用于 cursor 变化（resetCursorRects），
    /// 手势在 installDragMonitor 里统一处理。
    private var resizeHandles: [ResizeHandle] = []
    private static let minSize = NSSize(width: 180, height: 150)
    private static let resizeThickness: CGFloat = 10

    init<Content: View>(contentView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 243),
            // 用 .borderless 替代原本的 .titled + .fullSizeContentView：
            // .titled 即便设置了 titlebarAppearsTransparent、隐藏了标准按钮，
            // 系统仍保留 _NSTitlebarView，在 isMovableByWindowBackground=true 时
            // 会画出多个不可交互的 chrome 图标（左上角的代理图标/ghost zoom button）。
            // .borderless 完全无 titlebar，画面干净；resize 让我们自己用 corner 把手实现。
            styleMask: [.nonactivatingPanel, .borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = true
        // 让 NSWindow 接收 mouseMoved，搭配 ResizeHandle 的 resetCursorRects 才能持续更新 cursor。
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        // 层级高于菜单栏，允许窗口进入顶部菜单栏区域
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)

        let hosting = NSHostingView(rootView: contentView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // SwiftUI 内容驱动 intrinsicContentSize（nil proposal 布局，不受窗口当前尺寸污染），
        // fitHeightToContent 据此量内容真实高度。
        hosting.sizingOptions = [.intrinsicContentSize]
        self.contentView = hosting

        installDragMonitor()
        installResizeHandles()
    }

    func applyLevel(_ pref: WindowLevelPref) {
        if pref == .desktop {
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        } else {
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        }
    }

    /// 锁定后禁止背景拖动、窗口移动与调整大小。
    func applyMovable(_ locked: Bool) {
        isMovable = !locked
        // 背景位置拖动交给系统（borderless 下无 titlebar ghost 图标问题，且不依赖 app 激活）。
        isMovableByWindowBackground = !locked
        panEnabled = !locked
        // locked 时整窗不动，corner 自然也不该动。隐藏把手指针顺便断绝鼠标命中。
        for h in resizeHandles {
            h.isHidden = locked
        }
        if locked {
            styleMask.remove(.resizable)
        } else {
            styleMask.insert(.resizable)
        }
    }

    /// 事件监听：只接管四角 resize。mouseDown 落在 corner handle 内 → resize 模式并吞掉事件
    /// （return nil，阻止系统 isMovableByWindowBackground 同时移动窗口）；其余区域一律放行，
    /// 由系统处理背景拖动。
    private func installDragMonitor() {
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, event.window === self else { return event }
            switch event.type {
            case .leftMouseDown:
                self.beginDrag(atWindow: event)
                if case .resize = self.dragMode { return nil }   // 命中 corner：自己 resize
            case .leftMouseDragged:
                if case .resize = self.dragMode {
                    self.handleResize(event: event)
                    return nil
                }
            case .leftMouseUp:
                if case .resize = self.dragMode {
                    self.endDrag()
                    return nil
                }
            default:
                break
            }
            return event   // 背景点击/拖动：放行，系统 isMovableByWindowBackground 接管移动
        }
    }

    private func beginDrag(atWindow event: NSEvent) {
        guard panEnabled, let cv = contentView else {
            dragMode = .idle
            return
        }
        // 找鼠标位置是否落在某个未隐藏的 corner handle 的 frame 内（contentView 坐标系）。
        let ptInContent = cv.convert(event.locationInWindow, from: nil)
        if let handle = resizeHandles.first(where: { !$0.isHidden && $0.frame.contains(ptInContent) }) {
            dragMode = .resize(handle.edge)
            dragStartLocationInWindow = event.locationInWindow
            dragStartFrame = frame
        } else {
            dragMode = .idle   // 背景：交给系统拖动
        }
    }

    private func handleResize(event: NSEvent) {
        guard case .resize(let edge) = dragMode else { return }
        // 用 locationInWindow（window 坐标系，y 朝上）相对起始点的位移，对角锚定 resize。
        let cur = event.locationInWindow
        let dx = cur.x - dragStartLocationInWindow.x
        let dy = cur.y - dragStartLocationInWindow.y
        setFrame(computeFrame(edge: edge, start: dragStartFrame, dx: dx, dy: dy), display: true)
    }

    private func endDrag() {
        dragMode = .idle
    }

    /// 对角锚定的 resize：被拎起的 corner 移动，对角 (opposite corner) 不动。
    /// 缩到最小尺寸时，把对边"推回"以保持 opposite corner 锚定。
    private func computeFrame(edge: ResizeHandle.Edge, start: NSRect, dx: CGFloat, dy: CGFloat) -> NSRect {
        let minW = Self.minSize.width
        let minH = Self.minSize.height
        switch edge {
        case .topLeft:
            let newW = max(minW, start.width - dx)
            let newH = max(minH, start.height + dy)
            return NSRect(x: start.maxX - newW, y: start.minY, width: newW, height: newH)
        case .topRight:
            let newW = max(minW, start.width + dx)
            let newH = max(minH, start.height + dy)
            return NSRect(x: start.minX, y: start.minY, width: newW, height: newH)
        case .bottomLeft:
            let newW = max(minW, start.width - dx)
            let newH = max(minH, start.height - dy)
            return NSRect(x: start.maxX - newW, y: start.maxY - newH, width: newW, height: newH)
        case .bottomRight:
            let newW = max(minW, start.width + dx)
            let newH = max(minH, start.height - dy)
            return NSRect(x: start.minX, y: start.maxY - newH, width: newW, height: newH)
        }
    }

    private func installResizeHandles() {
        guard let cv = contentView else { return }
        let t = Self.resizeThickness
        let b = cv.bounds
        // 4 个角落；autoresizingMask 让 corner 跟随 contentView 缩放/移动。
        let corners: [(ResizeHandle.Edge, NSRect, NSView.AutoresizingMask)] = [
            (.topLeft,     NSRect(x: 0,           y: b.maxY - t,  width: t, height: t), [.minXMargin, .maxYMargin]),
            (.topRight,    NSRect(x: b.maxX - t,  y: b.maxY - t,  width: t, height: t), [.maxXMargin, .maxYMargin]),
            (.bottomLeft,  NSRect(x: 0,           y: 0,           width: t, height: t), [.minXMargin, .minYMargin]),
            (.bottomRight, NSRect(x: b.maxX - t,  y: 0,           width: t, height: t), [.maxXMargin, .minYMargin]),
        ]
        for (edge, frame, mask) in corners {
            let h = ResizeHandle(edge: edge)
            h.frame = frame
            h.autoresizingMask = mask
            h.isHidden = true  // 默认 locked
            cv.addSubview(h)
            resizeHandles.append(h)
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

    /// 高度自适应内容：按 SwiftUI 内容的理想高度调整窗口高度（顶部锚定，宽度保持不变）。
    /// 平台增减（开关、失败降级）会让行数变化，固定初始高度 243 装不下时底部会被裁掉。
    func fitHeightToContent() {
        guard let hosting = contentView as? NSHostingView<WidgetCard> else {
            os_log("fit: cast failed, contentView=%{public}@", log: .default, type: .error, String(describing: contentView))
            return
        }
        hosting.layoutSubtreeIfNeeded()   // 强制 SwiftUI 立即重算，避免读到上一次布局的旧 intrinsic
        hosting.invalidateIntrinsicContentSize()
        let raw = hosting.intrinsicContentSize.height
        let h = max(Self.minSize.height, raw)
        os_log("fit: intrinsic=%{public}f -> h=%{public}f frame=%{public}f", log: .default, type: .info, raw, h, frame.height)
        if h <= 0 || abs(h - frame.height) <= 1 { return }
        var f = frame
        f.origin.y += f.height - h   // 顶部（maxY）锚定，往下长/缩
        f.size.height = h
        setFrame(f, display: true)
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

    /// 透明的 corner 把手。仅有 resetCursorRects 一件事 —— 鼠标进入时改 cursor。
    /// 手势由 installDragMonitor / beginDrag 统一接管（命中 frame → .resize 模式）。
    fileprivate final class ResizeHandle: NSView {
        enum Edge { case topLeft, topRight, bottomLeft, bottomRight }
        let edge: Edge

        init(edge: Edge) {
            self.edge = edge
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: cursor)
        }

        // NSCursor 没公开对角 resize cursor，用 SF Symbol 拼一个。
        private var cursor: NSCursor {
            let symbolName: String
            switch edge {
            case .topLeft, .bottomRight: symbolName = "arrow.up.left.and.arrow.down.right"
            case .topRight, .bottomLeft: symbolName = "arrow.up.right.and.arrow.down.left"
            }
            if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let size = img.size
                return NSCursor(image: img, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
            }
            return .arrow
        }
    }
}
