import FSKit
import Foundation
import os

final class Volume: FSVolume {

    private let log = Logger(subsystem: "FSKitExt", category: "Volume")

    private let socket = Socket.shared

    private var volumeBehavior: Pb_VolumeBehavior!
    private var pathConfOperations: Pb_PathConfOperations!
    private var supportedCapabilities: Pb_SupportedCapabilities!

    private var items: [UInt64: Item] = [:]

    init(_ identifier: Pb_VolumeIdentifier) {
        super.init(
            volumeID: FSVolume.Identifier(
                uuid: UUID(uuidString: identifier.id) ?? UUID()
            ),
            volumeName: FSFileName(
                string: identifier.hasName
                    ? identifier.name : Bundle.main.fsShortName!
            )
        )
    }

    func load() {
        volumeBehavior = getVolumeBehavior()
        pathConfOperations = getPathConfOperations()
        supportedCapabilities = getVolumeCapabilities()
    }

    private func getVolumeBehavior() -> Pb_VolumeBehavior {
        log.d("getInhibitedOperations")
        let response = try? socket.send(
            content: .getVolumeBehavior(Pb_GetVolumeBehavior())
        )
        return if case .volumeBehavior(let value) = response {
            value
        } else {
            Pb_VolumeBehavior()
        }
    }

    private func getPathConfOperations() -> Pb_PathConfOperations {
        log.d("getPathConfOperations")
        let response = try? socket.send(
            content: .getPathConfOperations(Pb_GetPathConfOperations())
        )
        return if case .pathConfOperations(let value) = response {
            value
        } else {
            Pb_PathConfOperations()
        }
    }

    private func getVolumeCapabilities() -> Pb_SupportedCapabilities {
        log.d("getVolumeCapabilities")
        let response = try? socket.send(
            content: .getVolumeCapabilities(Pb_GetVolumeCapabilities())
        )
        return if case .supportedCapabilities(let value) = response {
            value
        } else {
            Pb_SupportedCapabilities()
        }
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
        FSVolume.SupportedCapabilities(supportedCapabilities)
    }

    var volumeStatistics: FSStatFSResult {
        log.d("getVolumeStatistics")
        let response = try? socket.send(
            content: .getVolumeStatistics(Pb_GetVolumeStatistics())
        )
        return if case .statFsResult(let value) = response {
            FSStatFSResult(value)
        } else {
            FSStatFSResult(fileSystemTypeName: Bundle.main.fsShortName!)
        }
    }

