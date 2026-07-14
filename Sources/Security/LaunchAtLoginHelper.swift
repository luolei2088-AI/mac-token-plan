import Foundation
import ServiceManagement

/// 开机自启（登录项）管理，基于 SMAppService（macOS 13+）。
/// 仅在 .app bundle 运行时有效；swift run 调试模式下 register 会失败（非 bundle）。
enum LaunchAtLoginHelper {
    @MainActor
    static func set(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            FileHandle.standardError.write(Data("LaunchAtLogin set \(enabled) ok\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("LaunchAtLogin set \(enabled) failed: \(error)\n".utf8))
        }
    }

    @MainActor
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
