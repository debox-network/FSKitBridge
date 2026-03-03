import Foundation

final class ItemCache {
    private let lock = NSLock()
    private var items: [UInt64: Item] = [:]

    func resolve(_ item: Item) -> Item {
        lock.withLock {
            if let current = items[item.id] {
                return current
            }

            items[item.id] = item
            return item
        }
    }

    func upsert(_ item: Pb_Item) -> Item {
        lock.withLock {
            if let current = items[item.attributes.fileID] {
                current.updateName(name: item.name)
                current.updateAttributes(attributes: item.attributes)
                return current
            }

            let created = Item(item)
            items[created.id] = created
            return created
        }
    }

    func remove(_ id: UInt64) {
        lock.withLock {
            items.removeValue(forKey: id)
        }
    }
}
