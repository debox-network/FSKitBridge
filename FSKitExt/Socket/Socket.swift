import Foundation
import os
import NIO
import SwiftProtobuf

enum FrameDecoderError: Error {
    case invalidVarint
}

enum ClientTimeoutError: Error {
    case responseTimedOut
    case notConnected
    case missingRequestID
}

final class Socket: @unchecked Sendable {

    static let shared = Socket()

    private let logger = Logger(subsystem: "FSKitExt", category: "Socket.Socket")

    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var channel: Channel?
    private var pendingPromises: [UInt64: EventLoopPromise<Response>] = [:]
    private let lock = NSLock()

    func connect(host: String, port: Int) throws {
        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                channel.pipeline.addHandler(ByteToMessageHandler(LengthDelimitedFrameDecoder()))
                    .flatMap {
                        channel.pipeline.addHandler(ResponseRouter(self))
                    }
            }

        self.channel = try bootstrap.connect(host: host, port: port).wait()
        logger.debug("✅ Connected to \(host):\(port)")
    }

    func sendAndWaitForResponse(
        message: String,
        count: Int32,
        timeout: TimeAmount = .seconds(5)
    ) throws -> Response {
        guard let channel = self.channel else {
            throw ClientTimeoutError.notConnected
        }

        let requestID = generateRequestID()

        var requestTypeOne = RequestTypeOne()
        requestTypeOne.message = message
        requestTypeOne.count = count

        var request = Request()
        request.requestID = requestID
        request.requestData = .typeOne(requestTypeOne)

        let buffer = try encodeLengthDelimited(request, allocator: channel.allocator)

        let promise = channel.eventLoop.makePromise(of: Response.self)
        lock.lock()
        pendingPromises[requestID] = promise
        lock.unlock()

        let timeoutFuture = channel.eventLoop.scheduleTask(in: timeout) {
            promise.fail(ClientTimeoutError.responseTimedOut)
        }

        defer { timeoutFuture.cancel() }

        channel.writeAndFlush(buffer, promise: nil)

        return try promise.futureResult.wait()
    }

    func fulfillPromise(for requestID: UInt64, with response: Response) {
        lock.lock()
        defer { lock.unlock() }
        if let promise = pendingPromises.removeValue(forKey: requestID) {
            promise.succeed(response)
        } else {
            logger.error("⚠️ No matching promise for request_id: \(requestID)")
        }
    }

    private func generateRequestID() -> UInt64 {
        return UInt64.random(in: 1...UInt64.max)
    }

    func shutdown() {
        do {
            try channel?.close().wait()
            try group.syncShutdownGracefully()
            logger.error("🔻 Client shutdown")
        } catch {
            logger.error("❌ Shutdown error: \(error.localizedDescription, privacy: .public)")
        }
    }
}

final class LengthDelimitedFrameDecoder: ByteToMessageDecoder {
    typealias InboundOut = ByteBuffer

    private var state: State = .waitingLength
    private var expectedLength: Int = 0

    enum State {
        case waitingLength
        case waitingData
    }

    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
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
                        throw ClientTimeoutError.responseTimedOut
                    }
                }

                if state != .waitingData {
                    return .needMoreData
                }

            case .waitingData:
                guard buffer.readableBytes >= expectedLength else {
                    return .needMoreData
                }
                let frame = buffer.readSlice(length: expectedLength)!
                state = .waitingLength
                context.fireChannelRead(self.wrapInboundOut(frame))
                // continue loop to process next frame if available
            }
        }
    }
}

func encodeLengthDelimited<T: SwiftProtobuf.Message>(_ message: T, allocator: ByteBufferAllocator) throws -> ByteBuffer {
    let messageData = try message.serializedData()
    var buffer = allocator.buffer(capacity: 5 + messageData.count)

    var length = messageData.count
    repeat {
        var byte = UInt8(length & 0x7F)
        length >>= 7
        if length > 0 {
            byte |= 0x80
        }
        buffer.writeInteger(byte)
    } while length > 0

    buffer.writeBytes(messageData)
    return buffer
}

final class ResponseRouter: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private let logger = Logger(subsystem: "FSKitExt", category: "Socket.ResponseRouter")
    private weak var socket: Socket?

    init(_ socket: Socket) {
        self.socket = socket
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        logger.debug("🧩 Raw bytes received: \(buffer.readableBytes)")
        let rawData = Data(buffer.readableBytesView)
        logger.debug("🧩 Data received (hex): \(rawData.map { String(format: "%02x", $0) }.joined(), privacy: .public)")

        do {
            let response = try Response(serializedBytes: rawData)
            logger.debug("📨 Decoded Response: request_id=\(response.requestID)")
            socket?.fulfillPromise(for: response.requestID, with: response)
        } catch {
            logger.error("❌ Failed to decode response: \(error.localizedDescription, privacy: .public)")
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("❌ Router error: \(error.localizedDescription, privacy: .public)")
        context.close(promise: nil)
    }
}
