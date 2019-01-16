import CoreBluetooth

extension BLEKit {
    public final class PeripheralBox {
        public let central: CBCentralManager
        public let peripheral: PeripheralCompatible
        public let advertisementData: [String: Any]
        public let rssi: NSNumber
        public var didDisconnectHandler: (CBCentralManager, PeripheralCompatible, Swift.Error?) -> Void = { _, _, _ in }
        private var connectHandler: (CBCentralManager, PeripheralCompatible, Swift.Error?) -> Void = { _, _, _ in }

        private lazy var peripheralDelegator = BLEKit.PeripheralDelegator()
        private lazy var addMonitorOnce = false

        private var connectTask: CancellableDelayedTask?

        private let queue: DispatchQueue = DispatchQueue(label: "PeripheralBox.property", qos: .utility, attributes: .concurrent)
        
        private var timeoutTask: CancellableDelayedTask?

        // MARK: Read Write Request

        private lazy var _waitForHitRequest: Request = .none
        private var waitForHitRequest: Request {
            get { return queue.sync { _waitForHitRequest } }
            set { queue.async(flags: .barrier) { self._waitForHitRequest = newValue } }
        }

        private var _handlerForRequest: [Request: ActionResult] = [:]
        private var handlerForRequest: [Request: ActionResult] {
            get { return queue.sync { _handlerForRequest } }
            set { queue.async(flags: .barrier) { self._handlerForRequest = newValue } }
        }

        // MARK: Find Service Request

        private lazy var _waitForHitServiceID: ServiceID = .none
        private var waitForHitServiceID: ServiceID {
            get { return queue.sync { _waitForHitServiceID } }
            set { queue.async(flags: .barrier) { self._waitForHitServiceID = newValue } }
        }

        private var _findServiceHandlerForRequest: [ServiceID: ((Result<CBService, BLEKit.Error>) -> Void)] = [:]
        private var findServiceHandlerForRequest: [ServiceID: ((Result<CBService, BLEKit.Error>) -> Void)] {
            get { return queue.sync { _findServiceHandlerForRequest } }
            set { queue.async(flags: .barrier) { self._findServiceHandlerForRequest = newValue } }
        }

        // MARK: Find Characteristic Request

        private lazy var _waitForHitCharacteristicID: CharacteristicID = .none
        private var waitForHitCharacteristicID: CharacteristicID {
            get { return queue.sync { _waitForHitCharacteristicID } }
            set { queue.async(flags: .barrier) { self._waitForHitCharacteristicID = newValue } }
        }

        private var _findCharacteristicHandlerForRequest: [CharacteristicID: ((Result<CBCharacteristic, BLEKit.Error>) -> Void)] = [:]
        private var findCharacteristicHandlerForRequest: [CharacteristicID: ((Result<CBCharacteristic, BLEKit.Error>) -> Void)] {
            get { return queue.sync { _findCharacteristicHandlerForRequest } }
            set { queue.async(flags: .barrier) { self._findCharacteristicHandlerForRequest = newValue } }
        }

        // MARK: Notify Request

        private lazy var _waitForHitNotifyIDs: [Request] = []
        private var waitForHitNotifyIDs: [Request] {
            get { return queue.sync { _waitForHitNotifyIDs } }
            set { queue.async(flags: .barrier) { self._waitForHitNotifyIDs = newValue } }
        }

        private var _notifyHandlerForRequest: [Request: ActionResult] = [:]
        private var notifyHandlerForRequest: [Request: ActionResult] {
            get { return queue.sync { _notifyHandlerForRequest } }
            set { queue.async(flags: .barrier) { self._notifyHandlerForRequest = newValue } }
        }

        deinit {
            BLEKit.shared.removeCentralEventMonitor(for: peripheral)
        }

        public convenience init(_ central: CBCentralManager, _ peripheral: PeripheralCompatible, _ advertisementData: [String: Any], _ rssi: NSNumber) {
            self.init(central: central, peripheral: peripheral, advertisementData: advertisementData, rssi: rssi)
        }

