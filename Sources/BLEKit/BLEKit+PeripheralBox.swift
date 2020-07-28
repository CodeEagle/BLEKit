import CoreBluetooth

extension BLEKit {
    public final class PeripheralBox {
        // MARK: - properties

        public let central: CBCentralManager
        public let peripheral: PeripheralCompatible
        public let peripheralId: UUID
        public let advertisementData: AdvertisementData
        public let rssi: NSNumber
        public var didDisconnectHandler: (CBCentralManager, PeripheralCompatible, Swift.Error?) -> Void = { _, _, _ in }
        private var connectHandler: ConnectResult = { _ in }

        private lazy var peripheralDelegator = PeripheralDelegator()
        private lazy var addMonitorOnce = false

        private var connectTimoutTask: CancellableDelayedTask?

        private var operationtimeoutTask: CancellableDelayedTask?

        private let queue: DispatchQueue
        private var isInDisconnect = false
        
        public var validataPeripheral: PeripheralCompatible? {
            return peripheral.isSimulator ? peripheral : (central.retrievePeripherals(withIdentifiers: [peripheralId]).first != nil ? peripheral : nil)
        }

        /// 延迟断开标识符
        private lazy var _delayDisconnect: Bool = false
        private var delayDisconnect: Bool {
            get { return queue.sync { _delayDisconnect } }
            set { queue.async(flags: .barrier) { self._delayDisconnect = newValue } }
        }

        private var _pendingRequest: [Request] = []
        private var pendingRequest: [Request] {
            get { return queue.sync { _pendingRequest } }
            set { queue.async(flags: .barrier) { self._pendingRequest = newValue } }
        }

        // MARK: Read Write Request

        private lazy var _waitForHitRequest: Request = .none
        private var waitForHitRequest: Request {
            get { return queue.sync { _waitForHitRequest } }
            set { queue.async(flags: .barrier) { self._waitForHitRequest = newValue } }
        }
        
        // write without callback take value from notify
        private lazy var _waitForHitNotifyWriteRequest: Request = .none
        private var waitForHitNotifyWriteRequest: Request {
            get { return queue.sync { _waitForHitNotifyWriteRequest } }
            set { queue.async(flags: .barrier) { self._waitForHitNotifyWriteRequest = newValue } }
        }

        private var _handlerForRequest: [Request: ActionResult] = [:]
        private var handlerForRequest: [Request: ActionResult] {
            get { return queue.sync { _handlerForRequest } }
            set { queue.async(flags: .barrier) { self._handlerForRequest = newValue } }
        }

        // MARK: Find Service Request

        private var _waitForHitServiceID: ServiceID = .none
        private var waitForHitServiceID: ServiceID {
            get { return queue.sync { _waitForHitServiceID } }
            set { queue.async(flags: .barrier) { self._waitForHitServiceID = newValue } }
        }

        private var _findServiceHandlerForRequest: [ServiceID: (Result<CBService, BLEKit.Error>) -> Void] = [:]
        private var findServiceHandlerForRequest: [ServiceID: (Result<CBService, BLEKit.Error>) -> Void] {
            get { return queue.sync { _findServiceHandlerForRequest } }
            set { queue.async(flags: .barrier) { self._findServiceHandlerForRequest = newValue } }
        }

        // MARK: Find Characteristic Request

        private lazy var _waitForHitCharacteristicID: CharacteristicID = .none
        private var waitForHitCharacteristicID: CharacteristicID {
            get { return queue.sync { _waitForHitCharacteristicID } }
            set { queue.async(flags: .barrier) { self._waitForHitCharacteristicID = newValue } }
        }

        private var _findCharacteristicHandlerForRequest: [CharacteristicID: (Result<CBCharacteristic, BLEKit.Error>) -> Void] = [:]
        private var findCharacteristicHandlerForRequest: [CharacteristicID: (Result<CBCharacteristic, BLEKit.Error>) -> Void] {
            get { return queue.sync { _findCharacteristicHandlerForRequest } }
            set { queue.async(flags: .barrier) { self._findCharacteristicHandlerForRequest = newValue } }
        }

