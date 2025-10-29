import FSKit
import Foundation
import os

final class Bridge: FSUnaryFileSystem, FSUnaryFileSystemOperations {

    static let shared = Bridge()

    private let log = Logger(subsystem: "FSKitExt", category: "Bridge")

    private let socket = Socket.shared

    private override init() {
        super.init()
        do {
            let port = try Bundle.main.getServerPort()
            socket.initialize(host: "localhost", port: port)
        } catch {
            log.e("Failed to configure socket: \(error.localizedDescription)")
        }
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
