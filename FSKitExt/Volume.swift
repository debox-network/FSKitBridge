import Foundation
import FSKit
import os

final class Volume: FSVolume {
    
    private let logger = Logger(subsystem: "FSKitExt", category: "Volume")
    
    private let socket = Socket.shared
    
    private let resource: FSResource
    
    private let root: Item = {
        var attrs = ItemAttributes()
        attrs.parentID = 1
        attrs.fileID = 2
        attrs.uid = 0
        attrs.gid = 0
        attrs.linkCount = 1
        attrs.type = .directory
        attrs.mode = UInt32(S_IFDIR | 0b111_000_000)
        attrs.allocSize = 1
        attrs.size = 1
        var item = Response.Item()
        item.attributes = attrs
        item.name = Data("/".utf8)
        return Item(item)
    }()
    
    init(resource: FSResource) {
        self.resource = resource
        
        super.init(
            volumeID: FSVolume.Identifier(uuid: Constants.volumeIdentifier),
            volumeName: FSFileName(string: "Debox")
        )
    }
}

extension Volume: FSVolume.PathConfOperations {
    
    var maximumLinkCount: Int {
        return -1
    }
    
    var maximumNameLength: Int {
        return -1
    }
    
    var restrictsOwnershipChanges: Bool {
        return false
    }
    
    var truncatesLongNames: Bool {
        return false
    }
    
    var maximumXattrSize: Int {
        return Int.max
    }
    
    var maximumFileSize: UInt64 {
        return UInt64.max
    }
}

extension Volume: FSVolume.Operations {
    var supportedVolumeCapabilities: FSVolume.SupportedCapabilities {
        logger.debug("getVolumeCapabilities")
        do {
            let response = try socket.send(content: .getVolumeCapabilities(Request.GetVolumeCapabilities()))
            if case let .volumeCapabilities(capabilities) = response {
                return FSVolume.SupportedCapabilities(capabilities)
            }
        } catch {
            logger.error("getVolumeCapabilities: failure (error = \(error))")
        }
        return FSVolume.SupportedCapabilities()
    }
    
    var volumeStatistics: FSStatFSResult {
        //logger.debug("volumeStatistics")
        
        let result = FSStatFSResult(fileSystemTypeName: "AppFS")
        
        result.blockSize = 1024000
        result.ioSize = 1024000
        result.totalBlocks = 1024000
        result.availableBlocks = 1024000
        result.freeBlocks = 1024000
        result.totalFiles = 1024000
        result.freeFiles = 1024000
        
        return result
    }
    
    
    func activate(options: FSTaskOptions) async throws -> FSItem {
        logger.debug("activate")
        return root
    }
    
    func deactivate(options: FSDeactivateOptions = []) async throws {
        logger.debug("deactivate")
    }
    
    func mount(options: FSTaskOptions) async throws {
        logger.debug("mount")
    }
    
    func unmount() async {
        logger.debug("unmount")
    }
    
    func synchronize(flags: FSSyncFlags) async throws {
        //logger.debug("synchronize")
    }
    
