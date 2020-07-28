import CoreBluetooth

extension BLEKit {
    static var forbidden: String = "this property is not available"

    public final class PeripheralSimulator: NSObject, PeripheralCompatible {
        // MARK: - properties

        public var delay: TimeInterval = 0

        public var isSimulator: Bool { return true }

        public var mockAdvertisementData: [String: Any] = [:]

        public var mockRSSI: NSNumber = -82

        public var mockState: CBPeripheralState = .disconnected

        public private(set) var mockServices: [ServiceCompatible] = []

        public private(set) var identifier: UUID

        public weak var delegate: CBPeripheralDelegate?

        public weak var mockDelegate: PeripheralDelegator?

        public var name: String?

        public var rssi: NSNumber? { return mockRSSI }

        public var state: CBPeripheralState { return mockState }

        public var services: [CBService]? { return nil }

        public private(set) var canSendWriteWithoutResponse: Bool = true

        private var readStubs: [Request: ReadStub] = [:]

        private var writeStubs: [Request: WriteStub] = [:]

        private var notifyStubs: [Request: NotifyStub] = [:]

        // MARK: - life cycle methods

        public init(identifier: UUID) {
            self.identifier = identifier
        }

        // MARK: - methods

        public func readRSSI() {}
        public func discoverServices(_: [CBUUID]?) {}
        public func discoverIncludedServices(_: [CBUUID]?, for _: CBService) {}
        public func discoverCharacteristics(_: [CBUUID]?, for _: CBService) {}
        public func readValue(for _: CBCharacteristic) {}
        public func maximumWriteValueLength(for _: CBCharacteristicWriteType) -> Int { return 0 }
        public func writeValue(_: Data, for _: CBCharacteristic, type _: CBCharacteristicWriteType) {}
        public func setNotifyValue(_: Bool, for _: CBCharacteristic) {}
        public func discoverDescriptors(for _: CBCharacteristic) {}
        public func readValue(for _: CBDescriptor) {}
        public func writeValue(_: Data, for _: CBDescriptor) {}
        public func openL2CAPChannel(_: CBL2CAPPSM) {}

        // MARK: mock

        /// 模拟 Read 返回
        ///
        /// - Parameter action: Action
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
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let sself = self else { return }
                sself.mockDelegate?.eventPipeline.call(.didUpdateCharacteristicValue((sself, box.0, box.1)))
            }
        }

        /// 模拟 Write 的返回
        ///
        /// - Parameters:
        ///   - data: write 的数据
        ///   - action: Action
        ///   - type: write 的类型
        public func mockWriteValue(_ data: Data, for action: Action, type: CBCharacteristicWriteType) {
            let responseRequest: Request
            if case let Action.write(_, param) = action {
                responseRequest = param.responseRequest
            } else {
                responseRequest = action.request
            }

            let responseChar: CharacteristicCompatible
            if case let Action.write(_, param) = action {
                guard let char = findCharacteristic(request: param.responseRequest) else {
                    fatalError("CharacteristicCompatible For \(param.responseRequest) Not Found")
                }
                responseChar = char
            } else {
                guard let char = findCharacteristic(request: action.request) else {
                    fatalError("CharacteristicCompatible For \(action.request) Not Found")
                }
                responseChar = char
            }

            guard let result = writeStubs[responseRequest] else {
                fatalError("Write Stub For \(responseRequest) Not Found")
            }

            if responseChar.properties.contains(action.property) == false {
                action.handler?(.failure(BLEKit.Error.peripheralCharacteristicPropertiesIllegal(action.property)))
                BLEKit.shared.doneExecute()
                return
            }

            let pipeline = mockDelegate?.eventPipeline
            let box = result(responseChar, data, type)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let sself = self else { return }
                switch type {
                case .withoutResponse:
                    pipeline?.call(.isReadyToSendWriteWithoutResponse(sself))
                case .withResponse:
                    pipeline?.call(.didWriteCharacteristicValue((sself, box.0, box.1)))
                @unknown default:
                    break
                }
            }
        }

        /// 模拟 Notify 的返回
        ///
        /// - Parameters:
        ///   - _: 是否开启 Notify
        ///   - action: Action
        public func mockSetNotifyValue(_: Bool, for action: Action) {
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

        /// 注册模拟的服务
        ///
        /// - Parameter services: 服务列表
        public func addMockServices(_ services: [ServiceCompatible]) {
            mockServices.append(contentsOf: services)
        }

        private func findCharacteristic(request: Request) -> CharacteristicCompatible? {
            return mockServices.filter { $0.uuid.uuidString == request.serviceID.id }.first?.mockCharacteristics.filter { $0.uuid.uuidString == request.characteristicID.id }.first
        }
    }
}

// MARK: - extension

// MARK: - Public API

