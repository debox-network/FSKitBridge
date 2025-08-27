import Foundation
import os
import NIO
import SwiftProtobuf

final class Socket: @unchecked Sendable {
    
    static let shared = Socket()
    
    private let logger = Logger(subsystem: "FSKitExt", category: "Socket.Socket")
    
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var channel: Channel?
    private var pendingPromises: [UInt64: EventLoopPromise<Pb_Response.OneOf_Content>] = [:]
    private let lock = NSLock()
    
    func connect(host: String, port: Int) throws {
        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                channel.pipeline.addHandler(ByteToMessageHandler(LengthDelimitedDecoder()))
                    .flatMap {
                        channel.pipeline.addHandler(ResponseRouter(self))
                    }
            }
        channel = try bootstrap.connect(host: host, port: port).wait()
        logger.info("Connected to \(host, privacy: .public):\(port)")
    }
    
    func send(content: Pb_Request.OneOf_Content) throws -> Pb_Response.OneOf_Content {
        guard let channel = self.channel else {
            throw SocketError.notConnected
        }
        
        var request = Pb_Request()
        request.id = generateRequestID()
        request.content = content
        
        let buffer = try encodeLengthDelimited(request, allocator: channel.allocator)
        
        let promise = channel.eventLoop.makePromise(of: Pb_Response.OneOf_Content.self)
        lock.lock()
        pendingPromises[request.id] = promise
        lock.unlock()
        
        let timeout = channel.eventLoop.scheduleTask(in: .seconds(5)) {
            promise.fail(SocketError.responseTimedOut)
        }
        defer { timeout.cancel() }
        
        channel.writeAndFlush(buffer, promise: nil)
        
        return try promise.futureResult.wait()
    }
    
    func fulfillPromise(for requestID: UInt64, with response: Pb_Response) {
        lock.lock()
        defer { lock.unlock() }
        if let promise = pendingPromises.removeValue(forKey: requestID) {
            promise.succeed(response.content!)
        } else {
            logger.error("No matching promise for requestID = \(requestID)")
        }
    }
    
    func shutdown() {
        do {
            try channel?.close().wait()
            try group.syncShutdownGracefully()
            logger.info("Client shutdown")
        } catch {
            logger.error("Shutdown error: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func generateRequestID() -> UInt64 {
        return UInt64.random(in: 1...UInt64.max)
    }
}

enum SocketError: Error {
    case notConnected
    case invalidVarint
    case responseTimedOut
    case missingRequestID
}

final class LengthDelimitedDecoder: ByteToMessageDecoder {
    typealias InboundOut = ByteBuffer
    
    private enum State {
        case waitingLength
        case waitingData
    }
    
    private var state = State.waitingLength
    private var expectedLength = 0
    
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
                let frame = buffer.readSlice(length: expectedLength)!
                state = .waitingLength
                context.fireChannelRead(wrapInboundOut(frame))
            }
        }
    }
}

func encodeLengthDelimited<T: SwiftProtobuf.Message>(_ message: T, allocator: ByteBufferAllocator) throws -> ByteBuffer {
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
    
    private let logger = Logger(subsystem: "FSKitExt", category: "Socket.ResponseRouter")
    
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
            logger.error("Failed to decode response: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("Router error: \(error.localizedDescription, privacy: .public)")
        context.close(promise: nil)
    }
}
