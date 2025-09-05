import Foundation
import FSKit

@main
struct FSKitExt : UnaryFileSystemExtension {
    var fileSystem : FSUnaryFileSystem & FSUnaryFileSystemOperations {
        BridgeFS()
    }
}

extension Logger {
    func d(_ message: String) {
        self.debug("\(message, privacy: .public)")
    }
    
    func e(_ message: String) {
        self.error("\(message, privacy: .public)")
    }
    
    func posixError(_ function: String, _ error: Pb_PosixError) {
        self.e("\(function): failure (error = \(error.code))")
    }
}

// log stream --info --debug --style syslog --predicate 'subsystem == "FSKitExt"'
//
// mkfile -n 1m /tmp/fskit-rs.dmg
// hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount /tmp/fskit-rs.dmg
//
// mkdir /tmp/vol
// mount -F -t BridgeFS disk20 /tmp/vol
//
// umount /tmp/vol
//
// mv ~/Documents/FSKitBridge.app /Applications/