        // MARK: Notify Request

        private lazy var _waitForHitNotifyRequest: Request = .none
        private var waitForHitNotifyRequest: Request {
            get { return queue.sync { _waitForHitNotifyRequest } }
            set { queue.async(flags: .barrier) { self._waitForHitNotifyRequest = newValue } }
        }

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

        // MARK: - life cycle methods

        deinit {
            peripheral.delegate = nil
            peripheralDelegator.eventPipeline.toggle(enable: false)
            NotificationCenter.default.removeObserver(self)
        }

        public convenience init(_ central: CBCentralManager, _ peripheral: PeripheralCompatible, _ advertisementData: [String: Any], _ rssi: NSNumber) {
            self.init(central: central, peripheral: peripheral, advertisementData: advertisementData, rssi: rssi)
        }

        public init(central: CBCentralManager, peripheral: PeripheralCompatible, advertisementData: [String: Any], rssi: NSNumber) {
            queue = DispatchQueue(label: "PeripheralBox.\(peripheral.name ?? peripheral.identifier.uuidString).propertyqueue", qos: .utility, attributes: .concurrent)
            self.central = central
            self.peripheral = peripheral
            self.peripheralId = peripheral.identifier
            self.advertisementData = AdvertisementData(target: advertisementData)
            self.rssi = rssi
            NotificationCenter.default.addObserver(self, selector: #selector(centralManagerDelegatorEvent(note:)), name: .centralManagerDelegatorEvent, object: nil)
        }
    }
}

// MARK: - extension

// MARK: - methods

// MARK: Public API

extension BLEKit.PeripheralBox {
    /// 连接蓝牙外设
    ///
    /// 多个connect 请求，前一个会马上回调
    ///
    /// - Parameters:
    ///   - timeout: 超时，单位秒，默认值5s
    ///   - options: 可选
    ///   - handler: 结果回调
    /// - Returns:
    public func connect(timeout: TimeInterval = 5, options: [String: Any]? = nil, completion handler: @escaping ConnectResult = { _ in }) {
        if peripheral.state == .connected {
            handler(.success((central, peripheral)))
            return
        }

        addMonitor()

        BLEKit.shared.bleCanUse { [weak self] canUse in

            guard canUse else {
                handler(.failure(.bluetoothNotAvailable))
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let sself = self else { return }
                sself.connectHandler(.failure(.connectCancelByNewRequest))
                sself.connectHandler = handler
                if let p = sself.peripheral as? CBPeripheral {
                    sself.central.connect(p, options: options)
                } else { // Stub Connect
                    sself.peripheral.mockState = .connected
                    BLEKit.shared.centralManagerDelegator.eventPipeline.call(.didConnect((sself.central, sself.peripheral)))
                }

                sself.connectTimoutTask?.cancel()
                sself.connectTimoutTask = CancellableDelayedTask(delay: timeout, task: { [weak self] in
                    guard let sself = self else { return }
                    sself.disconnect()
                    sself.connectHandler(.failure(.connectTimeout(timeout)))
                    sself.connectHandler = { _ in }
                })
            }
        }
    }

    /// 断开连接
    ///
    /// default true, 如果 immediately 是 false 的话，等待所有 Request 执行完毕才断开
    ///
    /// - Parameter immediately: 是否马上断开
    public func disconnect(immediately: Bool = true) {
        isInDisconnect = true
        peripheralDelegator.eventPipeline.toggle(enable: false)
        guard peripheral.state == .connected else {
            didDisconnectHandler(central, peripheral, BLEKit.Error.peripheralNotConnected(peripheral.state))
            return
        }

        addMonitor()

        if immediately {
            peripheral.delegate = nil
        }
        
        if immediately == false, isAllRequestsDone() == false {
            delayDisconnect = true
            return
        }

        if let p = peripheral as? CBPeripheral {
            if delayDisconnect { usleep(200_000) } // 确保上一条数据发送完, 0.2秒
            central.cancelPeripheralConnection(p)
        } else {
            peripheral.mockState = .disconnecting
            BLEKit.shared.centralManagerDelegator.eventPipeline.call(.didDisconnect((central, peripheral, nil)))
            peripheral.mockState = .disconnected
        }
        BLEKit.shared.reset()

        delayDisconnect = false
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
        appendPending(request: request)
    }

