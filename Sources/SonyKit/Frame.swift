public enum MessageType: UInt8, Sendable {
    case ack = 0x01
    case command1 = 0x0c
    case command2 = 0x0e
}

public struct Frame: Equatable, Sendable {
    static let startMarker: UInt8 = 0x3e
    static let endMarker: UInt8 = 0x3c
    static let escapeMarker: UInt8 = 0x3d
    static let escapeMask: UInt8 = 0xef

    public var type: UInt8
    public var sequence: UInt8
    public var payload: [UInt8]

    public init(type: MessageType, sequence: UInt8, payload: [UInt8]) {
        self.init(rawType: type.rawValue, sequence: sequence, payload: payload)
    }

    init(rawType: UInt8, sequence: UInt8, payload: [UInt8]) {
        self.type = rawType
        self.sequence = sequence
        self.payload = payload
    }

    public var messageType: MessageType? { MessageType(rawValue: type) }

    public func encoded() -> [UInt8] {
        let length = UInt32(payload.count)
        var body: [UInt8] = [
            type,
            sequence,
            UInt8(truncatingIfNeeded: length >> 24),
            UInt8(truncatingIfNeeded: length >> 16),
            UInt8(truncatingIfNeeded: length >> 8),
            UInt8(truncatingIfNeeded: length),
        ]
        body += payload
        body.append(body.reduce(0, &+))

        var bytes = [Frame.startMarker]
        for byte in body {
            if Frame.isMarker(byte) {
                bytes += [Frame.escapeMarker, byte & Frame.escapeMask]
            } else {
                bytes.append(byte)
            }
        }
        bytes.append(Frame.endMarker)
        return bytes
    }

    static func isMarker(_ byte: UInt8) -> Bool {
        byte == startMarker || byte == endMarker || byte == escapeMarker
    }

    static func decode(escapedBody: ArraySlice<UInt8>) -> Frame? {
        var body: [UInt8] = []
        var iterator = escapedBody.makeIterator()
        while let byte = iterator.next() {
            if byte == escapeMarker {
                guard let escaped = iterator.next() else { return nil }
                body.append(escaped | ~escapeMask)
            } else {
                body.append(byte)
            }
        }

        guard body.count >= 7 else { return nil }
        let checksum = body.removeLast()
        guard body.reduce(0, &+) == checksum else { return nil }

        let declaredLength = body[2...5].reduce(0) { $0 << 8 | Int($1) }
        guard declaredLength == body.count - 6 else { return nil }

        return Frame(rawType: body[0], sequence: body[1], payload: Array(body[6...]))
    }
}

public struct FrameDecoder: Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func append(_ bytes: [UInt8]) -> [Frame] {
        buffer += bytes
        var frames: [Frame] = []

        while let start = buffer.firstIndex(of: Frame.startMarker) {
            guard let end = buffer[start...].firstIndex(of: Frame.endMarker) else {
                buffer.removeSubrange(..<start)
                return frames
            }
            if let frame = Frame.decode(escapedBody: buffer[(start + 1)..<end]) {
                frames.append(frame)
            }
            buffer.removeSubrange(...end)
        }

        buffer.removeAll()
        return frames
    }
}
