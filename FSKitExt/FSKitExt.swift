import Foundation
import FSKit

@main
struct FSKitExt : UnaryFileSystemExtension {
    
    private let logger = Logger(subsystem: "FSKitExt", category: "FSKitExt")
    
    private let socket = Socket.shared
    
    var fileSystem : FSUnaryFileSystem & FSUnaryFileSystemOperations {
        BridgeFS()
    }
    
    init() {
        DispatchQueue.global().async { [self] in
            do {
                try socket.connect(host: "127.0.0.1", port: 35367)
                
                while true {
                    let message = "Hello \(Int.random(in: 100...999))"
                    try socket.sendTypeOne(message: message, count: Int32.random(in: 1...10))
                    Thread.sleep(forTimeInterval: 5)
                }
            } catch {
                logger.debug("❌ TCP client error: \(error)")
            }
        }
    }
}

// mkfile -n 1m /tmp/fskit-rs.dmg
// hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount /tmp/fskit-rs.dmg

// log stream --info --debug --style syslog --predicate 'subsystem == "FSKitExt"'
// umount /tmp/vol
// mount -F -t BridgeFS disk20 /tmp/vol
//
// ~/Library/Application Support/FSKitBridge/fskit.sock
// chmod(socketPath, 0o600)