        public init(central: CBCentralManager, peripheral: PeripheralCompatible, advertisementData: [String: Any], rssi: NSNumber) {
            self.central = central
            self.peripheral = peripheral
            self.advertisementData = advertisementData
            self.rssi = rssi
        }
    }
}

// MARK: Public API

extension BLEKit.PeripheralBox {
    /// 连接蓝牙外设
    ///
    /// - Parameters:
    ///   - options: 可选
    ///   - handler: 结果回调
    /// - Returns:
    public func connect(timeout: TimeInterval = 5, options: [String : Any]? = nil, completion handler: @escaping (CBCentralManager, PeripheralCompatible, Swift.Error?) -> Void = { _, _, _ in }) {

        if peripheral.state == .connected {
            handler(central, peripheral, nil)
            return
        }

        addMonitor()

        BLEKit.shared.bleCanUse { [weak self] canUse in
            guard let sself = self else { return }

            guard canUse else {
                handler(sself.central, sself.peripheral, BLEKit.Error.bluetoothNotAvailable)
                return
            }

            DispatchQueue.main.async {
                sself.connectHandler(sself.central, sself.peripheral, BLEKit.Error.connectCancelByNewRequest)
                sself.connectHandler = handler
                if let p = sself.peripheral as? CBPeripheral {
                    sself.central.connect(p, options: options)
                } else {
                    sself.peripheral.mockState = .connecting
                    sself.peripheral.mockState = .connected
                    BLEKit.shared.centralManagerDelegator.eventPipeline.call(.didConnect((sself.central, sself.peripheral)))
                }

                sself.connectTask?.cancel()
                sself.connectTask = CancellableDelayedTask(delay: timeout, task: { [weak self] in
                    guard let sself = self else { return }
                    sself.disconnect()
                    sself.connectHandler(sself.central, sself.peripheral, BLEKit.Error.connectTimeout(timeout))
                    sself.connectHandler = { _, _, _ in }
                })
            }
        }
    }

    /// 断开连接
    public func disconnect() {
        guard peripheral.state == .connected else {
            didDisconnectHandler(central, peripheral, BLEKit.Error.peripheralNotConnected(peripheral.state))
            return
        }

        addMonitor()
        if let p = peripheral as? CBPeripheral {
            central.cancelPeripheralConnection(p)
        } else {
            peripheral.mockState = .disconnecting
            BLEKit.shared.centralManagerDelegator.eventPipeline.call(.didDisconnect((central, peripheral, nil)))
            peripheral.mockState = .disconnected
        }
    }

    private func notConnectedError(completion: ActionResult?) {
        completion?(.failure(.peripheralNotConnected(peripheral.state)))
    }

    /// 读操作
    ///
    /// - Parameters:
    ///   - request: 服务和特征值
    ///   - completion: 结果回调
    public func read(request: Request, completion: @escaping ActionResult) {
        guard peripheral.state == .connected else {
            notConnectedError(completion: completion)
            return
        }

        let action: PeripheralAction = .init(peripheral: self, action: .read(request, completion))
        BLEKit.shared.request(action: action)
    }

    /// 写操作
    ///
    /// - Parameters:
    ///   - request: 服务和特征值
    ///   - data: 发送的数据
    ///   - needResponse: 是否需要返回值
    ///   - completion: 结果回调
    public func write(request: Request, data: Data, action: Write = .noResponse) {
        guard peripheral.state == .connected else {
            notConnectedError(completion: action.handler)
            return
        }

        let type: CBCharacteristicWriteType = action.isWithResponse ? .withResponse : .withoutResponse
        let action: PeripheralAction = .init(peripheral: self, action: .write(request, data, type, action.handler))
        BLEKit.shared.request(action: action)
    }

