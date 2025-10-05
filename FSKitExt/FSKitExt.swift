import FSKit
import Foundation

@main
struct FSKitExt: UnaryFileSystemExtension {
    var fileSystem: FSUnaryFileSystem & FSUnaryFileSystemOperations {
        BridgeFS()
    }
}

extension Bundle {
    var serverPort: Int? {
        guard
            let attrs = infoDictionary?["Configuration"]
                as? [String: Any],
            let value = attrs["serverPort"] as? String
        else { return nil }
        return Int(value)
    }

    var fsShortName: String? {
        guard
            let attrs = infoDictionary?["EXAppExtensionAttributes"]
                as? [String: Any],
            let value = attrs["FSShortName"] as? String
        else { return nil }
        return value
    }

    var fsSubType: Int? {
        guard
            let attrs = infoDictionary?["EXAppExtensionAttributes"]
                as? [String: Any],
            let pers = attrs["FSPersonalities"]
                as? [String: Any],
            let value = pers["FSSubType"] as? Int
        else { return nil }
        return value
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
