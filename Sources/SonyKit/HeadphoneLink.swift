import Foundation
@preconcurrency import IOBluetooth
import os

enum SonyService {
    private static let protocolV1Bytes: [UInt8] = [
        0x96, 0xcc, 0x20, 0x3e, 0x50, 0x68, 0x46, 0xad,
        0xb3, 0x2d, 0xe3, 0x16, 0xf5, 0xe0, 0x69, 0xba,
    ]
    private static let protocolV2Bytes: [UInt8] = [
        0x95, 0x6c, 0x7b, 0x26, 0xd4, 0x9a, 0x4b, 0xa8,
        0xb0, 0x3f, 0xb1, 0x7d, 0x39, 0x3c, 0xb6, 0xe2,
    ]

    static var protocolV1: IOBluetoothSDPUUID { IOBluetoothSDPUUID(bytes: protocolV1Bytes, length: protocolV1Bytes.count) }
    static var protocolV2: IOBluetoothSDPUUID { IOBluetoothSDPUUID(bytes: protocolV2Bytes, length: protocolV2Bytes.count) }

    static func controlChannelID(of device: IOBluetoothDevice) -> BluetoothRFCOMMChannelID? {
        guard let record = device.getServiceRecord(for: protocolV1) else { return nil }
        var channelID: BluetoothRFCOMMChannelID = 0
        return record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess ? channelID : nil
    }

    static func usesNewerProtocol(_ device: IOBluetoothDevice) -> Bool {
        device.getServiceRecord(for: protocolV2) != nil
    }
}

@MainActor
final class HeadphoneLink: NSObject, IOBluetoothRFCOMMChannelDelegate {
    enum Status: Equatable {
        case opening
        case open
        case closed(reason: String?)
    }

    private static let log = Logger(subsystem: "dev.local.SonyControl", category: "link")
    private static let ackTimeout: Duration = .milliseconds(1500)
    private static let openTimeout: Duration = .seconds(4)
    private static let maxOpenAttempts = 3
    private static let maxSendAttempts = 3

    let device: IOBluetoothDevice
    var onStatus: ((Status) -> Void)?
    var onEvent: ((HeadphoneEvent) -> Void)?

    private var channel: IOBluetoothRFCOMMChannel?
    private var decoder = FrameDecoder()
    private var sequence: UInt8 = 0
    private var queue: [Request] = []
    private var inFlight: (request: Request, attempt: Int)?
    private var ackTimeoutTask: Task<Void, Never>?
    private var openTimeoutTask: Task<Void, Never>?
    private var openAttempt = 0
    private var isOpen = false

    init(device: IOBluetoothDevice) {
        self.device = device
    }

    func open() {
        onStatus?(.opening)
        openAttempt = 0
        attemptOpen()
    }

    private func attemptOpen() {
        openAttempt += 1
        startOpenTimeout()
        if let channelID = SonyService.controlChannelID(of: device) {
            openChannel(channelID)
        } else {
            device.performSDPQuery(self)
        }
    }

    func close() {
        openTimeoutTask?.cancel()
        ackTimeoutTask?.cancel()
        channel?.setDelegate(nil)
        channel?.close()
        channel = nil
        isOpen = false
        inFlight = nil
        queue.removeAll()
    }

    func send(_ request: Request) {
        if let index = queue.firstIndex(where: { $0.type == request.type && $0.coalescingKey == request.coalescingKey }) {
            queue[index] = request
        } else {
            queue.append(request)
        }
        sendNext()
    }

    private func startOpenTimeout() {
        openTimeoutTask?.cancel()
        openTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.openTimeout)
            guard !Task.isCancelled, let self, !self.isOpen else { return }
            self.openTimedOut()
        }
    }

    private func openTimedOut() {
        channel?.setDelegate(nil)
        channel?.close()
        channel = nil
        if openAttempt < Self.maxOpenAttempts {
            attemptOpen()
        } else {
            finish(reason: "The headphones did not answer. Try again, or turn the headphones off and on.")
        }
    }

    private func openChannel(_ channelID: BluetoothRFCOMMChannelID) {
        var opened: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&opened, withChannelID: channelID, delegate: self)
        guard result == kIOReturnSuccess, let opened else {
            finish(reason: "Could not open the control channel (error \(result)).")
            return
        }
        channel = opened
    }

    private func didOpen(status: IOReturn) {
        guard status == kIOReturnSuccess else {
            finish(reason: "The headphones refused the control channel (error \(status)). Try again, or turn the headphones off and on.")
            return
        }
        isOpen = true
        openTimeoutTask?.cancel()
        onStatus?(.open)
        send(SonyCommand.initialize)
    }

    private func sdpQueryFinished() {
        if let channelID = SonyService.controlChannelID(of: device) {
            openChannel(channelID)
        } else if SonyService.usesNewerProtocol(device) {
            finish(reason: "This headphone model uses a newer Sony protocol. This app supports WH-1000XM3 and WH-1000XM4.")
        } else {
            finish(reason: "This device does not offer the Sony control service.")
        }
    }

    private func finish(reason: String?) {
        guard channel != nil || reason != nil else { return }
        close()
        onStatus?(.closed(reason: reason))
    }

    private func sendNext() {
        guard inFlight == nil, isOpen, !queue.isEmpty else { return }
        transmit(queue.removeFirst(), attempt: 1)
    }

    private func transmit(_ request: Request, attempt: Int) {
        inFlight = (request, attempt)
        write(Frame(type: request.type, sequence: sequence, payload: request.payload))
        ackTimeoutTask?.cancel()
        ackTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.ackTimeout)
            guard !Task.isCancelled else { return }
            self?.ackTimedOut()
        }
    }

    private func ackTimedOut() {
        guard let inFlight else { return }
        self.inFlight = nil
        if inFlight.attempt < Self.maxSendAttempts {
            transmit(inFlight.request, attempt: inFlight.attempt + 1)
        } else {
            Self.log.error("No ACK for payload \(Self.hex(inFlight.request.payload), privacy: .public)")
            sendNext()
        }
    }

    private func receive(_ bytes: [UInt8]) {
        for frame in decoder.append(bytes) {
            Self.log.debug("RX type \(frame.type) seq \(frame.sequence) payload \(Self.hex(frame.payload), privacy: .public)")
            switch frame.messageType {
            case .ack:
                sequence = frame.sequence
                inFlight = nil
                ackTimeoutTask?.cancel()
                sendNext()
            case .command1, .command2:
                acknowledge(frame)
                if let type = frame.messageType, let event = HeadphoneEvent(type: type, payload: frame.payload) {
                    onEvent?(event)
                }
            case nil:
                break
            }
        }
    }

    private func acknowledge(_ frame: Frame) {
        write(Frame(type: .ack, sequence: 1 &- frame.sequence, payload: []))
    }

    private func write(_ frame: Frame) {
        guard let channel else { return }
        Self.log.debug("TX type \(frame.type) seq \(frame.sequence) payload \(Self.hex(frame.payload), privacy: .public)")
        var bytes = frame.encoded()
        let result = channel.writeSync(&bytes, length: UInt16(bytes.count))
        if result != kIOReturnSuccess {
            Self.log.error("Write failed with error \(result)")
        }
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    nonisolated private func onMainThread(_ work: @escaping @Sendable @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    nonisolated func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        onMainThread { self.didOpen(status: error) }
    }

    nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = [UInt8](UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        onMainThread { self.receive(bytes) }
    }

    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        onMainThread { self.finish(reason: nil) }
    }

    @objc nonisolated func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        onMainThread { self.sdpQueryFinished() }
    }
}
