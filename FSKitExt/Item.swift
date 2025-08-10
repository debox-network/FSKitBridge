import Foundation
import FSKit
import SwiftProtobuf

final class Item: FSItem {
    
    private let logger = Logger(subsystem: "FSKitExt", category: "Item")
    
    private static var id: UInt64 = FSItem.Identifier.rootDirectory.rawValue + 1
    static func getNextID() -> UInt64 {
        let current = id
        id += 1
        return current
    }
    
    let name: FSFileName
    private(set) var attributes: FSItem.Attributes
    
    //let id = Item.getNextID()
    
    var xattrs: [FSFileName: Data] = [:]
    var data: Data?
    
    private(set) var children: [FSFileName: Item] = [:]
    
    var id: UInt64 { attributes.fileID.rawValue }
    
    init(name: FSFileName, attributes: FSItem.Attributes) {
        logger.debug("Item: \(name.string ?? "-", privacy: .public)")
        self.name = name
        self.attributes = attributes
    }
    
    func addItem(_ item: Item) {
        children[item.name] = item
    }
    
    func removeItem(_ item: Item) {
        children[item.name] = nil
    }
}

extension FSItem.Attributes {
    convenience init(_ attrs: Response.ItemAttributes) {
        self.init()
        self.uid = attrs.uid
        self.gid = attrs.gid
        self.mode = attrs.mode
        self.type = FSItem.ItemType(rawValue: attrs.type.rawValue)!
        self.linkCount = attrs.linkCount
        self.flags = attrs.flags
        self.size = attrs.size
        self.allocSize = attrs.allocSize
        self.fileID = FSItem.Identifier(rawValue: attrs.fileID)!
        self.parentID = FSItem.Identifier(rawValue: attrs.parentID)!
        self.supportsLimitedXAttrs = attrs.supportsLimitedXattrs
        self.inhibitKernelOffloadedIO = attrs.inhibitKernelOffloadedIo
        self.modifyTime = timespec(attrs.modifyTime)
        self.addedTime = timespec(attrs.addedTime)
        self.changeTime = timespec(attrs.changeTime)
        self.accessTime = timespec(attrs.accessTime)
        self.birthTime = timespec(attrs.birthTime)
        self.backupTime = timespec(attrs.backupTime)
    }
}

extension timespec {
    init(_ ts: Google_Protobuf_Timestamp) {
        self.init(
            tv_sec: Int(ts.seconds),
            tv_nsec: Int(ts.nanos)
        )
    }
    
    /// Convert a timespec to a protobuf timestamp
    //    func toProto() -> Google_Protobuf_Timestamp {
    //        var ts = Google_Protobuf_Timestamp()
    //        ts.seconds = Int64(self.tv_sec)
    //        ts.nanos   = Int32(self.tv_nsec)
    //        return ts
    //    }
}
