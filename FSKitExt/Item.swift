import Foundation
import FSKit
import SwiftProtobuf

final class Item: FSItem {
    
    private(set) var name: FSFileName
    private(set) var attributes: FSItem.Attributes
    
    var id: UInt64 { attributes.fileID.rawValue }
    
    init(_ item: Pb_Item) {
        self.name = FSFileName(data: item.name)
        self.attributes = FSItem.Attributes(item.attributes)
    }
    
    func updateName(name: Data) {
        self.name = FSFileName(data: name)
    }
    
    func updateAttributes(attributes: Pb_ItemAttributes) {
        self.attributes = FSItem.Attributes(attributes)
    }
}

extension FSItem.Attributes {
    convenience init(_ attributes: Pb_ItemAttributes) {
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
    
    func toProto() -> Pb_ItemAttributes {
        var attributes = Pb_ItemAttributes()
        if self.isValid(.uid) {
            attributes.uid = self.uid
        }
        if self.isValid(.gid)  {
            attributes.gid = self.gid
        }
        if self.isValid(.mode) {
            attributes.mode = self.mode
        }
        if self.isValid(.type) {
            attributes.type = Pb_ItemType(rawValue: self.type.rawValue)!
        }
        if self.isValid(.linkCount) {
            attributes.linkCount = self.linkCount
        }
        if self.isValid(.flags) {
            attributes.flags = self.flags
        }
        if self.isValid(.size) {
            attributes.size = self.size
        }
        if self.isValid(.allocSize) {
            attributes.allocSize = self.allocSize
        }
        if self.isValid(.fileID) {
            attributes.fileID = self.fileID.rawValue
        }
        if self.isValid(.parentID) {
            attributes.parentID = self.parentID.rawValue
        }
        if self.isValid(.supportsLimitedXAttrs) {
            attributes.supportsLimitedXattrs = self.supportsLimitedXAttrs
        }
        if self.isValid(.inhibitKernelOffloadedIO) {
            attributes.inhibitKernelOffloadedIo = self.inhibitKernelOffloadedIO
        }
        if self.isValid(.modifyTime) {
            attributes.modifyTime = self.modifyTime.toProto()
        }
        if self.isValid(.addedTime) {
            attributes.addedTime = self.addedTime.toProto()
        }
        if self.isValid(.changeTime) {
            attributes.changeTime = self.changeTime.toProto()
        }
        if self.isValid(.accessTime) {
            attributes.accessTime = self.accessTime.toProto()
        }
        if self.isValid(.birthTime) {
            attributes.birthTime = self.birthTime.toProto()
        }
        if self.isValid(.backupTime) {
            attributes.backupTime = self.backupTime.toProto()
        }
        return attributes
    }
}

extension timespec {
    init(_ ts: Google_Protobuf_Timestamp) {
        self.init(
            tv_sec: Int(ts.seconds),
            tv_nsec: Int(ts.nanos)
        )
    }
    
    func toProto() -> Google_Protobuf_Timestamp {
        var ts = Google_Protobuf_Timestamp()
        ts.seconds = Int64(self.tv_sec)
        ts.nanos = Int32(self.tv_nsec)
        return ts
    }
}