    func mount(options: FSTaskOptions) async throws {
        log.d("mount")

        var request = Pb_Mount()
        request.options = options.toProto()

        switch try socket.send(content: .mount(request)) {
        case .success(_):
            return
        case .posixError(let code):
            log.posixError("mount", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }

    func unmount() async {
        log.d("unmount")
        switch try? socket.send(content: .unmount(Pb_Unmount())) {
        case .success(_):
            return
        case .posixError(let error):
            log.posixError("unmount", error)
        default:
            log.e("unmount: failure")
        }
    }

    func synchronize(flags: FSSyncFlags) async throws {
        log.d("synchronize")

        var request = Pb_Synchronize()
        request.flags = Pb_Synchronize.SyncFlags(rawValue: flags.rawValue)!

        switch try socket.send(content: .synchronize(request)) {
        case .success(_):
            return
        case .posixError(let code):
            log.posixError("synchronize", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }

    func attributes(
        _ desiredAttributes: FSItem.GetAttributesRequest,
        of item: FSItem
    ) async throws -> FSItem.Attributes {
        guard let item = item as? Item else {
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
        log.d("getAttributes: \(item.name.string ?? "") (id = \(item.id))")

        var request = Pb_GetAttributes()
        request.itemID = item.id

        switch try socket.send(content: .getAttributes(request)) {
        case .itemAttributes(let attributes):
            item.updateAttributes(attributes: attributes)
            return item.attributes
        case .posixError(let code):
            log.posixError("getAttributes", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }

    func setAttributes(
        _ newAttributes: FSItem.SetAttributesRequest,
        on item: FSItem
    ) async throws -> FSItem.Attributes {
        let item = item as! Item
        log.d("setAttributes: \(item.name.string ?? "") (id = \(item.id))")

        var request = Pb_SetAttributes()
        request.attributes = newAttributes.toProto()
        request.itemID = item.id

        switch try socket.send(content: .setAttributes(request)) {
        case .itemAttributes(let attributes):
            item.updateAttributes(attributes: attributes)
            return item.attributes
        case .posixError(let code):
            log.posixError("setAttributes", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }

    func lookupItem(named name: FSFileName, inDirectory directory: FSItem)
        async throws -> (FSItem, FSFileName)
    {
        let directory = directory as! Item
        log.d(
            "lookupItem: \(directory.name.string ?? "") (id = \(directory.id)), name = \(name.string ?? "")"
        )

        var request = Pb_LookupItem()
        request.name = name.data
        request.directoryID = directory.id

        switch try socket.send(content: .lookupItem(request)) {
        case .item(let item):
            if let item_ = items[item.attributes.fileID] {
                item_.updateName(name: item.name)
                item_.updateAttributes(attributes: item.attributes)
                return (item_, item_.name)
            } else {
                let item = Item(item)
                items[item.id] = item
                return (item, item.name)
            }
        case .posixError(let code):
            log.posixError("lookupItem", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }

    func reclaimItem(_ item: FSItem) async throws {
        let item = item as! Item
        log.d("reclaimItem: \(item.name.string ?? "") (id = \(item.id))")

        var request = Pb_ReclaimItem()
        request.itemID = item.id

        switch try socket.send(content: .reclaimItem(request)) {
        case .success(_):
            items.removeValue(forKey: item.id)
            return
        case .posixError(let code):
            log.posixError("reclaimItem", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }

    func readSymbolicLink(_ item: FSItem) async throws -> FSFileName {
        let item = item as! Item
        log.d("readSymbolicLink: \(item.name.string ?? "") (id = \(item.id))")

        var request = Pb_ReadSymbolicLink()
        request.itemID = item.id

        switch try socket.send(content: .readSymbolicLink(request)) {
        case .data(let data):
            return FSFileName(data: data)
        case .posixError(let code):
            log.posixError("readSymbolicLink", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }

    func createItem(
        named name: FSFileName,
        type: FSItem.ItemType,
        inDirectory directory: FSItem,
        attributes newAttributes: FSItem.SetAttributesRequest
    ) async throws -> (FSItem, FSFileName) {
        let directory = directory as! Item
        log.d(
            "createItem: \(directory.name.string ?? "") (id = \(directory.id)), name = \(name.string ?? "")"
        )

        var request = Pb_CreateItem()
        request.name = name.data
        request.type = Pb_ItemType(rawValue: type.rawValue)!
        request.directoryID = directory.id
        request.attributes = newAttributes.toProto()

        switch try socket.send(content: .createItem(request)) {
        case .item(let item):
            let item = Item(item)
            items[item.id] = item
            return (item, item.name)
        case .posixError(let code):
            log.posixError("createItem", code)
            throw fs_errorForPOSIXError(code)
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
        let directory = directory as! Item
        log.d(
            "createSymbolicLink: \(directory.name.string ?? "") (id = \(directory.id)), name = \(name.string ?? "")"
        )

        var request = Pb_CreateSymbolicLink()
        request.name = name.data
        request.directoryID = directory.id
        request.newAttributes = newAttributes.toProto()
        request.contents = contents.data

        switch try socket.send(content: .createSymbolicLink(request)) {
        case .item(let item):
            let item = Item(item)
            items[item.id] = item
            return (item, item.name)
        case .posixError(let code):
            log.posixError("createSymbolicLink", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }

    func createLink(
        to item: FSItem,
        named name: FSFileName,
        inDirectory directory: FSItem
    ) async throws -> FSFileName {
        let item = item as! Item
        let directory = directory as! Item
        log.d("createLink: \(item.name.string ?? "") (id = \(item.id))")

        var request = Pb_CreateLink()
        request.itemID = item.id
        request.name = name.data
        request.directoryID = directory.id

        switch try socket.send(content: .createLink(request)) {
        case .data(let data):
            item.updateName(name: data)
            return item.name
        case .posixError(let code):
            log.posixError("createLink", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }

    func removeItem(
        _ item: FSItem,
        named name: FSFileName,
        fromDirectory directory: FSItem
    ) async throws {
        let item = item as! Item
        let directory = directory as! Item
        log.d("removeItem: \(item.name.string ?? "") (id = \(item.id))")

        var request = Pb_RemoveItem()
        request.itemID = item.id
        request.name = name.data
        request.directoryID = directory.id

        switch try socket.send(content: .removeItem(request)) {
        case .success(_):
            return
        case .posixError(let code):
            log.posixError("removeItem", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
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
        let item = item as! Item
        let sourceDirectory = sourceDirectory as! Item
        let destinationDirectory = destinationDirectory as! Item
        let overItem = overItem as? Item
        log.d(
            "renameItem: \(item.name.string ?? "") -> \(destinationName.string ?? "") (id = \(item.id))"
        )

        var request = Pb_RenameItem()
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
        case .posixError(let code):
            log.posixError("renameItem", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }

    func enumerateDirectory(
        _ directory: FSItem,
        startingAt cookie: FSDirectoryCookie,
        verifier: FSDirectoryVerifier,
        attributes: FSItem.GetAttributesRequest?,
        packer: FSDirectoryEntryPacker
    ) async throws -> FSDirectoryVerifier {
        let directory = directory as! Item
        log.d(
            "enumerateDirectory: \(directory.name.string ?? "") (id = \(directory.id))"
        )

        var request = Pb_EnumerateDirectory()
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
        case .posixError(let code):
            log.posixError("enumerateDirectory", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }

    func activate(options: FSTaskOptions) async throws -> FSItem {
        log.d("activate")

        var request = Pb_Activate()
        request.options = options.toProto()

        switch try socket.send(content: .activate(request)) {
        case .item(let item):
            let item = Item(item)
            items[item.id] = item
            return item
        case .posixError(let code):
            log.posixError("activate", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }

    func deactivate(options: FSDeactivateOptions = []) async throws {
        log.d("deactivate")
        switch try socket.send(content: .deactivate(Pb_Deactivate())) {
        case .success(_):
            return
        case .posixError(let code):
            log.posixError("deactivate", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
}

extension Volume: FSVolume.XattrOperations {
    var xattrOperationsInhibited: Bool {
        get { volumeBehavior.xattrOperationsInhibited }
        set {}
    }

    func supportedXattrNames(for item: FSItem) -> [FSFileName] {
        let item = item as! Item
        log.d(
            "supportedXattrNames: \(item.name.string ?? "") (id = \(item.id))"
        )

        var request = Pb_GetSupportedXattrNames()
        request.itemID = item.id

        switch try? socket.send(content: .getSupportedXattrNames(request)) {
        case .xattrs(let xattrs):
            var names: [FSFileName] = []
            for name in xattrs.names {
                names.append(FSFileName(data: name))
            }
            return names
        case .posixError(let code):
            log.posixError("supportedXattrNames", code)
            return []
        default:
            return []
        }
    }

    func xattr(named name: FSFileName, of item: FSItem) async throws -> Data {
        let item = item as! Item
        log.d(
            "getXattr: \(item.name.string ?? "") (id = \(item.id)), xattr = \(name.string ?? "")"
        )

        var request = Pb_GetXattr()
        request.name = name.data
        request.itemID = item.id

        switch try socket.send(content: .getXattr(request)) {
        case .data(let data):
            return data
        case .posixError(let code):
            log.posixError("getXattr", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }

    func setXattr(
        named name: FSFileName,
        to value: Data?,
        on item: FSItem,
        policy: FSVolume.SetXattrPolicy
    ) async throws {
        let item = item as! Item
        log.d(
            "setXattr: \(item.name.string ?? "") (id = \(item.id)), xattr = \(name.string ?? "")"
        )

        var request = Pb_SetXattr()
        request.name = name.data
        if value != nil {
            request.value = value!
        }
        request.itemID = item.id
        request.policy = Pb_SetXattr.SetXattrPolicy(
            rawValue: Int(policy.rawValue)
        )!

        switch try socket.send(content: .setXattr(request)) {
        case .success(_):
            return
        case .posixError(let code):
            log.posixError("setXattr", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }

    func xattrs(of item: FSItem) async throws -> [FSFileName] {
        let item = item as! Item
        log.d("getXattrs: \(item.name.string ?? "") (id = \(item.id))")

        var request = Pb_GetXattrs()
        request.itemID = item.id

        switch try socket.send(content: .getXattrs(request)) {
        case .xattrs(let xattrs):
            var names: [FSFileName] = []
            for name in xattrs.names {
                names.append(FSFileName(data: name))
            }
            return names
        case .posixError(let code):
            log.posixError("getXattrs", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
}

extension Volume: FSVolume.OpenCloseOperations {
    var isOpenCloseInhibited: Bool {
        get { volumeBehavior.isOpenCloseInhibited }
        set {}
    }

    func openItem(_ item: FSItem, modes: FSVolume.OpenModes) async throws {
        let item = item as! Item
        log.d("openItem: \(item.name.string ?? "") (id = \(item.id))")

        var request = Pb_OpenItem()
        request.itemID = item.id
        request.modes = modes.toProto()

        switch try socket.send(content: .openItem(request)) {
        case .success(_):
            return
        case .posixError(let code):
            log.posixError("openItem", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }

    func closeItem(_ item: FSItem, modes: FSVolume.OpenModes) async throws {
        let item = item as! Item
        log.d("closeItem: \(item.name.string ?? "") (id = \(item.id))")

        var request = Pb_CloseItem()
        request.itemID = item.id
        request.modes = modes.toProto()

        switch try socket.send(content: .closeItem(request)) {
        case .success(_):
            return
        case .posixError(let code):
            log.posixError("closeItem", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
}

extension Volume: FSVolume.ReadWriteOperations {
    func read(
        from item: FSItem,
        at offset: off_t,
        length: Int,
        into buffer: FSMutableFileDataBuffer
    ) async throws -> Int {
        let item = item as! Item
        log.d("read: \(item.name.string ?? "") (id = \(item.id))")

        var request = Pb_Read()
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
        case .posixError(let code):
            log.posixError("read", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }

    func write(contents: Data, to item: FSItem, at offset: off_t) async throws
        -> Int
    {
        let item = item as! Item
        log.d("write: \(item.name.string ?? "") (id = \(item.id))")

        var request = Pb_Write()
        request.contents = contents
        request.itemID = item.id
        request.offset = offset

        switch try socket.send(content: .write(request)) {
        case .byteCount(let count):
            return Int(count)
        case .posixError(let code):
            log.posixError("write", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
}

extension Volume: FSVolume.AccessCheckOperations {
    var isAccessCheckInhibited: Bool {
        get { volumeBehavior.isAccessCheckInhibited }
        set {}
    }

    func checkAccess(
        to theItem: FSItem,
        requestedAccess access: FSVolume.AccessMask
    ) async throws -> Bool {
        let item = theItem as! Item
        log.d("checkAccess: \(item.name.string ?? "") (id = \(item.id))")

        var request = Pb_CheckAccess()
        request.itemID = item.id
        request.access = access.toProto()

        switch try socket.send(content: .checkAccess(request)) {
        case .allow(let allow):
            return allow
        case .posixError(let code):
            log.posixError("checkAccess", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
}

extension Volume: FSVolume.RenameOperations {
    var isVolumeRenameInhibited: Bool {
        get { volumeBehavior.isVolumeRenameInhibited }
        set {}
    }

    func setVolumeName(_ name: FSFileName) async throws -> FSFileName {
        log.d("setVolumeName: \(name.string ?? "")")

        var request = Pb_SetVolumeName()
        request.name = name.data

        switch try socket.send(content: .setVolumeName(request)) {
        case .data(let data):
            return FSFileName(data: data)
        case .posixError(let code):
            log.posixError("setVolumeName", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
}

extension Volume: FSVolume.PreallocateOperations {
    var isPreallocateInhibited: Bool {
        get { volumeBehavior.isPreallocateInhibited }
        set {}
    }

    func preallocateSpace(
        for item: FSItem,
        at offset: off_t,
        length: Int,
        flags: FSVolume.PreallocateFlags
    ) async throws -> Int {
        let item = item as! Item
        log.d("preallocateSpace: \(item.name.string ?? "") (id = \(item.id))")

        var request = Pb_PreallocateSpace()
        request.itemID = item.id
        request.offset = offset
        request.length = Int64(length)
        request.flags = flags.toProto()

        switch try socket.send(content: .preallocateSpace(request)) {
        case .byteCount(let count):
            return Int(count)
        case .posixError(let code):
            log.posixError("preallocateSpace", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
}

extension Volume: FSVolume.ItemDeactivation {
    var itemDeactivationPolicy: FSVolume.ItemDeactivationOptions {
        FSVolume.ItemDeactivationOptions(volumeBehavior.itemDeactivationOptions)
    }

    func deactivateItem(_ item: FSItem) async throws {
        let item = item as! Item
        log.d("deactivateItem: \(item.name.string ?? "") (id = \(item.id))")

        var request = Pb_DeactivateItem()
        request.itemID = item.id

        switch try socket.send(content: .deactivateItem(request)) {
        case .success(_):
            return
        case .posixError(let code):
            log.posixError("deactivateItem", code)
            throw fs_errorForPOSIXError(code)
        default:
            throw fs_errorForPOSIXError(POSIXError.ENOENT.rawValue)
        }
    }
}

extension FSVolume.SupportedCapabilities {
    convenience init(_ capabilities: Pb_SupportedCapabilities) {
        self.init()
        if capabilities.hasSupportsPersistentObjectIds {
            self.supportsPersistentObjectIDs =
                capabilities.supportsPersistentObjectIds
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
            self.doesNotSupportVolumeSizes =
                capabilities.doesNotSupportVolumeSizes
        }
        if capabilities.hasSupports64BitObjectIds {
            self.supports64BitObjectIDs = capabilities.supports64BitObjectIds
        }
        if capabilities.hasSupportsDocumentID {
            self.supportsDocumentID = capabilities.supportsDocumentID
        }
        if capabilities.hasDoesNotSupportImmutableFiles {
            self.doesNotSupportImmutableFiles =
                capabilities.doesNotSupportImmutableFiles
        }
        if capabilities.hasDoesNotSupportSettingFilePermissions {
            self.doesNotSupportSettingFilePermissions =
                capabilities.doesNotSupportSettingFilePermissions
        }
        if capabilities.hasSupportsSharedSpace {
            self.supportsSharedSpace = capabilities.supportsSharedSpace
        }
        if capabilities.hasSupportsVolumeGroups {
            self.supportsVolumeGroups = capabilities.supportsVolumeGroups
        }
        if capabilities.hasCaseFormat {
            self.caseFormat = FSVolume.CaseFormat(
                rawValue: capabilities.caseFormat.rawValue
            )!
        }
    }
}

extension FSStatFSResult {
    convenience init(_ result: Pb_StatFSResult) {
        self.init(fileSystemTypeName: Bundle.main.fsShortName!)
        self.blockSize = Int(result.blockSize)
        self.ioSize = Int(result.ioSize)
        self.totalBlocks = result.totalBlocks
        self.availableBlocks = result.availableBlocks
        self.freeBlocks = result.freeBlocks
        self.usedBlocks = result.usedBlocks
        self.totalBytes = result.totalBytes
        self.availableBytes = result.availableBytes
        self.freeBytes = result.freeBytes
        self.usedBytes = result.usedBytes
        self.totalFiles = result.totalFiles
        self.freeFiles = result.freeFiles
        self.fileSystemSubType = Bundle.main.fsSubType ?? 0
    }
}

extension FSVolume.ItemDeactivationOptions {
    init(_ options: [Pb_VolumeBehavior.ItemDeactivationOption]) {
        self.init()
        for option in options {
            switch option {
            case .always:
                self.insert(.always)
            case .forRemovedItems:
                self.insert(.forRemovedItems)
            case .forPreallocatedItems:
                self.insert(.forPreallocatedItems)
            case .UNRECOGNIZED(_):
                continue
            }
        }
    }
}

extension FSTaskOptions {
    func toProto() -> Pb_TaskOptions {
        var options = Pb_TaskOptions()
        options.taskOptions = self.taskOptions
        return options
    }
}

extension FSVolume.OpenModes {
    func toProto() -> [Pb_OpenMode] {
        var out: [Pb_OpenMode] = []
        if self.contains(.read) { out.append(.read) }
        if self.contains(.write) { out.append(.write) }
        return out
    }
}

extension FSVolume.AccessMask {
    func toProto() -> [Pb_CheckAccess.AccessMask] {
        var out: [Pb_CheckAccess.AccessMask] = []
        if self.contains(.readData) { out.append(.readData) }
        if self.contains(.listDirectory) { out.append(.listDirectory) }
        if self.contains(.writeData) { out.append(.writeData) }
        if self.contains(.addFile) { out.append(.addFile) }
        if self.contains(.execute) { out.append(.execute) }
        if self.contains(.search) { out.append(.search) }
        if self.contains(.delete) { out.append(.delete) }
        if self.contains(.appendData) { out.append(.appendData) }
        if self.contains(.addSubdirectory) { out.append(.addSubdirectory) }
        if self.contains(.deleteChild) { out.append(.deleteChild) }
        if self.contains(.readAttributes) { out.append(.readAttributes) }
        if self.contains(.writeAttributes) { out.append(.writeAttributes) }
        if self.contains(.readXattr) { out.append(.readXattr) }
        if self.contains(.writeXattr) { out.append(.writeXattr) }
        if self.contains(.readSecurity) { out.append(.readSecurity) }
        if self.contains(.writeSecurity) { out.append(.writeSecurity) }
        if self.contains(.takeOwnership) { out.append(.takeOwnership) }
        return out
    }
}

extension FSVolume.PreallocateFlags {
    func toProto() -> [Pb_PreallocateSpace.PreallocateFlag] {
        var out: [Pb_PreallocateSpace.PreallocateFlag] = []
        if self.contains(.contiguous) { out.append(.contiguous) }
        if self.contains(.all) { out.append(.all) }
        if self.contains(.persist) { out.append(.persist) }
        if self.contains(.fromEOF) { out.append(.fromEof) }
        return out
    }
}

extension Bundle {
    var fsShortName: String? {
        guard
            let attrs = infoDictionary?["EXAppExtensionAttributes"]
                as? [String: Any],
            let value = attrs["FSShortName"] as? String
        else { return nil }
        return value
    }

    var fsSubType: Int? {
        guard
            let attrs = infoDictionary?["EXAppExtensionAttributes"]
                as? [String: Any],
            let pers = attrs["FSPersonalities"]
                as? [String: Any],
            let value = pers["FSSubType"] as? Int
        else { return nil }
        return value
    }
}