extension BLEKit.PeripheralSimulator {
    /// 添加 Notify 的模拟服务
    ///
    /// - Parameters:
    ///   - stub: Notify 的行为
    ///   - request: 对应的服务和特征值
    ///   - properties: 特征值属性
    public func registerNotify(stub: @escaping NotifyStub, for request: Request, properties: CBCharacteristicProperties) {
        notifyStubs[request] = stub
        regisertServiceFor(request: request, properties: properties)
    }

    /// 添加 Read 的模拟服务
    ///
    /// - Parameters:
    ///   - stub: Read 的行为
    ///   - request: 对应的服务和特征值
    ///   - properties: 特征值属性
    public func registerRead(stub: @escaping ReadStub, for request: Request, properties: CBCharacteristicProperties) {
        readStubs[request] = stub
        regisertServiceFor(request: request, properties: properties)
    }

    /// 添加 Write 的模拟服务
    ///
    /// - Parameters:
    ///   - stub: Write 的行为
    ///   - request: 对应的服务和特征值
    ///   - properties: 特征值属性
    public func registerWrite(stub: @escaping WriteStub, for request: Request, response: Request = .none, properties: CBCharacteristicProperties) {
        let stubRequest = response != .none ? response : request
        writeStubs[stubRequest] = stub
        regisertServiceFor(request: stubRequest, properties: properties)
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
        @unknown default: return "unknown descriptuin for value: \(rawValue)"
        }
    }
}

// MARK: - MockCharacteristic

extension BLEKit.PeripheralSimulator {
    public final class MockCharacteristic: NSObject, CharacteristicCompatible {
        // MARK: - properties

        public private(set) unowned var mockService: ServiceCompatible

        public private(set) var uuid: CBUUID = CBUUID(nsuuid: UUID())

        public unowned var service: CBService { fatalError(BLEKit.forbidden) }

        public private(set) var properties: CBCharacteristicProperties

        public var value: Data?

        public private(set) var descriptors: [CBDescriptor]?

        public private(set) var isBroadcasted: Bool = false

        public private(set) var isNotifying: Bool = false

        // MARK: - life cycle methods

        /// 初始化
        ///
        /// - Parameters:
        ///   - id: 特征值的 ID
        ///   - service: 对应的服务
        ///   - value: 特征值属性
        public init(id: String, service: ServiceCompatible, properties value: CBCharacteristicProperties) {
            mockService = service
            properties = value
            uuid = CBUUID(string: id)
            super.init()
        }

        /// 复制特定特征值初始化
        ///
        /// - Parameter characteristic: 需要被复制的特征值
        public init(characteristic: CharacteristicCompatible) {
            mockService = characteristic.mockService
            properties = characteristic.properties
            super.init()
            uuid = characteristic.uuid
        }

        // MARK: - methods

        /// 添加特征值属性
        ///
        /// - Parameter value: 特征值属性
        public func addMockProperties(_ value: CBCharacteristicProperties) {
            properties.insert(value)
        }
    }
}

// MARK: - MockService

extension BLEKit.PeripheralSimulator {
    public final class MockService: NSObject, ServiceCompatible {
        // MARK: - properties

        public private(set) var mockCharacteristics: [CharacteristicCompatible] = []

        public private(set) unowned var mockPeripheral: PeripheralCompatible

        public private(set) var uuid: CBUUID = CBUUID(nsuuid: UUID())

        public unowned var peripheral: CBPeripheral { fatalError(BLEKit.forbidden) }

        public private(set) var isPrimary: Bool = false

        public var includedServices: [CBService]? { return nil }

        public var characteristics: [CBCharacteristic]? { return nil }

        // MARK: - life cycle methods

        /// 初始化
        ///
        /// - Parameters:
        ///   - id: 服务的 ID
        ///   - value: 对应的模拟外设
        public init(id: String, peripheral value: PeripheralCompatible) {
            mockPeripheral = value
            uuid = CBUUID(string: id)
            super.init()
        }

        // MARK: - methods

        /// 添加模拟特征值
        ///
        /// - Parameter value: 模拟特征值
        public func addMockCharacteristic(_ value: CharacteristicCompatible) {
            mockCharacteristics.append(value)
        }
    }
}

// MARK: - Typealias

extension BLEKit.PeripheralSimulator {
    public typealias PeripheralDelegator = BLEKit.PeripheralDelegator
    public typealias PeripheralAction = BLEKit.PeripheralAction
    public typealias ActionResult = PeripheralAction.ActionResult
    public typealias Request = PeripheralAction.Request
    public typealias Action = PeripheralAction.Action
    public typealias NotifyStatus = PeripheralAction.Action.NotifyStatus

    public typealias ReadStub = (CharacteristicCompatible) -> (CharacteristicCompatible, Swift.Error?)
    public typealias WriteStub = (CharacteristicCompatible, Data, CBCharacteristicWriteType) -> (CharacteristicCompatible, Swift.Error?)
    public typealias NotifyStub = (CharacteristicCompatible, @escaping (CharacteristicCompatible, Swift.Error?) -> Void) -> (CharacteristicCompatible, Swift.Error?)
}
