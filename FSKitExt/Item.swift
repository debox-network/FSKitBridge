import Darwin
import FSKit
import Foundation
import SwiftProtobuf

// Seconds for 1904-01-01 00:00:00 UTC in Unix epoch (1970-based)
private let HFSUnixEpochOffset: Int = -2_082_844_800

final class Item: FSItem {
    private let lock = NSLock()
    private let _id: UInt64
    private var _entryID: UInt64
    private var _name: FSFileName
    private var _attributes: FSItem.Attributes

    var id: UInt64 {
        _id
    }

    var entryID: UInt64 {
        lock.withLock { _entryID }
    }

    var parentID: UInt64 {
        lock.withLock { _attributes.parentID.rawValue }
    }

    var name: FSFileName {
        lock.withLock { _name }
    }

    var nameData: Data {
        lock.withLock { _name.data }
    }

    var attributes: FSItem.Attributes {
        lock.withLock { _attributes }
    }

    init(id: UInt64, item: Pb_Item, parentID: UInt64) {
        _id = id
        _entryID = item.attributes.fileID
        _name = FSFileName(data: item.name)
        _attributes = FSItem.Attributes(
            item.attributes,
            fileID: id,
            parentID: parentID
        )
    }

    func updateName(name: Data) {
        let name = FSFileName(data: name)
        lock.withLock {
            _name = name
        }
    }

    func update(item: Pb_Item, entryID: UInt64, parentID: UInt64) {
        let name = FSFileName(data: item.name)
        let attrs = FSItem.Attributes(
            item.attributes,
            fileID: _id,
            parentID: parentID
        )
        lock.withLock {
            _entryID = entryID
            _name = name
            _attributes = attrs
        }
    }

    func updateAttributes(attrs: Pb_ItemAttributes) {
        let attrs = FSItem.Attributes(attrs, fileID: _id, parentID: parentID)
        lock.withLock {
            _attributes = attrs
        }
    }

    func updateDirectoryEntry(name: Data, parentID: UInt64) {
        let name = FSFileName(data: name)
        lock.withLock {
            _name = name
            if let parent = FSItem.Identifier(rawValue: parentID) {
                _attributes.parentID = parent
            }
        }
    }
}

extension FSItem.Attributes {
    convenience init(
        _ attrs: Pb_ItemAttributes,
        fileID: UInt64? = nil,
        parentID: UInt64? = nil
    ) {
        self.init()
        if attrs.hasUid {
            uid = attrs.uid
        }
        if attrs.hasGid {
            gid = attrs.gid
        }
        if attrs.hasMode {
            mode = attrs.mode
        }
        if attrs.hasType,
            let type = FSItem.ItemType(rawValue: attrs.type.rawValue)
        {
            self.type = type
        }
        if attrs.hasLinkCount {
            linkCount = attrs.linkCount
        }
        if attrs.hasFlags {
            flags = attrs.flags
        }
        if attrs.hasSize {
            size = attrs.size
        }
        if attrs.hasAllocSize {
            allocSize = attrs.allocSize
        }
        if let fileID, let fileID = FSItem.Identifier(rawValue: fileID) {
            self.fileID = fileID
        } else if attrs.hasFileID,
            let fileID = FSItem.Identifier(rawValue: attrs.fileID)
        {
            self.fileID = fileID
        }
        if let parentID,
            let parentID = FSItem.Identifier(rawValue: parentID)
        {
            self.parentID = parentID
        } else if attrs.hasParentID,
            let parentID = FSItem.Identifier(rawValue: attrs.parentID)
        {
            self.parentID = parentID
        }
        if attrs.hasSupportsLimitedXattrs {
            supportsLimitedXAttrs = attrs.supportsLimitedXattrs
        }
        if attrs.hasInhibitKernelOffloadedIo {
            inhibitKernelOffloadedIO = attrs.inhibitKernelOffloadedIo
        }
        if attrs.hasModifyTime {
            modifyTime = timespec(attrs.modifyTime)
        }
        if attrs.hasAddedTime {
            addedTime = timespec(attrs.addedTime)
        }
        if attrs.hasChangeTime {
            changeTime = timespec(attrs.changeTime)
        }
        if attrs.hasAccessTime {
            accessTime = timespec(attrs.accessTime)
        }
        if attrs.hasBirthTime {
            birthTime = timespec(attrs.birthTime)
        }
        if attrs.hasBackupTime {
            backupTime = timespec(attrs.backupTime)
        }
    }

    func toProto() -> Pb_ItemAttributes {
        var attrs = Pb_ItemAttributes()
        if isValid(.uid) {
            attrs.uid = uid
        }
        if isValid(.gid) {
            attrs.gid = gid
        }
        if isValid(.mode) {
            attrs.mode = mode
        }
        if isValid(.type) {
            attrs.type = type.toProto()
        }
        if isValid(.linkCount) {
            attrs.linkCount = linkCount
        }
        if isValid(.flags) {
            attrs.flags = flags
        }
        if isValid(.size) {
            attrs.size = size
        }
        if isValid(.allocSize) {
            attrs.allocSize = allocSize
        }
        if isValid(.fileID) {
            attrs.fileID = fileID.rawValue
        }
        if isValid(.parentID) {
            attrs.parentID = parentID.rawValue
        }
        if isValid(.supportsLimitedXAttrs) {
            attrs.supportsLimitedXattrs = supportsLimitedXAttrs
        }
        if isValid(.inhibitKernelOffloadedIO) {
            attrs.inhibitKernelOffloadedIo = inhibitKernelOffloadedIO
        }
        if isValid(.modifyTime) {
            attrs.modifyTime = modifyTime.toProto()
        }
        if isValid(.addedTime) {
            attrs.addedTime = addedTime.toProto()
        }
        if isValid(.changeTime) {
            attrs.changeTime = changeTime.toProto()
        }
        if isValid(.accessTime) {
            attrs.accessTime = accessTime.toProto()
        }
        if isValid(.birthTime) {
            attrs.birthTime = birthTime.toProto()
        }
        if isValid(.backupTime) {
            attrs.backupTime = backupTime.toProto()
        }
        return attrs
    }
}

extension FSItem.ItemType {
    func toProto() -> Pb_ItemType {
        return Pb_ItemType(rawValue: rawValue) ?? .UNRECOGNIZED(rawValue)
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