    /// 写操作
    ///
    /// - Parameters:
    ///   - request: 请求的服务和特征值
    ///   - request: 需要监听返回的服务和特征值
    ///   - data: 发送的数据
    ///   - needResponse: 是否需要返回值
    ///   - completion: 结果回调
    public func write(request: Request, reponse: Request = .none, data: Data, action: Write = .noResponse(nil)) {
        guard peripheral.state == .connected else {
            notConnectedError(completion: action.handler)
            return
        }

        let type: CBCharacteristicWriteType = action.isWithResponse ? .withResponse : .withoutResponse
        let respRequest = reponse == .none ? request : reponse
        let param: WriteParam = .init(data: data, type: type, action: action.handler, responseRequest: respRequest)
        let pAction: PeripheralAction = .init(peripheral: self, action: .write(request, param))
        BLEKit.shared.request(action: pAction)
        appendPending(request: request)
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
        appendPending(request: request)
    }

    private func notConnectedError(completion: ActionResult?) {
        completion?(.failure(.peripheralNotConnected(peripheral.state)))
    }

    private func doneExecute() {
        cancelTimeoutTask()
        BLEKit.shared.doneExecute()
        guard delayDisconnect == true,
            isAllRequestsDone() else { return }
        disconnect()
    }

    private func isAllRequestsDone() -> Bool {
        return waitForHitRequest == .none
            && waitForHitNotifyRequest == .none
            && waitForHitNotifyWriteRequest == .none
            && pendingRequest.isEmpty
    }
}

// MARK: - Internal Implementation

extension BLEKit.PeripheralBox {
    func perform(action: Action) {
        // 保存结果回调
        guard saveCallback(for: action) else { return }

        // 启动计时器
        startTimeoutMonitor()

        // 如果 peripheral 是模拟器，使用模拟结果
        if peripheral.isSimulator {
            stubPerform(action: action)
            return
        }

        // 发现 服务 和 特征值
        findServiceAndCharateristic(request: action.request) { [weak self] result in
            guard let sself = self else {
                BLEKit.shared.doneExecute()
                return
            }

            switch result {
            case let .failure(error):
                action.handler?(.failure(error))
                BLEKit.dispatchError(error)
                sself.clearWaitRequest(for: action)
                sself.doneExecute()

            case let .success((_, characteristic)):

                // 特征值的属性不包含特定的属性
                if characteristic.properties.contains(action.property) == false {
                    let error: BLEKit.Error = .peripheralCharacteristicPropertiesIllegal(action.property)
                    action.handler?(.failure(error))
                    BLEKit.dispatchError(error)
                    sself.removePending(request: action.request)
                    sself.doneExecute()
                    return
                }

                switch action {
                case .read:
                    sself.peripheral.readValue(for: characteristic)

                case let .write(_, param):
                    sself.peripheral.writeValue(param.data, for: characteristic, type: param.type)
                    if param.type == .withoutResponse { // no repsonse
                        sself.cancelTimeoutTask()
                    }

                case let .notify(_, status):
                    sself.peripheral.setNotifyValue(status.value, for: characteristic)
                }
            }
        }
    }