    /// 订阅操作
    ///
    /// - Parameters:
    ///   - request: 服务和特征值
    ///   - policy: 开(带回调)或者关
    public func notify(request: Request, policy: NotifyStatus) {
        guard peripheral.state == .connected else {
            notConnectedError(completion: policy.handler)
            return
        }
        let action: PeripheralAction = .init(peripheral: self, action: .notify(request, policy))
        BLEKit.shared.request(action: action)
    }
}

// MARK: - Internal Implementation

extension BLEKit.PeripheralBox {
    func perform(action: Action) {

        if peripheral.isSimulator {
            stubPerform(action: action)
            return
        }

        findServiceAndCharateristic(request: action.request) { [weak self] result in
            guard let sself = self else { return }

            sself.startTimeoutMonitor()

            switch result {
            case let .failure(error): action.handler?(.failure(error))
            case let .success(_, characteristic):

                if characteristic.properties.contains(action.property) == false {
                    action.handler?(.failure(BLEKit.Error.peripheralCharacteristicPropertiesIllegal(action.property)))
                    BLEKit.shared.doneExecute()
                    return
                }

                switch action {
                case .read:
                    sself.performRead(characteristic: characteristic, action: action)

                case let .write(_, data, writeType, _):
                    sself.performWrite(characteristic: characteristic, writeType: writeType, data: data, action: action)

                case let .notify(_, status):
                    sself.performNotify(characteristic: characteristic, value: status.value, action: action)
                }
            }
        }
    }

    private func stubPerform(action: Action) {

        switch action {
        case .read:
            waitForHitRequest = action.request
            handlerForRequest[action.request] = action.handler
            peripheral.mockReadValue(for: action)

        case let .write(_, data, writeType, _):
            waitForHitRequest = action.request
            handlerForRequest[action.request] = action.handler
            peripheral.mockWriteValue(data, for: action, type: writeType)

        case let .notify(_, status):
            notifyHandlerForRequest[action.request] = action.handler
            waitForHitNotifyIDs.append(action.request)
            peripheral.mockSetNotifyValue(status.value, for: action)
        }
    }

    private func performRead(characteristic: CBCharacteristic, action: Action) {
        waitForHitRequest = action.request
        handlerForRequest[action.request] = action.handler
        peripheral.readValue(for: characteristic)
    }

    private func performWrite(characteristic: CBCharacteristic, writeType: CBCharacteristicWriteType, data: Data, action: Action) {
        guard data.isEmpty == false else {
            action.handler?(.failure(BLEKit.Error.writeDataIsEmpty))
            BLEKit.shared.doneExecute()
            return
        }
        waitForHitRequest = action.request
        handlerForRequest[action.request] = action.handler
        peripheral.writeValue(data, for: characteristic, type: writeType)
    }

    private func performNotify(characteristic: CBCharacteristic, value: Bool, action: Action) {
        waitForHitNotifyIDs.append(action.request)
        notifyHandlerForRequest[action.request] = action.handler
        peripheral.setNotifyValue(value, for: characteristic)
    }
}

// MARK: - Timeout handler

extension BLEKit.PeripheralBox {
    private func startTimeoutMonitor() {
        cancelTimeoutTask()

        guard let timeout = BLEKit.shared.timeoutPolicy.timeout else { return }
        timeoutTask = .init(delay: timeout, task: { [weak self] in
            DispatchQueue.main.async {
                self?.handlerTimeout()
            }
        })
    }

    private func handlerTimeout() {
        defer { BLEKit.shared.doneExecute() }
        guard waitForHitRequest != .none else { return  }

        let handler = handlerForRequest[waitForHitRequest]
        handler?(.failure(.timeout(BLEKit.shared.timeoutPolicy)))
        handlerForRequest[waitForHitRequest] = nil
        waitForHitRequest = .none
    }

    private func cancelTimeoutTask() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }
}

// MARK: - Found Service and Characteristic

