import Darwin
import FSKit
import Foundation
import SwiftProtobuf

// Seconds for 1904-01-01 00:00:00 UTC in Unix epoch (1970-based)
private let HFSUnixEpochOffset: Int = -2_082_844_800

final class Item: FSItem {
    private let lock = NSLock()
    private var _name: FSFileName
    private var _attributes: FSItem.Attributes

    var name: FSFileName {
        lock.withLock { _name }
    }

    var attributes: FSItem.Attributes {
        lock.withLock { _attributes }
    }

    var id: UInt64 {
        lock.withLock { _attributes.fileID.rawValue }
    }

    init(_ item: Pb_Item) {
        _name = FSFileName(data: item.name)
        _attributes = FSItem.Attributes(item.attributes)
    }

    func updateName(name: Data) {
        let name = FSFileName(data: name)
        lock.withLock {
            _name = name
        }
    }

    func updateAttributes(attributes: Pb_ItemAttributes) {
        let attributes = FSItem.Attributes(attributes)
        lock.withLock {
            _attributes = attributes
        }
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
        if attributes.hasType,
            let type = FSItem.ItemType(rawValue: attributes.type.rawValue)
        {
            self.type = type

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
        if attributes.hasFileID,
            let fileID = FSItem.Identifier(rawValue: attributes.fileID)
        {
            self.fileID = fileID

        }
        if attributes.hasParentID,
            let parentID = FSItem.Identifier(rawValue: attributes.parentID)
        {
            self.parentID = parentID

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
        if self.isValid(.gid) {
            attributes.gid = self.gid
        }
        if self.isValid(.mode) {
            attributes.mode = self.mode
        }
        if self.isValid(.type) {
            attributes.type = self.type.toProto()
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

extension FSItem.ItemType {
    func toProto() -> Pb_ItemType {
        return Pb_ItemType(rawValue: self.rawValue)
            ?? .UNRECOGNIZED(self.rawValue)
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
        let norm = normalize()
        ts.seconds = Int64(norm.tv_sec)
        ts.nanos = Int32(norm.tv_nsec)
        return ts
    }

    private func normalize() -> timespec {
        if self.tv_sec == HFSUnixEpochOffset {
            var now = timespec()
            clock_gettime(CLOCK_REALTIME, &now)
            return now
        }
        return self
    }
}