    /// 保存结果回调
    ///
    /// - Parameter action: 需要执行的 Action
    /// - Returns: 是否保存成功
    private func saveCallback(for action: Action) -> Bool {
        switch action {
        case .read:
            waitForHitRequest = action.request
            handlerForRequest[action.request] = action.handler

        case let .write(_, param):
            guard param.data.isEmpty == false else {
                action.handler?(.failure(.writeDataIsEmpty))
                doneExecute()
                return false
            }
            let q = param.responseRequest
            if action.property == .writeWithoutResponse {
                if q == action.request {// responseRequest not none,  write withou response take value from notify
                    waitForHitRequest = q
                } else { // responseRequest is none, just hit it when handleIsReadyToSendWriteWithoutResponse
                    waitForHitNotifyWriteRequest = q
                }
            } else {
                waitForHitRequest = q
            }
            
            handlerForRequest[q] = action.handler

        case .notify:
            waitForHitNotifyRequest = action.request
            waitForHitNotifyIDs.append(action.request)
            notifyHandlerForRequest[action.request] = action.handler
        }
        return true
    }

    /// 在发现服务的时候失败的话，清除掉等待的状态和事件回调
    ///
    /// - Parameter action: Action
    private func clearWaitRequest(for action: Action) {
        switch action {
        case .read:
            let q = action.request
            guard waitForHitRequest == q else { return }
            waitForHitRequest = .none
            handlerForRequest[q] = nil
            removePending(request: q)

        case let .write(_, param):
            let q = param.responseRequest
            let a = waitForHitRequest == q
            let b = waitForHitNotifyWriteRequest == q
            if a || b {
                if a { waitForHitRequest = .none }
                if b { waitForHitNotifyWriteRequest = .none }
                handlerForRequest[q] = nil
                removePending(request: q)
            }

        case .notify:
            let q = action.request
            guard waitForHitNotifyRequest == q else { return }
            waitForHitNotifyRequest = .none
            notifyHandlerForRequest[q] = nil
            waitForHitNotifyIDs = waitForHitNotifyIDs.filter { $0 != q }
            removePending(request: q)
        }
    }

    private func appendPending(request: Request, method _: String = #function) {
        pendingRequest.append(request)
    }

    private func removePending(request: Request, method _: String = #function) {
        guard let idx = pendingRequest.firstIndex(of: request) else { return }
        pendingRequest.remove(at: idx)
    }

    private func stubPerform(action: Action) {
        switch action {
        case .read:
            peripheral.mockReadValue(for: action)

        case let .write(_, param):
            peripheral.mockWriteValue(param.data, for: action, type: param.type)

        case let .notify(_, status):
            peripheral.mockSetNotifyValue(status.value, for: action)
        }
    }
}

// MARK: - Timeout handler

extension BLEKit.PeripheralBox {
    private func startTimeoutMonitor() {
        cancelTimeoutTask()

        guard let timeout = BLEKit.shared.timeoutPolicy.timeout else { return }
        operationtimeoutTask = .init(delay: timeout, task: { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.handlerTimeout()
            }
        })
    }

    private func handlerTimeout() {
        defer { BLEKit.shared.doneExecute() }

        let timeoutPolicy = BLEKit.shared.timeoutPolicy
        let a = waitForHitRequest != .none
        let b = waitForHitNotifyWriteRequest != .none
        if a || b {
            let req = a ? waitForHitRequest : waitForHitNotifyWriteRequest
            let handler = handlerForRequest[req]

            let error: BLEKit.Error
            if waitForHitServiceID != .none {
                error = .findServiceTimeout(timeoutPolicy, req)
                waitForHitServiceID = .none
            } else if waitForHitCharacteristicID != .none {
                error = .findCharacteristicTimeout(timeoutPolicy, req)
                waitForHitCharacteristicID = .none
            } else {
                error = .timeout(timeoutPolicy, req)
            }
            handler?(.failure(error))
            BLEKit.dispatchError(error)

            handlerForRequest[req] = nil
            if a { waitForHitRequest = .none }
            if b { waitForHitNotifyWriteRequest = .none }
        } else if waitForHitNotifyRequest != .none {
            let handler = notifyHandlerForRequest[waitForHitNotifyRequest]
            let error: BLEKit.Error = .notifySetTimeout(BLEKit.shared.timeoutPolicy, waitForHitNotifyRequest)
            handler?(.failure(error))
            BLEKit.dispatchError(error)
            waitForHitNotifyRequest = .none
        }
        cancelTimeoutTask()
    }

