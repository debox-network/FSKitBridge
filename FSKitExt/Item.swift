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
        logger.debug("Item: name=\(name.string ?? "", privacy: .public) (id=\(attributes.fileID.rawValue))")
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
    convenience init(_ attributes: ItemAttributes) {
        self.init()
        if attributes.hasUid {
            self.uid = attributes.uid
        }
        if attributes.hasGid {
            self.gid = attributes.gid
        }
        if attributes.hasMode {
            self.mode = attributes.mode
        }
        if attributes.hasType {
            self.type = FSItem.ItemType(rawValue: attributes.type.rawValue)!
        }
        if attributes.hasLinkCount {
            self.linkCount = attributes.linkCount
        }
        if attributes.hasFlags {
            self.flags = attributes.flags
        }
        if attributes.hasSize {
            self.size = attributes.size
        }
        if attributes.hasAllocSize {
            self.allocSize = attributes.allocSize
        }
        if attributes.hasFileID {
            self.fileID = FSItem.Identifier(rawValue: attributes.fileID)!
        }
        if attributes.hasParentID {
            self.parentID = FSItem.Identifier(rawValue: attributes.parentID)!
        }
        if attributes.hasSupportsLimitedXattrs {
            self.supportsLimitedXAttrs = attributes.supportsLimitedXattrs
        }
        if attributes.hasInhibitKernelOffloadedIo {
            self.inhibitKernelOffloadedIO = attributes.inhibitKernelOffloadedIo
        }
        if attributes.hasModifyTime {
            self.modifyTime = timespec(attributes.modifyTime)
        }
        if attributes.hasAddedTime {
            self.addedTime = timespec(attributes.addedTime)
        }
        if attributes.hasChangeTime {
            self.changeTime = timespec(attributes.changeTime)
        }
        if attributes.hasAccessTime {
            self.accessTime = timespec(attributes.accessTime)
        }
        if attributes.hasBirthTime {
            self.birthTime = timespec(attributes.birthTime)
        }
        if attributes.hasBackupTime {
            self.backupTime = timespec(attributes.backupTime)
        }
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