    func attributes(_ desiredAttributes: FSItem.GetAttributesRequest, of item: FSItem) async throws -> FSItem.Attributes {
        guard let item = item as? Item else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
        logger.pubDebug("getAttributes: name = \(item.name.string ?? "") (id = \(item.id))")
        
        var request = Request.GetAttributes()
        request.itemID = item.id
        
        switch try socket.send(content: .getAttributes(request)) {
        case .itemAttributes(let attributes):
            return FSItem.Attributes(attributes)
        case .posixError(let error):
            logger.error("getAttributes: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
    
    func setAttributes(
        _ newAttributes: FSItem.SetAttributesRequest,
        on item: FSItem
    ) async throws -> FSItem.Attributes {
        logger.debug("setItemAttributes: \(item), \(newAttributes)")
        if let item = item as? Item {
            //  mergeAttributes(item.attributes, request: newAttributes)
            return item.attributes
        } else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
    }
    
    func lookupItem(named name: FSFileName, inDirectory directory: FSItem) async throws -> (FSItem, FSFileName) {
        guard let parent = directory as? Item else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
        logger.pubDebug("lookupItem: parent = \(parent.name.string ?? "") (id = \(parent.id)), name = \(name.string ?? "")")
        
        var request = Request.LookupItem()
        request.name = name.data
        request.parentID = parent.id
        
        switch try socket.send(content: .lookupItem(request)) {
        case .item(let item):
            let item = Item(item)
            return (item, item.name)
        case .posixError(let error):
            logger.error("lookupItem: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
    
    func reclaimItem(_ item: FSItem) async throws {
        logger.debug("reclaimItem: \(item)")
    }
    
    func readSymbolicLink(
        _ item: FSItem
    ) async throws -> FSFileName {
        logger.debug("readSymbolicLink: \(item)")
        throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
    }
    
    func createItem(named name: FSFileName, type: FSItem.ItemType, inDirectory directory: FSItem, attributes newAttributes: FSItem.SetAttributesRequest) async throws -> (FSItem, FSFileName) {
        guard let parent = directory as? Item else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
        logger.pubDebug("createItem: parent = \(parent.name.string ?? "") (id = \(parent.id)), name = \(name.string ?? "")")
        
        var request = Request.CreateItem()
        request.name = name.data
        request.type = ItemType(rawValue: type.rawValue)!
        request.parentID = parent.id
        request.attributes = newAttributes.toProto()
        
        switch try socket.send(content: .createItem(request)) {
        case .item(let item):
            let item = Item(item)
            return (item, item.name)
        case .posixError(let error):
            logger.error("createItem: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
    
    func createSymbolicLink(
        named name: FSFileName,
        inDirectory directory: FSItem,
        attributes newAttributes: FSItem.SetAttributesRequest,
        linkContents contents: FSFileName
    ) async throws -> (FSItem, FSFileName) {
        logger.debug("createSymbolicLink: \(name)")
        throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
    }
    
    func createLink(
        to item: FSItem,
        named name: FSFileName,
        inDirectory directory: FSItem
    ) async throws -> FSFileName {
        logger.debug("createLink: \(name)")
        throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
    }
    
    func removeItem(
        _ item: FSItem,
        named name: FSFileName,
        fromDirectory directory: FSItem
    ) async throws {
        logger.debug("remove: \(name)")
        if let item = item as? Item, let directory = directory as? Item {
            //        directory.removeItem(item)
        } else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
    }
    
    func renameItem(
        _ item: FSItem,
        inDirectory sourceDirectory: FSItem,
        named sourceName: FSFileName,
        to destinationName: FSFileName,
        inDirectory destinationDirectory: FSItem,
        overItem: FSItem?
    ) async throws -> FSFileName {
        logger.debug("rename: \(item)")
        throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
    }
    
    func enumerateDirectory(_ directory: FSItem, startingAt cookie: FSDirectoryCookie, verifier: FSDirectoryVerifier, attributes: FSItem.GetAttributesRequest?, packer: FSDirectoryEntryPacker) async throws -> FSDirectoryVerifier {
        guard let item = directory as? Item else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
        logger.pubDebug("enumerateDirectory: name = \(item.name.string ?? "") (id = \(item.id))")
        
        var request = Request.EnumerateDirectory()
        request.itemID = item.id
        request.cookie = cookie.rawValue
        request.verifier = verifier.rawValue
        
        switch try socket.send(content: .enumerateDirectory(request)) {
        case .directoryEntries(let entries):
            for entry in entries.entries {
                let item = Item(entry.item)
                if !packer.packEntry(
                    name: item.name,
                    itemType: item.attributes.type,
                    itemID: item.attributes.fileID,
                    nextCookie: FSDirectoryCookie(entry.nextCookie),
                    attributes: attributes != nil ? item.attributes : nil
                ) {
                    break
                }
            }
            return FSDirectoryVerifier(entries.verifier)
        case .posixError(let error):
            logger.error("enumerateDirectory: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
}

extension Volume: FSVolume.OpenCloseOperations {
    func openItem(_ item: FSItem, modes: FSVolume.OpenModes) async throws {
        guard let item = item as? Item else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
        logger.pubDebug("openItem: name = \(item.name.string ?? "") (id = \(item.id))")
        
        var request = Request.OpenItem()
        request.itemID = item.id
        request.modes = modes.toProto()
        
        switch try socket.send(content: .openItem(request)) {
        case .success(_):
            break
        case .posixError(let error):
            logger.error("openItem: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
    
    func closeItem(_ item: FSItem, modes: FSVolume.OpenModes) async throws {
        guard let item = item as? Item else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
        logger.pubDebug("closeItem: name = \(item.name.string ?? "") (id = \(item.id))")
        
        var request = Request.CloseItem()
        request.itemID = item.id
        request.modes = modes.toProto()
        
        switch try socket.send(content: .closeItem(request)) {
        case .success(_):
            break
        case .posixError(let error):
            logger.error("closeItem: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
}

extension Volume: FSVolume.ReadWriteOperations {
    func read(from item: FSItem, at offset: off_t, length: Int, into buffer: FSMutableFileDataBuffer) async throws -> Int {
        guard let item = item as? Item else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
        logger.pubDebug("read: name = \(item.name.string ?? "") (id = \(item.id))")
        
        var request = Request.Read()
        request.itemID = item.id
        request.offset = offset
        request.length = Int64(length)
        
        switch try socket.send(content: .read(request)) {
        case .buffer(let data):
            return data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                let length = min(buffer.length, data.count)
                _ = buffer.withUnsafeMutableBytes { dst in
                    memcpy(dst.baseAddress, ptr.baseAddress, length)
                }
                return length
            }
        case .posixError(let error):
            logger.error("read: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
    
    func write(contents: Data, to item: FSItem, at offset: off_t) async throws -> Int {
        guard let item = item as? Item else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
        logger.pubDebug("write: name = \(item.name.string ?? "") (id = \(item.id))")
        
        var request = Request.Write()
        request.contents = contents
        request.itemID = item.id
        request.offset = offset
        
        switch try socket.send(content: .write(request)) {
        case .byteCount(let count):
            return Int(count)
        case .posixError(let error):
            logger.error("write: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
}

extension Volume: FSVolume.XattrOperations {
    func xattr(named name: FSFileName, of item: FSItem) async throws -> Data {
        logger.debug("xattr: \(item) - \(name.string ?? "NA")")
        
        if let item = item as? Item {
            return item.xattrs[name] ?? Data()
        } else {
            return Data()
        }
    }
    
    func setXattr(named name: FSFileName, to value: Data?, on item: FSItem, policy: FSVolume.SetXattrPolicy) async throws {
        logger.debug("setXattrOf: \(item)")
        
        if let item = item as? Item {
            item.xattrs[name] = value
        }
    }
    
    func xattrs(of item: FSItem) async throws -> [FSFileName] {
        logger.debug("listXattrs: \(item)")
        
        if let item = item as? Item {
            return Array(item.xattrs.keys)
        } else {
            return []
        }
    }
}

extension FSVolume.SupportedCapabilities {
    convenience init(_ capabilities: VolumeCapabilities) {
        self.init()
        if capabilities.hasSupportsPersistentObjectIds {
            self.supportsPersistentObjectIDs = capabilities.supportsPersistentObjectIds
        }
        if capabilities.hasSupportsSymbolicLinks {
            self.supportsSymbolicLinks = capabilities.supportsSymbolicLinks
        }
        if capabilities.hasSupportsHardLinks {
            self.supportsHardLinks = capabilities.supportsHardLinks
        }
        if capabilities.hasSupportsJournal {
            self.supportsJournal = capabilities.supportsJournal
        }
        if capabilities.hasSupportsActiveJournal {
            self.supportsActiveJournal = capabilities.supportsActiveJournal
        }
        if capabilities.hasDoesNotSupportRootTimes {
            self.doesNotSupportRootTimes = capabilities.doesNotSupportRootTimes
        }
        if capabilities.hasSupportsSparseFiles {
            self.supportsSparseFiles = capabilities.supportsSparseFiles
        }
        if capabilities.hasSupportsZeroRuns {
            self.supportsZeroRuns = capabilities.supportsZeroRuns
        }
        if capabilities.hasSupportsFastStatfs {
            self.supportsFastStatFS = capabilities.supportsFastStatfs
        }
        if capabilities.hasSupports2TbFiles {
            self.supports2TBFiles = capabilities.supports2TbFiles
        }
        if capabilities.hasSupportsOpenDenyModes {
            self.supportsOpenDenyModes = capabilities.supportsOpenDenyModes
        }
        if capabilities.hasSupportsHiddenFiles {
            self.supportsHiddenFiles = capabilities.supportsHiddenFiles
        }
        if capabilities.hasDoesNotSupportVolumeSizes {
            self.doesNotSupportVolumeSizes = capabilities.doesNotSupportVolumeSizes
        }
        if capabilities.hasSupports64BitObjectIds {
            self.supports64BitObjectIDs = capabilities.supports64BitObjectIds
        }
        if capabilities.hasSupportsDocumentID {
            self.supportsDocumentID = capabilities.supportsDocumentID
        }
        if capabilities.hasDoesNotSupportImmutableFiles {
            self.doesNotSupportImmutableFiles = capabilities.doesNotSupportImmutableFiles
        }
        if capabilities.hasDoesNotSupportSettingFilePermissions {
            self.doesNotSupportSettingFilePermissions = capabilities.doesNotSupportSettingFilePermissions
        }
        if capabilities.hasSupportsSharedSpace {
            self.supportsSharedSpace = capabilities.supportsSharedSpace
        }
        if capabilities.hasSupportsVolumeGroups {
            self.supportsVolumeGroups = capabilities.supportsVolumeGroups
        }
        if capabilities.hasCaseFormat {
            self.caseFormat = FSVolume.CaseFormat(rawValue: capabilities.caseFormat.rawValue)!
        }
    }
}

extension FSVolume.OpenModes {
    func toProto() -> [OpenMode] {
        var modes: [OpenMode] = []
        if self.rawValue & UInt(OpenMode.read.rawValue) != 0 { modes.append(.read) }
        if self.rawValue & UInt(OpenMode.write.rawValue) != 0 { modes.append(.write) }
        return modes
    }
}
