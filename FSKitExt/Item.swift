//
//  AppFSItem.swift
//  FSKitExp
//
//  Created by Debox on 7/16/25.
//

import Foundation
import FSKit

final class Item: FSItem {
    
    private let logger = Logger(subsystem: "FSKitExt", category: "Item")
    
    private static var id: UInt64 = FSItem.Identifier.rootDirectory.rawValue + 1
    static func getNextID() -> UInt64 {
        let current = id
        id += 1
        return current
    }
    
    let name: FSFileName
    let id = Item.getNextID()
    
    var attributes = FSItem.Attributes()
    var xattrs: [FSFileName: Data] = [:]
    var data: Data?
    
    private(set) var children: [FSFileName: Item] = [:]
    
    init(name: FSFileName) {
        logger.debug("FILENAME: \(name.string ?? "", privacy: .public)")
        
        self.name = name
        attributes.fileID = FSItem.Identifier(rawValue: id) ?? .invalid
        attributes.size = 0
        attributes.allocSize = 0
        attributes.flags = 0
        
        var timespec = timespec()
        timespec_get(&timespec, TIME_UTC)
        
        attributes.addedTime = timespec
        attributes.birthTime = timespec
        attributes.changeTime = timespec
        attributes.modifyTime = timespec
        attributes.accessTime = timespec
    }
    
    func addItem(_ item: Item) {
        children[item.name] = item
    }
    
    func removeItem(_ item: Item) {
        children[item.name] = nil
    }
}

// log stream --info --debug --style syslog --predicate 'subsystem == "com.example.FSKitExt"'
// umount /tmp/vol
// mount -F -t MyFS disk20 /tmp/vol
