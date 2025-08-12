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
            let response = try socket.send(content: .getVolumeCapabilities(GetVolumeCapabilities()))
            if case let .volumeCapabilities(capabilities) = response {
                return FSVolume.SupportedCapabilities(capabilities)
            }
        } catch {
            logger.error("Request failed: \(error)")
        }
        return FSVolume.SupportedCapabilities()
    }
    
    var volumeStatistics: FSStatFSResult {
        logger.debug("volumeStatistics")
        
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
        logger.debug("synchronize")
    }
    
    func attributes(
        _ desiredAttributes: FSItem.GetAttributesRequest,
        of item: FSItem
    ) async throws -> FSItem.Attributes {
        guard let item = item as? Item else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        logger.debug("GetAttributes: name=\(item.name.string ?? "", privacy: .public) (id=\(item.id))")
        
        var request = GetAttributes()
        request.fileID = item.id
        
        let response = try socket.send(content: .getAttributes(request))
        switch response {
        case .itemAttributes(let attrs):
            return FSItem.Attributes(attrs)
        case .posixError(let error):
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
        logger.debug("LookupItem: parent=\(parent.name.string ?? "", privacy: .public) (id=\(parent.id)), name=\(name.string ?? "", privacy: .public)")
        
        var request = LookupItem()
        request.parentID = parent.id
        request.name = name.data
        
        let response = try socket.send(content: .lookupItem(request))
        switch response {
        case .itemAttributes(let attrs):
            let item = Item(name: name, attributes: FSItem.Attributes(attrs))
            return (item, name)
        case .posixError(let error):
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
        logger.debug("createItem: \(String(describing: name.string)) - \(newAttributes.mode)")
        
        guard let directory = directory as? Item else {
            throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
        }
        
        let item = Item(name: name, attributes: newAttributes)
        //        mergeAttributes(item.attributes, request: newAttributes)
        //        item.attributes.parentID = directory.attributes.fileID
        //        item.attributes.type = type
        //        directory.addItem(item)
        
        return (item, name)
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
            directory.removeItem(item)
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
        
        return FSDirectoryVerifier(0)
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

extension Volume: FSVolume.OpenCloseOperations {
    
    func openItem(_ item: FSItem, modes: FSVolume.OpenModes) async throws {
        if let item = item as? Item {
            logger.debug("open: \(item.name)")
        } else {
            logger.debug("open: \(item)")
        }
    }
    
    func closeItem(_ item: FSItem, modes: FSVolume.OpenModes) async throws {
        if let item = item as? Item {
            logger.debug("close: \(item.name)")
        } else {
            logger.debug("close: \(item)")
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
