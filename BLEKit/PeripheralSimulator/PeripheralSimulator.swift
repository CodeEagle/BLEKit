import CoreBluetooth

extension BLEKit {
    static var forbidden: String = "this property is not available"

    public final class PeripheralSimulator: NSObject, PeripheralCompatible {
        public var isSimulator: Bool { return true }

        public var mockAdvertisementData: [String : Any] = [:]

        public var mockRSSI: NSNumber = -82

        public var mockState: CBPeripheralState = .disconnected
        
        public private(set) var mockServices: [ServiceCompatible] = []

        public private(set) var identifier: UUID

        public weak var delegate: CBPeripheralDelegate? = nil

        public weak var mockDelegate: PeripheralDelegator? = nil

        public var name: String?

        public var rssi: NSNumber? { return mockRSSI }

        public var state: CBPeripheralState { return mockState }

        public var services: [CBService]? { return nil }

        public private(set) var canSendWriteWithoutResponse: Bool = true

        private var readStubs: [Request : ReadStub] = [:]

        private var writeStubs: [Request : WriteStub] = [:]

        private var notifyStubs: [Request : NotifyStub] = [:]

        public init(identifier: UUID) {
            self.identifier = identifier
        }

        public func readRSSI() { }
        public func discoverServices(_ serviceUUIDs: [CBUUID]?) { }
        public func discoverIncludedServices(_ includedServiceUUIDs: [CBUUID]?, for service: CBService) { }
        public func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService) { }
        public func readValue(for characteristic: CBCharacteristic) { }
        public func maximumWriteValueLength(for type: CBCharacteristicWriteType) -> Int { return 0 }
        public func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) { }
        public func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic) { }
        public func discoverDescriptors(for characteristic: CBCharacteristic) { }
        public func readValue(for descriptor: CBDescriptor) { }
        public func writeValue(_ data: Data, for descriptor: CBDescriptor) { }
        public func openL2CAPChannel(_ PSM: CBL2CAPPSM) { }

        // MARK: mock
        public func mockReadValue(for action: Action) {
            guard let result = readStubs[action.request] else {
                fatalError("Read Stub For \(action.request) Not Found")
            }
            guard let char = findCharacteristic(request: action.request) else {
                fatalError("CharacteristicCompatible For \(action.request) Not Found")
            }
            if char.properties.contains(action.property) == false {
                action.handler?(.failure(BLEKit.Error.peripheralCharacteristicPropertiesIllegal(action.property)))
                BLEKit.shared.doneExecute()
                return
            }
            let box = result(char)
            mockDelegate?.eventPipeline.call(.didUpdateCharacteristicValue((self, box.0, box.1)))
        }

        public func mockWriteValue(_ data: Data, for action: Action, type: CBCharacteristicWriteType) {
            guard let result = writeStubs[action.request] else {
                fatalError("Write Stub For \(action.request) Not Found")
            }
            guard let char = findCharacteristic(request: action.request) else {
                fatalError("CharacteristicCompatible For \(action.request) Not Found")
            }
            if char.properties.contains(action.property) == false {
                action.handler?(.failure(BLEKit.Error.peripheralCharacteristicPropertiesIllegal(action.property)))
                BLEKit.shared.doneExecute()
                return
            }
            let pipeline = mockDelegate?.eventPipeline
            let box = result(char, data, type)
            switch type {
            case .withoutResponse:
                pipeline?.call(.isReadyToSendWriteWithoutResponse(self))
            case .withResponse:
                pipeline?.call(.didWriteCharacteristicValue((self, box.0, box.1)))
            }
        }

        public func mockSetNotifyValue(_ enabled: Bool, for action: Action) {
            guard let result = notifyStubs[action.request] else {
                fatalError("Write Stub For \(action.request) Not Found")
            }
            guard let char = findCharacteristic(request: action.request) else {
                fatalError("CharacteristicCompatible For \(action.request) Not Found")
            }
            if char.properties.contains(action.property) == false {
                action.handler?(.failure(BLEKit.Error.peripheralCharacteristicPropertiesIllegal(action.property)))
                BLEKit.shared.doneExecute()
                return
            }
            let resultExecutor: (CharacteristicCompatible, Swift.Error?) -> Void = { [weak self] char, error in
                guard let sself = self else { return }
                sself.mockDelegate?.eventPipeline.call(.didUpdateCharacteristicValue((sself, char, error)))
            }
            let box = result(char, resultExecutor)
            let pipeline = mockDelegate?.eventPipeline
            pipeline?.call(.didUpdateCharacteristicNotificationState((self, box.0, box.1)))
        }

        public func addMockServices(_ services: [ServiceCompatible]) {
            mockServices.append(contentsOf: services)
        }

        private func findCharacteristic(request: Request) -> CharacteristicCompatible? {
            return mockServices.filter { $0.uuid.uuidString == request.serviceID.id }.first?.mockCharacteristics.filter { $0.uuid.uuidString == request.characteristicID.id }.first
        }

        // MARK: description
        public override var description: String {
            return "<BLEKit.PeripheralSimulator id:\(identifier), RSSI: \(mockRSSI), state: \(state)>"
        }
    }
}
// MARK: - Open API
extension BLEKit.PeripheralSimulator {

    public func registerNotify(stub: @escaping NotifyStub, for request: Request, properties: CBCharacteristicProperties) {
        notifyStubs[request] = stub
        regisertServiceFor(request: request, properties: properties)
    }

    public func registerRead(stub: @escaping ReadStub, for request: Request, properties: CBCharacteristicProperties) {
        readStubs[request] = stub
        regisertServiceFor(request: request, properties: properties)
    }

    public func registerWrite(stub: @escaping WriteStub, for request: Request, properties: CBCharacteristicProperties) {
        writeStubs[request] = stub
        regisertServiceFor(request: request, properties: properties)
    }

    private func regisertServiceFor(request: Request, properties: CBCharacteristicProperties) {
        if let old = findCharacteristic(request: request) {
            old.addMockProperties(properties)
            return
        }

        let service: MockService
        let item = mockServices.filter { $0.uuid.uuidString == request.serviceID.id }.first as? MockService
        if let value = item {
            service = value
        } else {
            let value = MockService(id: request.serviceID.id, peripheral: self)
            mockServices.append(value)
            service = value
        }
        let mockChar = MockCharacteristic(id: request.characteristicID.id, service: service, properties: properties)
        service.addMockCharacteristic(mockChar)
    }
}


// MARK: - CBPeripheralState@CustomStringConvertible
extension CBPeripheralState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .connected: return "CBPeripheralState.connected"
        case .connecting: return "CBPeripheralState.connecting"
        case .disconnected: return "CBPeripheralState.disconnected"
        case .disconnecting: return "CBPeripheralState.disconnecting"
        }
    }
}
