import Foundation

import UIKit

struct DeviceEnvironment {
    private let stableIDKey = "com.Statsig.InternalStore.stableIDKey"

    var deviceOS: String = "iOS"
    var sdkType: String = "ios-client"
    var sdkVersion: String = "1.11.0"
    var sessionID: String? { UUID().uuidString }
    var systemVersion: String { UIDevice.current.systemVersion }
    var systemName: String { UIDevice.current.systemName }
    var language: String { Locale.preferredLanguages[0] }
    var locale: String { Locale.current.identifier }
    var appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    var appIdentifier = Bundle.main.bundleIdentifier

    var deviceModel: String {
        if let simulatorModelIdentifier = ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulatorModelIdentifier
        }
        var sysinfo = utsname()
        uname(&sysinfo)
        if let deviceModel = String(bytes: Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN)), encoding: .ascii) {
            return deviceModel.trimmingCharacters(in: .controlCharacters)
        } else {
            return UIDevice.current.model
        }
    }

    func getStableID(_ overrideStableID: String? = nil) -> String {
        let stableID = overrideStableID ?? UserDefaults.standard.string(forKey: stableIDKey) ?? UUID().uuidString
        UserDefaults.standard.setValue(stableID, forKey: stableIDKey)
        return stableID
    }

    func get(_ overrideStableID: String? = nil) -> [String: String?] {
        return [
            "appIdentifier": appIdentifier,
            "appVersion": appVersion,
            "deviceModel": deviceModel,
            "deviceOS": deviceOS,
            "language": language,
            "locale": locale,
            "sdkType": sdkType,
            "sdkVersion": sdkVersion,
            "sessionID": sessionID,
            "stableID": getStableID(overrideStableID),
            "systemVersion": systemVersion,
            "systemName": systemName
        ]
    }
}
