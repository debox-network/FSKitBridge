import FSKit
import Foundation

@main
struct FSKitExt: UnaryFileSystemExtension {
    var fileSystem: FSUnaryFileSystem & FSUnaryFileSystemOperations {
        Bridge.shared
    }
}

extension Bundle {
    func getServerPort() throws -> Int {
        guard let config = infoDictionary?["Configuration"] as? [String: Any]
        else {
            throw ConfigurationError.missingConfigurationRoot
        }

        guard let value = config["serverPort"] else {
            throw ConfigurationError.missingValue(key: "serverPort")
        }

        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String,
            let number = Int(
                string.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        {
            return number
        }
        throw ConfigurationError.invalidValue(key: "serverPort")
    }

    var fsShortName: String? {
        guard
            let attrs = infoDictionary?["EXAppExtensionAttributes"]
                as? [String: Any],
            let value = attrs["FSShortName"]
        else { return nil }

        if let string = value as? String {
            return string
        }
        if let string = value as? NSString {
            return string as String
        }
        return nil
    }

    var resolvedShortName: String {
        if let value = fsShortName, !value.isEmpty {
            return value
        }
        return bundleDisplayName
    }

    var fsSubType: Int? {
        guard
            let attrs = infoDictionary?["EXAppExtensionAttributes"]
                as? [String: Any],
            let pers = attrs["FSPersonalities"]
                as? [String: Any],
            let value = pers["FSSubType"]
        else { return nil }

        if let number = value as? NSNumber {
            return number.intValue
        }
        if let intValue = value as? Int {
            return intValue
        }
        return nil
    }

    var bundleDisplayName: String {
        if let displayName = object(forInfoDictionaryKey: "CFBundleDisplayName")
            as? String,
            !displayName.isEmpty
        {
            return displayName
        }
        if let name = object(forInfoDictionaryKey: "CFBundleName") as? String,
            !name.isEmpty
        {
            return name
        }
        return bundleURL.deletingPathExtension().lastPathComponent
    }

    enum ConfigurationError: LocalizedError {
        case missingConfigurationRoot
        case missingValue(key: String)
        case invalidValue(key: String)

        var errorDescription: String? {
            switch self {
            case .missingConfigurationRoot:
                return "Missing Configuration dictionary in Info.plist."
            case .missingValue(let key):
                return
                    "Missing value for key \"\(key)\" in Configuration dictionary."
            case .invalidValue(let key):
                return
                    "Invalid value for key \"\(key)\" in Configuration dictionary."
            }
        }
    }
}

extension Logger {
    func d(_ message: String) {
        self.debug("\(message, privacy: .public)")
    }

    func e(_ message: String) {
        self.error("\(message, privacy: .public)")
    }

    func posixError(_ function: String, _ code: Int32) {
        self.e("\(function): failure (code = \(code))")
    }
}

// log stream --info --debug --style syslog --predicate 'subsystem == "FSKitExt"'
//
// pluginkit -m -A -p com.apple.fskit.fsmodule
//
// mkfile -n 1m /tmp/fskit-rs.dmg
// hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount /tmp/fskit-rs.dmg
//
// mkdir /tmp/vol
// mount -F -t bridgefs /dev/disk22 /tmp/vol
//
// umount /tmp/vol
//
// mv ~/Documents/FSKitBridge.app /Applications/
