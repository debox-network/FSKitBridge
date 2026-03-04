import FSKit
import Foundation

final class ItemCache {
    private struct EntryKey: Hashable {
        let parentID: UInt64
        let name: Data
    }

    private let lock = NSLock()
    private var itemsByID: [UInt64: Item] = [:]
    private var itemsByKey: [EntryKey: UInt64] = [:]
    private var itemsByEntryID: [UInt64: UInt64] = [:]

    func resolve(_ item: Item) -> Item {
        lock.withLock {
            if let current = itemsByID[item.id] {
                return current
            }

            itemsByID[item.id] = item
            itemsByEntryID[item.entryID] = item.id
            itemsByKey[key(item.parentID, item.nameData)] = item.id
            return item
        }
    }

    func upsertRoot(_ item: Pb_Item) -> Item {
        lock.withLock {
            upsert(item, parentID: FSItem.Identifier.parentOfRoot.rawValue)
        }
    }

    func upsert(_ item: Pb_Item, inParent parentID: UInt64) -> Item {
        lock.withLock {
            upsert(item, parentID: parentID)
        }
    }

    func move(_ item: Item, to name: Data, inParent parentID: UInt64) {
        lock.withLock {
            guard let current = itemsByID[item.id] else { return }
            itemsByKey.removeValue(
                forKey: key(current.parentID, current.nameData)
            )
            current.updateDirectoryEntry(name: name, parentID: parentID)
            itemsByKey[key(parentID, name)] = current.id
        }
    }

    func remove(_ id: UInt64) {
        lock.withLock {
            guard let item = itemsByID.removeValue(forKey: id) else {
                return
            }
            itemsByEntryID.removeValue(forKey: item.entryID)
            itemsByKey.removeValue(forKey: key(item.parentID, item.nameData))
        }
    }

    private func reindex(
        _ item: Item,
        entryID: UInt64,
        parentID: UInt64,
        name: Data
    ) {
        itemsByEntryID.removeValue(forKey: item.entryID)
        itemsByKey.removeValue(forKey: key(item.parentID, item.nameData))
        itemsByEntryID[entryID] = item.id
        itemsByKey[key(parentID, name)] = item.id
    }

    private func upsert(_ item: Pb_Item, parentID: UInt64) -> Item {
        let key = key(parentID, item.name)

        if let id = itemsByKey[key], let current = itemsByID[id] {
            reindex(
                current,
                entryID: item.attributes.fileID,
                parentID: parentID,
                name: item.name
            )
            current.update(
                item: item,
                entryID: item.attributes.fileID,
                parentID: parentID
            )
            return current
        }

        if let id = itemsByEntryID[item.attributes.fileID],
            let current = itemsByID[id]
        {
            reindex(
                current,
                entryID: item.attributes.fileID,
                parentID: parentID,
                name: item.name
            )
            current.update(
                item: item,
                entryID: item.attributes.fileID,
                parentID: parentID
            )
            return current
        }

        let id = item.attributes.fileID
        let created = Item(id: id, item: item, parentID: parentID)
        itemsByID[id] = created
        itemsByEntryID[created.entryID] = id
        itemsByKey[key] = id
        return created
    }

    private func key(_ parentID: UInt64, _ name: Data) -> EntryKey {
        EntryKey(parentID: parentID, name: name)
    }
}
