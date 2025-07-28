//
//  FSKitExt.swift
//  FSKitExt
//
//  Created by Debox on 7/16/25.
//

import Foundation
import FSKit

@main
struct FSKitExt : UnaryFileSystemExtension {
    var fileSystem : FSUnaryFileSystem & FSUnaryFileSystemOperations {
        BridgeFS()
    }
}
