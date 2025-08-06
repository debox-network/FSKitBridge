import Foundation
import os
import NIO
import SwiftProtobuf

enum FrameDecoderError: Error {
    case invalidVarint
}

class Socket {
    
    static let shared = Socket()
    
    private let logger = Logger(subsystem: "FSKitExt", category: "Socket.Socket")
    
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var channel: Channel?
    
    func connect(host: String = "127.0.0.1", port: Int = 9000) throws {
        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                channel.pipeline.addHandler(ByteToMessageHandler(LengthDelimitedFrameDecoder()))
                    .flatMap {
                        channel.pipeline.addHandler(ProtobufClientHandler())
                    }
            }
        
        self.channel = try bootstrap.connect(host: host, port: port).wait()
        logger.debug("✅ Connected to \(host):\(port)")
    }
    
    func sendTypeOne(message: String, count: Int32) throws {
        guard let channel = self.channel else {
            logger.debug("❌ Not connected")
            return
        }
        
        var requestTypeOne = RequestTypeOne()
        requestTypeOne.message = message
        requestTypeOne.count = count
        
        var request = Request()
        request.requestData = .typeOne(requestTypeOne)
        
        let buffer = try encodeLengthDelimited(request, allocator: channel.allocator)
        channel.writeAndFlush(buffer, promise: nil)
        logger.debug("📤 Sent RequestTypeOne: \(message, privacy: .public)")
    }
    
    func shutdown() {
        do {
            try channel?.close().wait()
            try group.syncShutdownGracefully()
            logger.debug("🔻 Client shutdown")
        } catch {
            logger.debug("❌ Error during shutdown: \(error)")
        }
    }
}

// MARK: - Client Handler
class ProtobufClientHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    
    private let logger = Logger(subsystem: "FSKitExt", category: "IPC.ProtobufClientHandler")
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        let rawData = Data(buffer.readableBytesView)
        
        do {
            let response = try Response(serializedBytes: rawData)
            switch response.responseData {
            case .typeOne(let r1):
                logger.debug("✅ ResponseTypeOne: \(r1.reply), success: \(r1.success)")
            case .typeTwo(let r2):
                logger.debug("✅ ResponseTypeTwo: \(r2.status), code: \(r2.errorCode)")
            case nil:
                logger.debug("⚠️ Received response with no data")
            }
        } catch {
            logger.debug("❌ Failed to decode response: \(error)")
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.debug("❌ Client socket error: \(error)")
        context.close(promise: nil)
    }
}

// MARK: - Length-delimited decoder (compatible with Rust's decode_length_delimited)
final class LengthDelimitedFrameDecoder: ByteToMessageDecoder {
    typealias InboundOut = ByteBuffer
    
    private var state: State = .waitingLength
    private var expectedLength: Int = 0
    
    enum State {
        case waitingLength
        case waitingData
    }
    
    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        switch state {
        case .waitingLength:
            // Try to decode a varint
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
                    return .needMoreData
                }
                shift += 7
                if shift > 32 {
                    throw FrameDecoderError.invalidVarint
                }
            }
            
            return .needMoreData
            
        case .waitingData:
            guard buffer.readableBytes >= expectedLength else {
                return .needMoreData
            }
            
            let frame = buffer.readSlice(length: expectedLength)!
            state = .waitingLength
            return .continue
        }
    }
}

// MARK: - Outbound: Length-delimited encoder (encode_length_delimited)
func encodeLengthDelimited<T: SwiftProtobuf.Message>(_ message: T, allocator: ByteBufferAllocator) throws -> ByteBuffer {
    let messageData = try message.serializedData()
    var buffer = allocator.buffer(capacity: 5 + messageData.count) // Max varint size = 5 bytes
    
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