    private func cancelTimeoutTask() {
        operationtimeoutTask?.cancel()
        operationtimeoutTask = nil
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
                    case let .failure(error):
                        handler(.failure(error))
                    case let .success(characteristic):
                        handler(.success((service, characteristic)))
                    }
                })
            }
        }
    }

    private func findService(_ id: ServiceID, completion handler: @escaping (Result<CBService, BLEKit.Error>) -> Void) {
        let idStr = id.id.uppercased()
        if let service = peripheral.services?.filter({ $0.uuid.uuidString.uppercased() == idStr }).first {
            handler(.success(service))
        } else {
            waitForHitServiceID = id
            findServiceHandlerForRequest[id] = handler
            peripheral.discoverServices([CBUUID(string: idStr)])
        }
    }

    private func findCharacteristic(_ id: CharacteristicID, in service: CBService, completion handler: @escaping (Result<CBCharacteristic, BLEKit.Error>) -> Void) {
        let idStr = id.id.uppercased()
        if let service = service.characteristics?.filter({ $0.uuid.uuidString.uppercased() == idStr }).first {
            handler(.success(service))
        } else {
            waitForHitCharacteristicID = id
            findCharacteristicHandlerForRequest[id] = handler
            peripheral.discoverCharacteristics([CBUUID(string: idStr)], for: service)
        }
    }
}

// MARK: AddMonitor

extension BLEKit.PeripheralBox {
    private func addMonitor() {
        guard addMonitorOnce == false else { return }

        addMonitorOnce = true
        addperipheralEventMonitor()
    }

    @objc private func centralManagerDelegatorEvent(note: Notification) {
        guard let event = note.userInfo?["event"] as? BLEKit.CentralManagerDelegator.Event else { return }
        handleCentralEventMonitor(event)
    }

    private func handleCentralEventMonitor(_ event: BLEKit.CentralManagerDelegator.Event) {
        func connectDone(_ central: CBCentralManager, _ peripheral: PeripheralCompatible, _ error: Swift.Error?) {
            connectTimoutTask?.cancel()
            if let e = error {
                let ee: BLEKit.Error = .bleError(e)
                connectHandler(.failure(.bleError(ee)))
                BLEKit.dispatchError(ee)
            } else {
                connectHandler(.success((central, peripheral)))
            }

            connectHandler = { _ in }
        }

        switch event {
        case let .didConnect((central, peripheral)):
            connectDone(central, peripheral, nil)

        case let .didFailToConnect((central, peripheral, error)):
            connectDone(central, peripheral, error)

        case let .didDisconnect((central, peripheral, error)):
            if let e = error {
                let ee: BLEKit.Error = .bleError(e)
                BLEKit.dispatchError(ee)
            }
            didDisconnectHandler(central, peripheral, error)

        case .didDiscover: break
        case .didUpdateState: break
        case .willRestoreState: break
        }
    }

