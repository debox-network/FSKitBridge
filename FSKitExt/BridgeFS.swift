import Foundation
import FSKit
import os

final class BridgeFS: FSUnaryFileSystem, FSUnaryFileSystemOperations {
    
    private let logger = Logger(subsystem: "FSKitExt", category: "BridgeFS")
    
    func probeResource(
        resource: FSResource,
        replyHandler: @escaping (FSProbeResult?, (any Error)?) -> Void
    ) {
        logger.debug("probeResource: \(resource, privacy: .public)")
        replyHandler(
            FSProbeResult.usable(
                name: "Debox",
                containerID: FSContainerIdentifier(uuid: Constants.containerIdentifier)
            ),
            nil
        )
    }
    
    func loadResource(
        resource: FSResource,
        options: FSTaskOptions,
        replyHandler: @escaping (FSVolume?, (any Error)?) -> Void
    ) {
        logger.debug("loadResource: \(resource, privacy: .public)")
        containerStatus = .ready
        replyHandler(Volume(resource: resource), nil)
    }
    
    func unloadResource(
        resource: FSResource,
        options: FSTaskOptions,
        replyHandler reply: @escaping ((any Error)?) -> Void
    ) {
        logger.debug("unloadResource: \(resource, privacy: .public)")
        reply(nil)
    }
    
    func didFinishLoading() {
        logger.debug("didFinishLoading")
    }
}
