import Foundation
import NIO
import SwiftProtobuf
import os

final class Socket: @unchecked Sendable {

    static let shared = Socket()

    private let log = Logger(subsystem: "FSKitExt", category: "Socket")

    private var host: String?
    private var port: Int?
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var channel: Channel?
    private var pendingPromises:
        [UInt64: EventLoopPromise<Pb_Response.OneOf_Content>] = [:]
    private let channelLock = NSLock()
    private let promiseLock = NSLock()

    func initialize(host: String, port: Int) {
        channelLock.lock()
        defer { channelLock.unlock() }

        failAllPromises(SocketError.notConnected)

        self.host = host
        self.port = port

        if let channel, channel.isActive {
            channel.close(mode: .all, promise: nil)
            self.channel = nil
        }

        log.d("Socket configured for \(host):\(port)")
    }

    func send(content: Pb_Request.OneOf_Content) throws
        -> Pb_Response.OneOf_Content
    {
        let channel = try getChannel()

        let promise = channel.eventLoop.makePromise(
            of: Pb_Response.OneOf_Content.self
        )
        let requestID = registerPromise(promise)

        var request = Pb_Request()
        request.id = requestID
        request.content = content

        let buffer: ByteBuffer
        do {
            buffer = try encodeLengthDelimited(
                request,
                allocator: channel.allocator
            )
        } catch {
            failPromise(for: requestID, error: error)
            throw error
        }

        let timeout = channel.eventLoop.scheduleTask(in: .seconds(5)) {
            [weak self] in
            self?.failPromise(
                for: requestID,
                error: SocketError.responseTimedOut
            )
        }
        defer { timeout.cancel() }

        channel.writeAndFlush(buffer).whenFailure { [weak self] error in
            self?.failPromise(for: requestID, error: error)
        }

        return try promise.futureResult.wait()
    }

    func fulfillPromise(for requestID: UInt64, with response: Pb_Response) {
        if let promise = removePromise(for: requestID) {
            if let content = response.content {
                promise.succeed(content)
            } else {
                promise.fail(SocketError.missingContent)
            }
        } else {
            log.e("No matching promise for requestID = \(requestID)")
        }
    }

    func failAllPromises(_ error: Error) {
        promiseLock.lock()
        let promises = pendingPromises
        pendingPromises = [:]
        promiseLock.unlock()

        for (_, promise) in promises {
            promise.fail(error)
        }
    }

    func shutdown() {
        failAllPromises(SocketError.notConnected)
        do {
            try channel?.close().wait()
            try group.syncShutdownGracefully()
            log.d("Client shutdown")
        } catch {
            log.e("Shutdown error: \(error.localizedDescription)")
        }
    }

    private func getChannel() throws -> Channel {
        channelLock.lock()
        defer { channelLock.unlock() }

        guard let host = host, let port = port else {
            throw SocketError.notConfigured
        }

        if let current = channel, current.isActive {
            return current
        }

        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelOption(ChannelOptions.socketOption(.so_keepalive), value: 1)
            .channelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(
                    ByteToMessageHandler(LengthDelimitedDecoder())
                )
                .flatMap {
                    channel.pipeline.addHandler(ResponseRouter(self))
                }
            }

        channel = try bootstrap.connect(host: host, port: port).wait()
        log.d("Connected to \(host):\(port)")
        return channel!
    }

    private func registerPromise(
        _ promise: EventLoopPromise<Pb_Response.OneOf_Content>
    ) -> UInt64 {
        promiseLock.lock()
        defer { promiseLock.unlock() }

        var requestID: UInt64
        repeat {
            requestID = UInt64.random(in: 1...UInt64.max)
        } while pendingPromises[requestID] != nil

        pendingPromises[requestID] = promise
        return requestID
    }

    private func removePromise(for requestID: UInt64) -> EventLoopPromise<
        Pb_Response.OneOf_Content
    >? {
        promiseLock.lock()
        defer { promiseLock.unlock() }
        return pendingPromises.removeValue(forKey: requestID)
    }

    private func failPromise(for requestID: UInt64, error: Error) {
        if let promise = removePromise(for: requestID) {
            promise.fail(error)
        }
    }
}

enum SocketError: LocalizedError {
    case notConfigured
    case notConnected
    case invalidVarint
    case responseTimedOut
    case missingContent

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Socket has not been configured with a host and port."
        case .notConnected:
            return "Socket is not connected."
        case .invalidVarint:
            return "Received invalid varint when decoding frame length."
        case .responseTimedOut:
            return "Timed out waiting for a response."
        case .missingContent:
            return "Received a response without any payload."
        }
    }
}

final class LengthDelimitedDecoder: ByteToMessageDecoder {
    typealias InboundOut = ByteBuffer

    private enum State {
        case waitingLength
        case waitingData
    }

    private var state = State.waitingLength
    private var expectedLength = 0

    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws
        -> DecodingState
    {
        while true {
            switch state {
            case .waitingLength:
                var length = 0
                var shift = 0
                var tempBuffer = buffer
                var bytesConsumed = 0

                while let byte = tempBuffer.readInteger(as: UInt8.self) {
                    bytesConsumed += 1
                    length |= Int(byte & 0x7F) << shift
                    if (byte & 0x80) == 0 {
                        expectedLength = length
                        buffer.moveReaderIndex(forwardBy: bytesConsumed)
                        state = .waitingData
                        break
                    }
                    shift += 7
                    if shift > 32 {
                        throw SocketError.invalidVarint
                    }
                }

                if state != .waitingData {
                    return .needMoreData
                }

            case .waitingData:
                guard buffer.readableBytes >= expectedLength else {
                    return .needMoreData
                }
                guard let frame = buffer.readSlice(length: expectedLength)
                else {
                    return .needMoreData
                }
                state = .waitingLength
                context.fireChannelRead(wrapInboundOut(frame))
            }
        }
    }
}

func encodeLengthDelimited<T: SwiftProtobuf.Message>(
    _ message: T,
    allocator: ByteBufferAllocator
) throws -> ByteBuffer {
    let data = try message.serializedData()
    var buffer = allocator.buffer(capacity: 5 + data.count)

    var length = data.count
    repeat {
        var byte = UInt8(length & 0x7F)
        length >>= 7
        if length > 0 {
            byte |= 0x80
        }
        buffer.writeInteger(byte)
    } while length > 0

    buffer.writeBytes(data)
    return buffer
}

final class ResponseRouter: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private let log = Logger(
        subsystem: "FSKitExt",
        category: "Socket.ResponseRouter"
    )

    private weak var socket: Socket?

    init(_ socket: Socket) {
        self.socket = socket
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let rawData = Data(unwrapInboundIn(data).readableBytesView)
        do {
            let response = try Pb_Response(serializedBytes: rawData)
            socket?.fulfillPromise(for: response.requestID, with: response)
        } catch {
            log.e("Failed to decode response: \(error.localizedDescription)")
            socket?.failAllPromises(error)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        log.e("Router error: \(error.localizedDescription)")
        socket?.failAllPromises(error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        socket?.failAllPromises(SocketError.notConnected)
        context.fireChannelInactive()
    }
}