extension BLEKit.PeripheralBox {
    private func findServiceAndCharateristic(request: Request, completion handler: @escaping (Result<(CBService, CBCharacteristic), BLEKit.Error>) -> Void) {
        findService(request.serviceID) { [weak self] resultOne in
            guard let sself = self else { return }

            switch resultOne {
            case let .failure(error): handler(.failure(error))
            case let .success(service):
                sself.findCharacteristic(request.characteristicID, in: service, completion: { resultTwo in
                    switch resultTwo {
                    case let .failure(error): handler(.failure(error))
                    case let .success(characteristic): handler(.success((service, characteristic)))
                    }
                })
            }
        }
    }

    private func findService(_ id: ServiceID, completion handler: @escaping (Result<CBService, BLEKit.Error>) -> Void) {
        if let service = peripheral.services?.filter({ $0.uuid.uuidString == id.id }).first {
            handler(.success(service))
        } else {
            waitForHitServiceID = id
            findServiceHandlerForRequest[id] = handler
            peripheral.discoverServices([CBUUID(string: id.id)])
        }
    }

    private func findCharacteristic(_ id: CharacteristicID, in service: CBService, completion handler: @escaping (Result<CBCharacteristic, BLEKit.Error>) -> Void) {
        if let service = service.characteristics?.filter({ $0.uuid.uuidString == id.id }).first {
            handler(.success(service))
        } else {
            waitForHitCharacteristicID = id
            findCharacteristicHandlerForRequest[id] = handler
            peripheral.discoverCharacteristics([CBUUID(string: id.id)], for: service)
        }
    }
}

// MARK: AddMonitor

extension BLEKit.PeripheralBox {
    private func addMonitor() {
        guard addMonitorOnce == false else { return }

        addMonitorOnce = true
        addperipheralEventMonitor()
        addCentralEventMonitor()
    }

    private func addCentralEventMonitor() {
        BLEKit.shared.addCentralEventMonitor(for: peripheral) { [weak self] event in
            guard let sself = self else { return }

            func connectDone(_ central: CBCentralManager, _ peripheral: PeripheralCompatible, _ error: Swift.Error?) {
                sself.connectTask?.cancel()
                sself.connectHandler(central, peripheral, nil)
                sself.connectHandler = { _, _, _ in }
            }

            switch event {
            case let .didConnect(central, peripheral):
                connectDone(central, peripheral, nil)

            case let .didFailToConnect(central, peripheral, error):
                connectDone(central, peripheral, error)

            case let .didDisconnect(central, peripheral, error):
                sself.didDisconnectHandler(central, peripheral, error)

            case .didDiscover: break
            case .didUpdateState: break
            case .willRestoreState: break
            }
        }
    }

    private func addperipheralEventMonitor() {
        peripheral.delegate = peripheralDelegator
        peripheral.mockDelegate = peripheralDelegator

        peripheralDelegator.eventPipeline.delegate(to: self) { target, event in
            DispatchQueue.main.async {
                switch event {
                case let .didDiscoverServices(peripheral, error):
                    target.handleDidDiscoverServices(peripheral: peripheral, error: error)

                case let .didDiscoverIncludedServices(_, service, error):
                    target.handleDidDiscoverIncludedServices(service: service, error: error)

                case let .didDiscoverCharacteristics(_, service, error):
                    target.handleDidDiscoverCharacteristics(service: service, error: error)

                case let .didUpdateCharacteristicValue(_, characteristic, error):
                    target.handleDidUpdateCharacteristicValue(characteristic: characteristic, error: error)

                case .didUpdateCharacteristicNotificationState:
                    target.handleDidUpdateCharacteristicNotificationState()

                case .isReadyToSendWriteWithoutResponse:
                    target.handleIsReadyToSendWriteWithoutResponse()

                case let .didWriteCharacteristicValue(box):
                    target.handleDidWriteCharacteristicValue(box)

                case .didDiscoverCharacteristicDescriptors: break
                case .didUpdateDescriptorValue: break
                case .didWriteDescriptorValue: break
                case .didOpenChannel: break
                case .didUpdateName: break
                case .didModifyServices: break
                case .didUpdateRSSI: break
                case .didReadRSSI: break
                }

                BLEKit.shared.eventPipeline.call(.peripheralDelegator(event))
            }
        }
    }

