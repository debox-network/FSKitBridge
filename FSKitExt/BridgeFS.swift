import FSKit
import Foundation
import os

final class BridgeFS: FSUnaryFileSystem, FSUnaryFileSystemOperations {

    private let log = Logger(subsystem: "FSKitExt", category: "BridgeFS")

    private let socket = Socket.shared

    override init() {
        super.init()
        Socket.shared.initialize(
            host: "localhost",
            port: Bundle.main.serverPort!
        )
    }

    func probeResource(
        resource: FSResource,
        replyHandler: @escaping (FSProbeResult?, (any Error)?) -> Void
    ) {
        log.d("probeResource")
        do {
            let response = try socket.send(
                content: .getResourceIdentifier(Pb_GetResourceIdentifier())
            )
            if case .resourceIdentifier(let value) = response {
                replyHandler(
                    FSProbeResult.usable(
                        name: value.name,
                        containerID: FSContainerIdentifier(
                            uuid: UUID(uuidString: value.containerID) ?? UUID()
                        )
                    ),
                    nil
                )
                return
            }
        } catch {
            log.e(
                "probeResource: failure (error = \(error.localizedDescription))"
            )
        }
        replyHandler(nil, nil)
    }

    func loadResource(
        resource: FSResource,
        options: FSTaskOptions,
        replyHandler: @escaping (FSVolume?, (any Error)?) -> Void
    ) {
        log.d("loadResource")
        do {
            let response = try socket.send(
                content: .getVolumeIdentifier(Pb_GetVolumeIdentifier())
            )
            if case .volumeIdentifier(let value) = response {
                let volume = Volume(value)
                volume.load()
                containerStatus = .ready
                replyHandler(volume, nil)
                return
            }
        } catch {
            log.e(
                "loadResource: failure (error = \(error.localizedDescription))"
            )
        }
        replyHandler(nil, nil)
    }

    func unloadResource(
        resource: FSResource,
        options: FSTaskOptions,
        replyHandler reply: @escaping ((any Error)?) -> Void
    ) {
        log.d("unloadResource")
        reply(nil)
    }

    func didFinishLoading() {
        log.d("didFinishLoading")
    }
}