    private func addperipheralEventMonitor() {
        peripheral.delegate = peripheralDelegator
        peripheral.mockDelegate = peripheralDelegator

        peripheralDelegator.eventPipeline.delegate(to: self) { target, event in
            
            guard target.isInDisconnect == false else {
                return
            }
            switch event {
            case let .didDiscoverServices((peripheral, error)):
                target.handleDidDiscoverServices(peripheral: peripheral, error: error)

            case let .didDiscoverIncludedServices((_, service, error)):
                target.handleDidDiscoverIncludedServices(service: service, error: error)

            case let .didDiscoverCharacteristics((_, service, error)):
                target.handleDidDiscoverCharacteristics(service: service, error: error)

            case let .didUpdateCharacteristicValue((_, characteristic, error)):
                target.handleDidUpdateCharacteristicValue(characteristic: characteristic, error: error)

            case let .didUpdateCharacteristicNotificationState(box):
                target.handleDidUpdateCharacteristicNotificationState(box: box)

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
            NotificationCenter.default.post(name: .peripheralDelegatorEvent, object: nil, userInfo: ["event": event])
            DispatchQueue.main.async {
                BLEKit.shared.eventPipeline.call(.peripheralDelegator(event))
            }
        }
    }

    // MARK: peripheral event handler

    private func handleDidDiscoverServices(peripheral: PeripheralCompatible, error: Swift.Error?) {
        if waitForHitServiceID == .none { return }
        
        guard let service = peripheral.services?.filter({ $0.uuid.uuidString.uppercased() == waitForHitServiceID.id.uppercased() }).first else {
            let e: BLEKit.Error = .peripheralServiceNotFound(waitForHitServiceID)
            let handler = findServiceHandlerForRequest[waitForHitServiceID]
            handler?(.failure(e))
            return
        }

        guard let handler = findServiceHandlerForRequest[waitForHitServiceID] else {
            doneExecute()
            return
        }

        if let e = error {
            let ee: BLEKit.Error = .bleError(e)
            handler(.failure(ee))
            BLEKit.dispatchError(ee)
        } else {
            handler(.success(service))
        }

        findServiceHandlerForRequest[waitForHitServiceID] = nil
        waitForHitServiceID = .none
    }

    private func handleDidDiscoverIncludedServices(service _: ServiceCompatible, error _: Swift.Error?) {
        // 未知用途，暂未支持
    }

    private func handleDidDiscoverCharacteristics(service: ServiceCompatible, error: Swift.Error?) {
        guard let char = service.characteristics?.filter({ $0.uuid.uuidString.uppercased() == waitForHitCharacteristicID.id.uppercased() }).first else {
            let e: BLEKit.Error = .peripheralCharacteristicNotFound(waitForHitCharacteristicID)
            let handler = findCharacteristicHandlerForRequest[waitForHitCharacteristicID]
            handler?(.failure(e))
            return
        }

        guard let handler = findCharacteristicHandlerForRequest[waitForHitCharacteristicID] else {
            doneExecute()
            return
        }

        if let e = error {
            let ee: BLEKit.Error = .bleError(e)
            handler(.failure(ee))
            BLEKit.dispatchError(ee)
        } else {
            handler(.success(char))
        }
        findCharacteristicHandlerForRequest[waitForHitCharacteristicID] = nil
        waitForHitCharacteristicID = .none
    }

    private func handleDidUpdateCharacteristicValue(characteristic: CharacteristicCompatible, error: Swift.Error?) {
        guard let p = validataPeripheral else { return }
        let service: ServiceCompatible
        if p.isSimulator {
            service = characteristic.mockService
        } else {
            service = characteristic.service
        }
        let request = Request(characteristic: characteristic, service: service)

        // Read & Notify 都可以读

        if waitForHitNotifyIDs.contains(request) { // Notify callback
            let handler = notifyHandlerForRequest[request]

            if let e = error {
                handler?(.failure(.bleError(e)))
            } else {
                handler?(.success(characteristic.value))
            }
        }

        let a = waitForHitRequest == request
        let b = waitForHitNotifyWriteRequest == request
        if a || b { // Read CallBack
            let handler = handlerForRequest[request]

            if let e = error {
                let ee: BLEKit.Error = .bleError(e)
                handler?(.failure(ee))
                BLEKit.dispatchError(ee)
            } else {
                handler?(.success(characteristic.value))
            }
            removePending(request: request)
            handlerForRequest[request] = nil
            if a { waitForHitRequest = .none }
            if b { waitForHitNotifyWriteRequest = .none }
            doneExecute()
        }
    }

    /// write to enable/disable notify callback
    private func handleDidUpdateCharacteristicNotificationState(box: DidUpdateCharacteristicNotificationStateBox) {
        let characteristic = box.1
        let service: ServiceCompatible = peripheral.isSimulator ? characteristic.mockService : characteristic.service
        let request = Request(characteristic: characteristic, service: service)

        if request == waitForHitNotifyRequest {
            removePending(request: request)
            waitForHitNotifyRequest = .none
        }

        doneExecute()
    }

    /// write without response callback
    private func handleIsReadyToSendWriteWithoutResponse() {
        guard waitForHitRequest != .none else { return }
        //  for write without response still can take result form notify
        if let han = handlerForRequest[waitForHitRequest]{
            han(.success(Data()))
            removePending(request: waitForHitRequest)
            handlerForRequest[waitForHitRequest] = nil
            waitForHitRequest = .none
        }
        doneExecute()
    }

    /// write with response callback
    private func handleDidWriteCharacteristicValue(_ box: DidWriteCharacteristicValueBox) {
        guard waitForHitRequest != .none else { return }
        if #available(iOS 11.0, *) {
            // use iOS 11-only feature
        } else {
            if BLEKit.shared.ignoreDidWriteCharacteristicValueForiOS10 {
                return
            }
        }
        let handler = handlerForRequest[waitForHitRequest]
        if let e = box.error {
            let ee: BLEKit.Error = .bleError(e)
            handler?(.failure(ee))
            BLEKit.dispatchError(ee)
        } else {
            handler?(.success(box.characteristic.value))
        }
        removePending(request: waitForHitRequest)
        handlerForRequest[waitForHitRequest] = nil
        waitForHitRequest = .none
        doneExecute()
    }
}