    // MARK: peripheral event handler
    private func handleDidDiscoverServices(peripheral: PeripheralCompatible, error: Swift.Error?) {
        guard let service = peripheral.services?.filter({ $0.uuid.uuidString == waitForHitServiceID.id }).first,
            let handler = findServiceHandlerForRequest[waitForHitServiceID] else { return }
        if let e = error {
            handler(.failure(.bleError(e)))
        } else {
            handler(.success(service))
        }

        findServiceHandlerForRequest[waitForHitServiceID] = nil
        waitForHitServiceID = .none
    }

    private func handleDidDiscoverIncludedServices(service: ServiceCompatible, error: Swift.Error?) {
        guard let char = service.characteristics?.filter({ $0.uuid.uuidString == waitForHitCharacteristicID.id }).first,
            let handler = findCharacteristicHandlerForRequest[waitForHitCharacteristicID] else { return }

        if let e = error {
            handler(.failure(.bleError(e)))
        } else {
            handler(.success(char))
        }
        findCharacteristicHandlerForRequest[waitForHitCharacteristicID] = nil
        waitForHitCharacteristicID = .none
    }

    private func handleDidDiscoverCharacteristics(service: ServiceCompatible, error: Swift.Error?) {
        guard let char = service.characteristics?.filter({ $0.uuid.uuidString == waitForHitCharacteristicID.id }).first,
            let handler = findCharacteristicHandlerForRequest[waitForHitCharacteristicID] else { return }

        if let e = error {
            handler(.failure(.bleError(e)))
        } else {
            handler(.success(char))
        }
        findCharacteristicHandlerForRequest[waitForHitCharacteristicID] = nil
        waitForHitCharacteristicID = .none
    }

    private func handleDidUpdateCharacteristicValue(characteristic: CharacteristicCompatible, error: Swift.Error?) {
        let service: ServiceCompatible
        if peripheral.isSimulator {
            service = characteristic.mockService
        } else {
            service = characteristic.service
        }
        let request = Request(characteristic: characteristic, service: service)

        if waitForHitRequest == request { // Read CallBack

            let handler = handlerForRequest[request]

            if let e = error {
                handler?(.failure(.bleError(e)))
            } else {
                handler?(.success(characteristic.value))
            }

            handlerForRequest[request] = nil
            waitForHitRequest = .none
            cancelTimeoutTask()
            BLEKit.shared.doneExecute()

        } else if waitForHitNotifyIDs.contains(request) { // Notify callback

            let handler = notifyHandlerForRequest[request]

            if let e = error {
                handler?(.failure(.bleError(e)))
            } else {
                handler?(.success(characteristic.value))
            }
        }
    }

    /// write to enable/disable notify callback
    private func handleDidUpdateCharacteristicNotificationState() {
        cancelTimeoutTask()
        BLEKit.shared.doneExecute()
    }

    /// write without response callback
    private func handleIsReadyToSendWriteWithoutResponse() {
        guard waitForHitRequest != .none,
            handlerForRequest[waitForHitRequest] == nil else { return }
        
        handlerForRequest[waitForHitRequest] = nil
        waitForHitRequest = .none
        cancelTimeoutTask()
        BLEKit.shared.doneExecute()
    }

    /// write with response callback
    private func handleDidWriteCharacteristicValue(_ box: DidWriteCharacteristicValueBox) {
        guard waitForHitRequest != .none else { return }

        let handler = handlerForRequest[waitForHitRequest]
        if let e = box.error {
            handler?(.failure(.bleError(e)))
        } else {
            handler?(.success(box.characteristic.value))
        }
        
        handlerForRequest[waitForHitRequest] = nil
        waitForHitRequest = .none
        cancelTimeoutTask()
        BLEKit.shared.doneExecute()
    }
}
