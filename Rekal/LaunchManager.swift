import Foundation
import ServiceManagement

class LaunchManager {
    private static let launchAgentPlist = "com.thomasm6m6.RekalAgent.plist"

    static func registerLoginItem() -> Bool {
        let service = SMAppService.mainApp
        do {
            try service.register()
            print("Registered login item")
            return true
        } catch {
            print("Error registering login item: \(error)")
            return false
        }
    }

    static func unregisterLoginItem() -> Bool {
        let service = SMAppService.mainApp
        do {
            try service.unregister()
            print("Unregistered login item")
            return true
        } catch {
            print("Error unregistering login item: \(error)")
            return false
        }
    }

    static func getLoginItemStatus() -> SMAppService.Status {
        let service = SMAppService.mainApp
        return service.status
    }

    static func registerLaunchAgent() -> Bool {
        let service = SMAppService.agent(plistName: launchAgentPlist)
        do {
            try service.register()
            print("Registered launch agent")
            return true
        } catch {
            print("Error registering launch agent: \(error)")
            return false
        }
    }

    static func unregisterLaunchAgent() -> Bool {
        let service = SMAppService.agent(plistName: launchAgentPlist)
        do {
            try service.unregister()
            print("Unregistered launch agent")
            return true
        } catch {
            print("Error unregistering launch agent: \(error)")
            return false
        }
    }

    static func getLaunchAgentStatus() -> SMAppService.Status {
        let service = SMAppService.agent(plistName: launchAgentPlist)
        return service.status
    }
}