// MARK: - Typealias FlyBLEKit.PeripheralBox

extension BLEKit.PeripheralBox {
    public typealias PeripheralAction = BLEKit.PeripheralAction
    public typealias ActionResult = PeripheralAction.ActionResult
    public typealias Request = PeripheralAction.Request
    public typealias Action = PeripheralAction.Action
    public typealias NotifyStatus = PeripheralAction.Action.NotifyStatus
    public typealias Write = PeripheralAction.Action.Write
    public typealias WriteParam = PeripheralAction.Action.WriteParam
    public typealias Result = Swift.Result
    public typealias ServiceID = PeripheralAction.ServiceID
    public typealias CharacteristicID = PeripheralAction.CharacteristicID
    public typealias DidWriteCharacteristicValueBox = BLEKit.PeripheralDelegator.DidWriteCharacteristicValueBox
    public typealias DidUpdateCharacteristicNotificationStateBox = BLEKit.PeripheralDelegator.DidUpdateCharacteristicNotificationStateBox
    public typealias ConnectResult = (Result<(CBCentralManager, PeripheralCompatible), BLEKit.Error>) -> Void
}

// MARK: - AdvertisementData

public extension BLEKit.PeripheralBox {
    struct AdvertisementData {
        public let value: [String: Any]
        public init(target: [String: Any]) {
            value = target
        }

        public var isConnectable: Bool? {
            return value[Constants.isConnectable] as? Bool
        }

        public var localName: String? {
            return value[Constants.localName] as? String
        }

        public var serviceUUIDs: [Any] {
            return (value[Constants.serviceUUIDs] as? [Any]) ?? []
        }

        public var manufacturerData: Data? {
            return value[Constants.manufacturerData] as? Data
        }

        public var txPowerLevel: NSNumber? {
            return value[Constants.txPowerLevel] as? NSNumber
        }

        public func read<T>(key: String) -> T? {
            return value[key] as? T
        }

        struct Constants {
            static let isConnectable = "kCBAdvDataIsConnectable"
            static let localName = "kCBAdvDataLocalName"
            static let serviceUUIDs = "kCBAdvDataServiceUUIDs"
            static let manufacturerData = "kCBAdvDataManufacturerData"
            static let txPowerLevel = "kCBAdvDataTxPowerLevel"
        }
    }
}
