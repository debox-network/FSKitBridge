import Foundation
import FSKit
import os

final class Volume: FSVolume {
    
    private let logger = Logger(subsystem: "FSKitExt", category: "Volume")
    
    private let socket = Socket.shared
    
    private let resource: FSResource
    
    private var pathConfOperations: Pb_PathConfOperations!
    private var volumeCapabilities: Pb_VolumeCapabilities!
    private var xattrOperations: Pb_XattrOperations!
    
    private var items: [UInt64: Item] = [:]
    
    private let root: Item = {
        var attrs = Pb_ItemAttributes()
        attrs.parentID = 1
        attrs.fileID = 2
        attrs.uid = 0
        attrs.gid = 0
        attrs.linkCount = 1
        attrs.type = .directory
        attrs.mode = UInt32(S_IFDIR | 0b111_000_000)
        attrs.allocSize = 1
        attrs.size = 1
        var item = Pb_Response.Item()
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
    
    func load() {
        pathConfOperations = getPathConfOperations()
        volumeCapabilities = getVolumeCapabilities()
        xattrOperations = getXattrOperations()
    }
    
    private func getPathConfOperations() -> Pb_PathConfOperations {
        logger.debug("getPathConfOperations")
        do {
            let response = try socket.send(content: .getPathConfOperations(Pb_Request.GetPathConfOperations()))
            if case let .pathConfOperations(value) = response {
                return value
            }
        } catch {
            logger.error("getPathConfOperations: failure (error = \(error))")
        }
        return Pb_PathConfOperations()
    }
    
    private func getVolumeCapabilities() -> Pb_VolumeCapabilities {
        logger.debug("getVolumeCapabilities")
        do {
            let response = try socket.send(content: .getVolumeCapabilities(Pb_Request.GetVolumeCapabilities()))
            if case let .volumeCapabilities(value) = response {
                return value
            }
        } catch {
            logger.error("getVolumeCapabilities: failure (error = \(error))")
        }
        return Pb_VolumeCapabilities()
    }
    
    private func getXattrOperations() -> Pb_XattrOperations {
        logger.debug("getXattrOperations")
        do {
            let response = try socket.send(content: .getXattrOperations(Pb_Request.GetXattrOperations()))
            if case let .xattrOperations(value) = response {
                return value
            }
        } catch {
            logger.error("getXattrOperations: failure (error = \(error))")
        }
        return Pb_XattrOperations()
    }
}

extension Volume: FSVolume.PathConfOperations {
    
    var maximumLinkCount: Int {
        Int(pathConfOperations.maximumLinkCount)
    }
    
    var maximumNameLength: Int {
        Int(pathConfOperations.maximumNameLength)
    }
    
    var restrictsOwnershipChanges: Bool {
        pathConfOperations.restrictsOwnershipChanges
    }
    
    var truncatesLongNames: Bool {
        pathConfOperations.truncatesLongNames
    }
    
    var maximumXattrSize: Int {
        if pathConfOperations.hasMaximumXattrSize {
            Int(pathConfOperations.maximumXattrSize)
        } else {
            Int.max
        }
    }
    
    var maximumXattrSizeInBits: Int {
        if pathConfOperations.hasMaximumXattrSizeInBits {
            Int(pathConfOperations.maximumXattrSizeInBits)
        } else {
            Int.max
        }
    }
    
    var maximumFileSize: UInt64 {
        if pathConfOperations.hasMaximumFileSize {
            pathConfOperations.maximumFileSize
        } else {
            UInt64.max
        }
    }
    
