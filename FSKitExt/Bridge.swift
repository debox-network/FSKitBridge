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
        Task {
            do {
                let response = try await socket.send(
                    content: .getResourceIdentifier(Pb_GetResourceIdentifier())
                )
                guard case .resourceIdentifier(let value) = response else {
                    throw BackendError.unexpectedResponse(
                        operation: "probeResource"
                    )
                }

                replyHandler(
                    FSProbeResult.usable(
                        name: value.name,
                        containerID: FSContainerIdentifier(
                            uuid: UUID(uuidString: value.containerID) ?? UUID()
                        )
                    ),
                    nil
                )
            } catch {
                log.e(
                    "probeResource: failure (error = \(error.localizedDescription))"
                )
                replyHandler(nil, error)
            }
        }
    }

    func loadResource(
        resource: FSResource,
        options: FSTaskOptions,
        replyHandler: @escaping (FSVolume?, (any Error)?) -> Void
    ) {
        log.d("loadResource")
        Task {
            do {
                let response = try await socket.send(
                    content: .getVolumeIdentifier(Pb_GetVolumeIdentifier())
                )
                guard case .volumeIdentifier(let value) = response else {
                    throw BackendError.unexpectedResponse(
                        operation: "loadResource"
                    )
                }

                let volume = Volume(value)
                try await volume.load()
                containerStatus = .ready
                replyHandler(volume, nil)
            } catch {
                log.e(
                    "loadResource: failure (error = \(error.localizedDescription))"
                )
                replyHandler(nil, error)
            }
        }
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

enum BackendError: LocalizedError {
    case unexpectedResponse(operation: String)

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse(let operation):
            return "Unexpected backend response during \(operation)."
        }
    }
}
