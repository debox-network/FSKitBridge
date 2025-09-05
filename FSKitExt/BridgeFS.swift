import Foundation
import FSKit
import os

final class BridgeFS: FSUnaryFileSystem, FSUnaryFileSystemOperations {
    
    private let log = Logger(subsystem: "FSKitExt", category: "BridgeFS")
    
    func probeResource(resource: FSResource, replyHandler: @escaping (FSProbeResult?, (any Error)?) -> Void) {
        log.d("probeResource")
        replyHandler(FSProbeResult.usable(name: "Debox", containerID: FSContainerIdentifier(uuid: Constants.containerIdentifier)), nil )
    }
    
    func loadResource(resource: FSResource, options: FSTaskOptions, replyHandler: @escaping (FSVolume?, (any Error)?) -> Void) {
        log.d("loadResource")
        
        try? Socket.shared.connect(host: Constants.localHost, port: Constants.localPort)
        
        let volume = Volume(resource: resource)
        volume.load()
        
        containerStatus = .ready
        replyHandler(volume, nil)
    }
    
    func unloadResource(resource: FSResource, options: FSTaskOptions, replyHandler reply: @escaping ((any Error)?) -> Void) {
        log.d("unloadResource")
        reply(nil)
    }
    
    func didFinishLoading() {
        log.d("didFinishLoading")
    }
}
