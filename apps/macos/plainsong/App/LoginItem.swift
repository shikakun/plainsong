import AppKit
import ServiceManagement

enum LoginItem {
    private static let mayLaunchAtLoginKey = "mayLaunchAtLogin"

    /// 問い合わせると起動が2msほど遅れるので、起動するときは最後に問い合わせた結果を使う
    static var mayLaunchAtLogin: Bool {
        UserDefaults.standard.bool(forKey: mayLaunchAtLoginKey)
    }

    static var status: SMAppService.Status {
        let status = SMAppService.mainApp.status
        UserDefaults.standard.set(status == .enabled || status == .requiresApproval, forKey: mayLaunchAtLoginKey)
        return status
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// 起動のApple Eventは、applicationWillFinishLaunchingではまだ読めない
    static var wasLaunchedAtLogin: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
