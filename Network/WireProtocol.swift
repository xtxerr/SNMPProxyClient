import Foundation

/// Wire protocol for length-delimited protobuf messages.
/// Format: [varint length][protobuf payload]
/// Compatible with Go's google.golang.org/protobuf/encoding/protodelim
enum WireProtocol {
    
    /// Frame a message with varint length prefix
    static func frame(_ data: Data) -> Data {
        var framed = Data()
        framed.append(contentsOf: encodeVarint(UInt64(data.count)))
        framed.append(data)
        return framed
    }
    
    /// Encode a UInt64 as varint bytes
    private static func encodeVarint(_ value: UInt64) -> [UInt8] {
        var v = value
        var result: [UInt8] = []
        
        while v > 0x7F {
            result.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        result.append(UInt8(v))
        
        return result
    }
    
    /// Parser for extracting complete messages from a byte stream
    class Parser {
        private var buffer = Data()
        private let maxMessageSize: Int
        
        init(maxMessageSize: Int = 16 * 1024 * 1024) {
            self.maxMessageSize = maxMessageSize
        }
        
        /// Append received data to buffer
        func append(_ data: Data) {
            buffer.append(data)
        }
        
        /// Extract complete messages from buffer
        /// Returns array of complete message payloads
        func extractMessages() -> [Data] {
            var messages: [Data] = []
            
            while !buffer.isEmpty {
                // Try to decode varint length
                guard let (length, varintSize) = decodeVarint() else {
                    break // Need more data for varint
                }
                
                let messageLength = Int(length)
                
                // Sanity check
                guard messageLength <= maxMessageSize else {
                    // Protocol error - clear buffer
                    print("WireProtocol: message too large (\(messageLength) > \(maxMessageSize))")
                    buffer.removeAll()
                    break
                }
                
                // Check if complete message available
                let totalLength = varintSize + messageLength
                guard buffer.count >= totalLength else {
                    break // Need more data for payload
                }
                
                // Extract message payload
                let messageData = buffer.subdata(in: varintSize..<totalLength)
                messages.append(messageData)
                
                // Remove processed bytes from buffer
                buffer.removeSubrange(0..<totalLength)
            }
            
            return messages
        }
        
        /// Decode varint from start of buffer
        /// Returns (value, bytesConsumed) or nil if incomplete
        private func decodeVarint() -> (value: UInt64, size: Int)? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            
            for i in 0..<min(buffer.count, 10) { // Varint max 10 bytes for uint64
                let byte = buffer[i]
                result |= UInt64(byte & 0x7F) << shift
                
                if byte & 0x80 == 0 {
                    // MSB not set = last byte
                    return (result, i + 1)
                }
                
                shift += 7
                
                // Overflow protection
                if shift > 63 {
                    return nil
                }
            }
            
            // Need more bytes
            return nil
        }
        
        /// Reset parser state
        func reset() {
            buffer.removeAll()
        }
        
        /// Current buffer size (for debugging)
        var bufferedBytes: Int {
            buffer.count
        }
    }
}
