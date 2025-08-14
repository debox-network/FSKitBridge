import Foundation
import FSKit
import os

final class Volume: FSVolume {
    
    private let logger = Logger(subsystem: "FSKitExt", category: "Volume")
    
    private let socket = Socket.shared
    
    private let resource: FSResource
    
    private let root: Item = {
        let attrs = FSItem.Attributes()
        attrs.parentID = .parentOfRoot
        attrs.fileID = .rootDirectory
        attrs.uid = 0
        attrs.gid = 0
        attrs.linkCount = 1
        attrs.type = .directory
        attrs.mode = UInt32(S_IFDIR | 0b111_000_000)
        attrs.allocSize = 1
        attrs.size = 1
        return Item(name: FSFileName(string: "/"), attributes: attrs)
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
        logger.debug("GetVolumeCapabilities")
        do {
            let response = try socket.send(content: .getVolumeCapabilities(Request.GetVolumeCapabilities()))
            if case let .getVolumeCapabilities(msg) = response {
                return FSVolume.SupportedCapabilities(msg.capabilities)
            }
        } catch {
            logger.error("Request failed: \(error)")
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
    
    func attributes(
        _ desiredAttributes: FSItem.GetAttributesRequest,
        of item: FSItem
    ) async throws -> FSItem.Attributes {
        guard let item = item as? Item else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        logger.debug("getAttributes: name = \(item.name.string ?? "", privacy: .public) (id = \(item.id))")
        
        var request = Request.GetAttributes()
        request.fileID = item.id
        
        let response = try socket.send(content: .getAttributes(request))
        switch response {
        case .getAttributes(let msg):
            logger.debug("getAttributes: success (id = \(msg.attributes.fileID, privacy: .public))")
            return FSItem.Attributes(msg.attributes)
        case .posixError(let error):
            logger.debug("getAttributes: failure (error = \(error.code))")
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
    
    func lookupItem(
        named name: FSFileName,
        inDirectory directory: FSItem
    ) async throws -> (FSItem, FSFileName) {
        guard let parent = directory as? Item else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
        logger.debug("lookupItem: parent = \(parent.name.string ?? "", privacy: .public) (id = \(parent.id)), name = \(name.string ?? "", privacy: .public)")
        
        var request = Request.LookupItem()
        request.name = name.data
        request.parentID = parent.id
        
        let response = try socket.send(content: .lookupItem(request))
        switch response {
        case .lookupItem(let msg):
            logger.debug("lookupItem: success (id = \(msg.attributes.fileID, privacy: .public))")
            let item = Item(name: FSFileName(data: msg.name), attributes: FSItem.Attributes(msg.attributes))
            return (item, item.name)
        case .posixError(let error):
            logger.debug("lookupItem: failure (error = \(error.code))")
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
    
    func createItem(
        named name: FSFileName,
        type: FSItem.ItemType,
        inDirectory directory: FSItem,
        attributes newAttributes: FSItem.SetAttributesRequest
    ) async throws -> (FSItem, FSFileName) {
        guard let parent = directory as? Item else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
        logger.debug("createItem: parent = \(parent.name.string ?? "", privacy: .public) (id = \(parent.id)), name = \(name.string ?? "", privacy: .public)")
        
        var request = Request.CreateItem()
        request.name = name.data
        request.type = ItemType(rawValue: type.rawValue)!
        request.parentID = parent.id
        request.attributes = newAttributes.toProto()
        
        let response = try socket.send(content: .createItem(request))
        switch response {
        case .createItem(let msg):
            logger.debug("createItem: success (id = \(msg.attributes.fileID, privacy: .public))")
            let item = Item(name: FSFileName(data: msg.name), attributes: FSItem.Attributes(msg.attributes))
            return (item, item.name)
        case .posixError(let error):
            logger.debug("createItem: failure (error = \(error.code))")
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
    
    func enumerateDirectory(
        _ directory: FSItem,
        startingAt cookie: FSDirectoryCookie,
        verifier: FSDirectoryVerifier,
        attributes: FSItem.GetAttributesRequest?,
        packer: FSDirectoryEntryPacker
    ) async throws -> FSDirectoryVerifier {
        logger.debug("enumerateDirectory: \(directory)")
        
        guard let directory = directory as? Item else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
        
        logger.debug("- enumerateDirectory - \(directory.name)")
        /*
         for (idx, item) in directory.children.values.enumerated() {
         let isLast = (idx == directory.children.count - 1)
         
         let v = packer.packEntry(
         name: item.name,
         itemType: item.attributes.type,
         itemID: item.attributes.fileID,
         nextCookie: FSDirectoryCookie(UInt64(idx)),
         attributes: attributes != nil ? item.attributes : nil
         )
         
         logger.debug("-- V: \(v) - \(item.name)")
         }
         */
        return FSDirectoryVerifier(0)
    }
}

extension Volume: FSVolume.OpenCloseOperations {
    func openItem(_ item: FSItem, modes: FSVolume.OpenModes) async throws {
        guard let item = item as? Item else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        logger.debug("openItem: name = \(item.name.string ?? "", privacy: .public) (id = \(item.id))")
        
        var request = Request.OpenItem()
        request.attributes = item.attributes.toProto()
        request.modes = modes.toProto()
        
        let response = try socket.send(content: .openItem(request))
        switch response {
        case .success(_):
            logger.debug("openItem: success (id = \(item.id, privacy: .public))")
        case .posixError(let error):
            logger.debug("openItem: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
    
    func closeItem(_ item: FSItem, modes: FSVolume.OpenModes) async throws {
        guard let item = item as? Item else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        logger.debug("closeItem: name = \(item.name.string ?? "", privacy: .public) (id = \(item.id))")
        
        var request = Request.CloseItem()
        request.attributes = item.attributes.toProto()
        request.modes = modes.toProto()
        
        let response = try socket.send(content: .closeItem(request))
        switch response {
        case .success(_):
            logger.debug("closeItem: success (id = \(item.id, privacy: .public))")
        case .posixError(let error):
            logger.debug("closeItem: failure (error = \(error.code))")
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

extension Volume: FSVolume.ReadWriteOperations {
    
    func read(from item: FSItem, at offset: off_t, length: Int, into buffer: FSMutableFileDataBuffer) async throws -> Int {
        logger.debug("read: \(item)")
        
        var bytesRead = 0
        
        if let item = item as? Item, let data = item.data {
            bytesRead = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                let length = min(buffer.length, data.count)
                _ = buffer.withUnsafeMutableBytes { dst in
                    memcpy(dst.baseAddress, ptr.baseAddress, length)
                }
                return length
            }
        }
        
        return bytesRead
    }
    
    func write(contents: Data, to item: FSItem, at offset: off_t) async throws -> Int {
        logger.debug("write: \(item) - \(offset)")
        
        if let item = item as? Item {
            logger.debug("- write: \(item.name)")
            item.data = contents
            item.attributes.size = UInt64(contents.count)
            item.attributes.allocSize = UInt64(contents.count)
        }
        
        return contents.count
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