    var maximumFileSizeInBits: Int {
        if pathConfOperations.hasMaximumFileSizeInBits {
            Int(pathConfOperations.maximumFileSizeInBits)
        } else {
            Int.max
        }
    }
}

extension Volume: FSVolume.Operations {
    var supportedVolumeCapabilities: FSVolume.SupportedCapabilities {
        FSVolume.SupportedCapabilities(volumeCapabilities)
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
        logger.pubDebug("getAttributes: \(item.name.string ?? "") (id = \(item.id))")
        
        var request = Pb_Request.GetAttributes()
        request.itemID = item.id
        
        switch try socket.send(content: .getAttributes(request)) {
        case .itemAttributes(let attributes):
            item.updateAttributes(attributes: attributes)
            return item.attributes
        case .posixError(let error):
            logger.error("getAttributes: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
    
    func setAttributes(_ newAttributes: FSItem.SetAttributesRequest, on item: FSItem) async throws -> FSItem.Attributes {
        let item = item as! Item
        logger.pubDebug("setAttributes: \(item.name.string ?? "") (id = \(item.id))")
        
        var request = Pb_Request.SetAttributes()
        request.attributes = newAttributes.toProto()
        request.itemID = item.id
        
        switch try socket.send(content: .setAttributes(request)) {
        case .itemAttributes(let attributes):
            return FSItem.Attributes(attributes)
        case .posixError(let error):
            logger.error("setAttributes: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
    
    func lookupItem(named name: FSFileName, inDirectory directory: FSItem) async throws -> (FSItem, FSFileName) {
        let directory = directory as! Item
        logger.pubDebug("lookupItem: \(directory.name.string ?? "") (id = \(directory.id)), name = \(name.string ?? "")")
        
        var request = Pb_Request.LookupItem()
        request.name = name.data
        request.directoryID = directory.id
        
        switch try socket.send(content: .lookupItem(request)) {
        case .item(let item):
            if let item = items[item.attributes.fileID] {
                return (item, item.name)
            } else {
                let item = Item(item)
                items[item.id] = item
                return (item, item.name)
            }
        case .posixError(let error):
            logger.error("lookupItem: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
    
    func reclaimItem(_ item: FSItem) async throws {
        let item = item as! Item
        logger.pubDebug("reclaimItem: \(item.name.string ?? "") (id = \(item.id))")
        
        var request = Pb_Request.ReclaimItem()
        request.itemID = item.id
        
        switch try socket.send(content: .reclaimItem(request)) {
        case .success(_):
            items.removeValue(forKey: item.id)
            return
        case .posixError(let error):
            logger.error("reclaimItem: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
    
    func readSymbolicLink(_ item: FSItem) async throws -> FSFileName {
        let item = item as! Item
        logger.pubDebug("readSymbolicLink: \(item.name.string ?? "") (id = \(item.id))")
        
        var request = Pb_Request.ReadSymbolicLink()
        request.itemID = item.id
        
        switch try socket.send(content: .readSymbolicLink(request)) {
        case .data(let data):
            return FSFileName(data: data)
        case .posixError(let error):
            logger.error("readSymbolicLink: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
    
    func createItem(named name: FSFileName, type: FSItem.ItemType, inDirectory directory: FSItem, attributes newAttributes: FSItem.SetAttributesRequest) async throws -> (FSItem, FSFileName) {
        let directory = directory as! Item
        logger.pubDebug("createItem: \(directory.name.string ?? "") (id = \(directory.id)), name = \(name.string ?? "")")
        
        var request = Pb_Request.CreateItem()
        request.name = name.data
        request.type = Pb_ItemType(rawValue: type.rawValue)!
        request.directoryID = directory.id
        request.attributes = newAttributes.toProto()
        
        switch try socket.send(content: .createItem(request)) {
        case .item(let item):
            let item = Item(item)
            items[item.id] = item
            return (item, item.name)
        case .posixError(let error):
            logger.error("createItem: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
    
    func createSymbolicLink(named name: FSFileName, inDirectory directory: FSItem, attributes newAttributes: FSItem.SetAttributesRequest, linkContents contents: FSFileName) async throws -> (FSItem, FSFileName) {
        let directory = directory as! Item
        logger.pubDebug("createSymbolicLink: \(directory.name.string ?? "") (id = \(directory.id)), name = \(name.string ?? "")")
        
        var request = Pb_Request.CreateSymbolicLink()
        request.name = name.data
        request.directoryID = directory.id
        request.newAttributes = newAttributes.toProto()
        request.contents = contents.data
        
        switch try socket.send(content: .createSymbolicLink(request)) {
        case .item(let item):
            let item = Item(item)
            items[item.id] = item
            return (item, item.name)
        case .posixError(let error):
            logger.error("createSymbolicLink: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
    
    func createLink(
        to item: FSItem,
        named name: FSFileName,
        inDirectory directory: FSItem
    ) async throws -> FSFileName {
        logger.debug("createLink: \(name)")
        throw fs_errorForPOSIXError(POSIXError.EIO.rawValue)
    }
    
    func removeItem(_ item: FSItem, named name: FSFileName, fromDirectory directory: FSItem) async throws {
        let item = item as! Item
        let directory = directory as! Item
        logger.pubDebug("removeItem: \(item.name.string ?? "") (id = \(item.id))")
        
        var request = Pb_Request.RemoveItem()
        request.itemID = item.id
        request.name = name.data
        request.directoryID = directory.id
        
        switch try socket.send(content: .removeItem(request)) {
        case .success(_):
            return
        case .posixError(let error):
            logger.error("removeItem: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
    
    func renameItem(_ item: FSItem, inDirectory sourceDirectory: FSItem, named sourceName: FSFileName, to destinationName: FSFileName, inDirectory destinationDirectory: FSItem, overItem: FSItem?) async throws -> FSFileName {
        let item = item as! Item
        let sourceDirectory = sourceDirectory as! Item
        let destinationDirectory = destinationDirectory as! Item
        let overItem = overItem as? Item
        logger.pubDebug("renameItem: \(item.name.string ?? "") -> \(destinationName.string ?? "") (id = \(item.id))")
        
        var request = Pb_Request.RenameItem()
        request.itemID = item.id
        request.sourceDirectoryID = sourceDirectory.id
        request.sourceName = item.name.data
        request.destinationName = destinationName.data
        request.destinationDirectoryID = destinationDirectory.id
        if overItem != nil {
            request.overItemID = overItem!.id
        }
        
        switch try socket.send(content: .renameItem(request)) {
        case .data(let data):
            item.updateName(name: data)
            return item.name
        case .posixError(let error):
            logger.error("renameItem: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
    
    func enumerateDirectory(_ directory: FSItem, startingAt cookie: FSDirectoryCookie, verifier: FSDirectoryVerifier, attributes: FSItem.GetAttributesRequest?, packer: FSDirectoryEntryPacker) async throws -> FSDirectoryVerifier {
        let directory = directory as! Item
        logger.pubDebug("enumerateDirectory: \(directory.name.string ?? "") (id = \(directory.id))")
        
        var request = Pb_Request.EnumerateDirectory()
        request.directoryID = directory.id
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

extension Volume: FSVolume.XattrOperations {
    var xattrOperationsInhibited: Bool {
        get {
            if xattrOperations.hasXattrOperationsInhibited {
                xattrOperations.xattrOperationsInhibited
            } else {
                true
            }
        }
        set {}
    }
    
    func xattr(named name: FSFileName, of item: FSItem) async throws -> Data {
        let item = item as! Item
        logger.pubDebug("getXattr: \(item.name.string ?? "") (id = \(item.id)), xattr = \(name.string ?? "")")
        
        var request = Pb_Request.GetXattr()
        request.name = name.data
        request.itemID = item.id
        
        switch try socket.send(content: .getXattr(request)) {
        case .data(let data):
            return data
        case .posixError(let error):
            logger.error("getXattr: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
    
    func setXattr(named name: FSFileName, to value: Data?, on item: FSItem, policy: FSVolume.SetXattrPolicy) async throws {
        let item = item as! Item
        logger.pubDebug("setXattr: \(item.name.string ?? "") (id = \(item.id)), xattr = \(name.string ?? "")")
        
        var request = Pb_Request.SetXattr()
        request.name = name.data
        if value != nil {
            request.value = value!
        }
        request.itemID = item.id
        request.policy = Pb_SetXattrPolicy(rawValue: Int(policy.rawValue))!
        
        switch try socket.send(content: .setXattr(request)) {
        case .success(_):
            return
        case .posixError(let error):
            logger.error("setXattr: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
    
    func xattrs(of item: FSItem) async throws -> [FSFileName] {
        let item = item as! Item
        logger.pubDebug("getXattrs: \(item.name.string ?? "") (id = \(item.id)), xattr = \(name.string ?? "")")
        
        var request = Pb_Request.GetXattrs()
        request.itemID = item.id
        
        switch try socket.send(content: .getXattrs(request)) {
        case .xattrs(let xattrs):
            var names: [FSFileName] = []
            for name in xattrs.names {
                names.append(FSFileName(data: name))
            }
            return names
        case .posixError(let error):
            logger.error("getXattr: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
}

extension Volume: FSVolume.OpenCloseOperations {
    func openItem(_ item: FSItem, modes: FSVolume.OpenModes) async throws {
        let item = item as! Item
        logger.pubDebug("openItem: \(item.name.string ?? "") (id = \(item.id))")
        
        var request = Pb_Request.OpenItem()
        request.itemID = item.id
        request.modes = modes.toProto()
        
        switch try socket.send(content: .openItem(request)) {
        case .success(_):
            return
        case .posixError(let error):
            logger.error("openItem: failure (error = \(error.code))")
            throw fs_errorForPOSIXError(error.code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
    
    func closeItem(_ item: FSItem, modes: FSVolume.OpenModes) async throws {
        let item = item as! Item
        logger.pubDebug("closeItem: \(item.name.string ?? "") (id = \(item.id))")
        
        var request = Pb_Request.CloseItem()
        request.itemID = item.id
        request.modes = modes.toProto()
        
        switch try socket.send(content: .closeItem(request)) {
        case .success(_):
            return
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
        let item = item as! Item
        logger.pubDebug("read: \(item.name.string ?? "") (id = \(item.id))")
        
        var request = Pb_Request.Read()
        request.itemID = item.id
        request.offset = offset
        request.length = Int64(length)
        
        switch try socket.send(content: .read(request)) {
        case .data(let data):
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
        let item = item as! Item
        logger.pubDebug("write: \(item.name.string ?? "") (id = \(item.id))")
        
        var request = Pb_Request.Write()
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

extension FSVolume.SupportedCapabilities {
    convenience init(_ capabilities: Pb_VolumeCapabilities) {
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
    func toProto() -> [Pb_OpenMode] {
        var modes: [Pb_OpenMode] = []
        if self.rawValue & UInt(Pb_OpenMode.read.rawValue) != 0 { modes.append(.read) }
        if self.rawValue & UInt(Pb_OpenMode.write.rawValue) != 0 { modes.append(.write) }
        return modes
    }
}
