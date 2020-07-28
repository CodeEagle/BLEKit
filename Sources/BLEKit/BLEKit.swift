import CoreBluetooth

public final class BLEKit {
    public static let shared = BLEKit()

    // MARK: - properties

    /// 外设模拟器开启策略
    public lazy var peripheralStubPolicy: PeripheralStubPolicy = .disable
    /// 蓝牙通讯超时策略
    public lazy var timeoutPolicy: TimeoutPolicy = .disable
    /// iOS 10 write withou response 会调起此函数
    public var ignoreDidWriteCharacteristicValueForiOS10 = false

    // MARK: 中心控制器和设备控制器

    public private(set) lazy var centralManager: CBCentralManager = {
        var option: [String: Any] = [CBCentralManagerOptionShowPowerAlertKey: false]
        let info = Bundle.main.infoDictionary

        // 后台模式
        if let backgroundArr = info?["UIBackgroundModes"] as? [String],
            backgroundArr.contains("bluetooth-central") {
            let identifier = Constants.EquipmentRestoreIdentifier
            option[CBCentralManagerOptionRestoreIdentifierKey] = identifier
        }
        /// 先添加 delegate，再去初始化，不然会漏掉事件
        addEventMotinor()
        let centralManager = CBCentralManager(delegate: centralManagerDelegator, queue: bleQueue, options: option)
        return centralManager
    }()

    /// 蓝牙状态
    ///
    /// 变更会发送通知 Notification.Name.BluetoothStateChanged
    ///
    /// userInfo 结构为 ["state" : bleState]
    public private(set) var bleState: CBManagerState {
        get { return queue.sync { _bleState } }
        set { queue.async(flags: .barrier) { self._bleState = newValue } }
    }

    private var _bleState: CBManagerState = .unknown {
        didSet {
            let info: [AnyHashable: Any] = ["state": _bleState]
            eventPipeline.call(.state(_bleState))
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .BluetoothStateChanged, object: nil, userInfo: info)
            }
        }
    }

    /// 事件流输出管道
    public private(set) lazy var eventPipeline = Delegated<Event, Void>()

    private(set) lazy var centralManagerDelegator = CentralManagerDelegator()

    private let bleQueue: DispatchQueue = DispatchQueue(label: BLEKit.Constants.BLEQueueName, qos: .userInitiated, attributes: .concurrent)

    // MARK: CentralManager Scan

    private var scanCompletionHandler: (Result<[PeripheralBox], BLEKit.Error>) -> Void = { _ in }
    private var scanDidFindOneHandler: (PeripheralBox) -> Void = { _ in }
    private var scanFilter: ((PeripheralBox) -> Bool)?
    private lazy var scanedPeripherals: [PeripheralBox] = []
    private var scanTask: CancellableDelayedTask?

    private let queue: DispatchQueue = DispatchQueue(label: BLEKit.Constants.PropertyQueue, qos: .utility, attributes: .concurrent)

    private var _isReadyForReadWriteRequest = true
    private var isReadyForReadWriteRequest: Bool {
        get { return queue.sync { _isReadyForReadWriteRequest } }
        set { queue.async(flags: .barrier) { self._isReadyForReadWriteRequest = newValue } }
    }

    private var _requestActions: [PeripheralAction] = []
    private var requestActions: [PeripheralAction] {
        get { return queue.sync { _requestActions } }
        set { queue.async(flags: .barrier) { self._requestActions = newValue } }
    }

    private var _isSearching = false
    private var isSearching: Bool {
        get { return queue.sync { _isSearching } }
        set { queue.async(flags: .barrier) { self._isSearching = newValue } }
    }

    // MARK: - life cycle methods

    private init() {}

    public func startDetect() { _ = centralManager }
    public func reset() {
        isReadyForReadWriteRequest = true
        requestActions = []
    }
}

// MARK: - extension

// MARK: - methods

// MARK: - Public API

extension BLEKit {
    /**
     扫描蓝牙外设

     多个搜索请求，前一个会被取消，返回被取消的错误

     - Parameters:
     - timeout: 在规定时间内的扫描，默认5秒
     - filter: 搜索结果过滤器
     - serviceUUID: 指定搜索限定的服务ID列表
     - options: 可选属性
     - didFindOne: 每当找到一个外设时候的回调
     - completion: 在到达时间后，返回该时间段搜索的结果，如果没有可用的外设，则返回超时错误
     - Returns:
     */
    public func scan(timeout: TimeInterval = 5,
                     filter: ((PeripheralBox) -> Bool)? = nil,
                     serviceUUID: [String]? = nil,
                     options: [CBCentralManagerScanOption: Any]? = nil,
                     didFindOne: @escaping (PeripheralBox) -> Void = { _ in },
                     completion handler: @escaping (Result<[PeripheralBox], BLEKit.Error>) -> Void = { _ in }) {
        reset()
        stopScan(isNewScanComing: true)
        startDetect()
        scanCompletionHandler = handler
        scanDidFindOneHandler = didFindOne
        scanFilter = filter
        bleCanUse { [weak self] canUse in
            guard let sself = self else { return }

            guard canUse else {
                handler(.failure(.bluetoothNotAvailable))
                return
            }

            if let mockPeripherals = sself.peripheralStubPolicy.peripherals {
                let boxs = mockPeripherals.compactMap { item -> PeripheralBox? in
                    let box = PeripheralBox(sself.centralManager, item, item.mockAdvertisementData, item.mockRSSI)
                    if let filter = sself.scanFilter {
                        if filter(box) == true {
                            sself.scanDidFindOneHandler(box)
                            return box
                        }
                    } else {
                        sself.scanDidFindOneHandler(box)
                        return box
                    }
                    return nil
                }
                sself.scanedPeripherals = boxs
                sself.scanDidComplete(isNewScanComing: false)
            } else {
                let uuid = serviceUUID?.compactMap { CBUUID(string: $0) }
                let opts = options?.flyMap { ($0.rawValue, $1) }
                sself.isSearching = true
                sself.centralManager.scanForPeripherals(withServices: uuid, options: opts)
                sself.scanTask = CancellableDelayedTask(delay: timeout, task: { [weak sself] in
                    sself?.scanDidComplete(isNewScanComing: false)
                })
            }
        }
    }

    /// 停止扫描
    public func stopScan() {
        stopScan(isNewScanComing: false)
    }

    private func stopScan(isNewScanComing: Bool) {
        scanDidComplete(isNewScanComing: isNewScanComing)
        scanedPeripherals = []
        scanTask?.cancel()
    }

    private func scanDidComplete(isNewScanComing: Bool, error: BLEKit.Error? = nil) {
        if centralManager.state == .poweredOn, centralManager.isScanning {
            centralManager.stopScan()
        }

        if let e = error {
            scanCompletionHandler(.failure(e))
        } else if isNewScanComing {
            scanCompletionHandler(.failure(.scanCancelByNewScanRequest))
        } else {
            let ar = Array(scanedPeripherals[0 ..< scanedPeripherals.count])
            scanCompletionHandler(.success(ar))
            scanedPeripherals = []
        }
        isSearching = false
        scanCompletionHandler = { _ in }
    }
}

// MARK: - Queued Request

extension BLEKit {
    func request(action: PeripheralAction) {
        requestActions.append(action)
        executeReadWriteAction()
    }

    func doneExecute() {
        if #available(iOS 11.0, *) {
            isReadyForReadWriteRequest = true
            executeReadWriteAction()
        } else {
            let delay: DispatchTimeInterval = .milliseconds(500)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.isReadyForReadWriteRequest = true
                self?.executeReadWriteAction()
            }
        }
    }

    static func dispatchError(_ event: Error) {
        shared.eventPipeline.call(.error(event))
    }

    private func executeReadWriteAction() {
        guard isReadyForReadWriteRequest == true,
            requestActions.isEmpty == false else { return }

        isReadyForReadWriteRequest = false
        requestActions.removeFirst().execute()
    }
}

// MARK: - CBCentralManager Stuff

extension BLEKit {
    /// 检测蓝牙是否可用
    ///
    /// - Parameter handler: 回调
    public func bleCanUse(completion handler: @escaping (Bool) -> Void) {
        if peripheralStubPolicy.isEnable {
            bleState = .poweredOn
            return handler(true)
        }

        if bleState == .unknown {
            doCheckBLEStateLater(handler: handler)
        } else {
            handler(bleState == .poweredOn)
        }
    }

    private func doCheckBLEStateLater(handler: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            handler(self?.bleState == .poweredOn)
        }
    }

    private func addEventMotinor() {
        centralManagerDelegator.eventPipeline.delegate(to: self) { monitor, event in
            DispatchQueue.main.async {
                switch event {
                case let .didUpdateState(central):
                    monitor.bleState = central.state
                    if monitor.isSearching {
                        monitor.scanDidComplete(isNewScanComing: false, error: BLEKit.Error.scanInterruptCauseBluetoothUnavailable)
                    }

                case let .didDiscover(result):
                    let peripheral = result.peripheral
                    func add() {
                        if monitor.scanedPeripherals.contains(where: { $0.peripheral.identifier == peripheral.identifier }) == false {
                            monitor.scanedPeripherals.append(result)
                            monitor.scanDidFindOneHandler(result)
                        }
                    }
                    if let filter = monitor.scanFilter { if filter(result) == true { add() } }
                    else { add() }

                case .didConnect: break

                case .didDisconnect: break

                case .didFailToConnect: break
                case .willRestoreState: break
                }
                NotificationCenter.default.post(name: .centralManagerDelegatorEvent, object: nil, userInfo: ["event": event])
                monitor.eventPipeline.call(.centralDelegator(event))
            }
        }
    }
}

// MARK: - type define

extension BLEKit {
    /// 蓝牙通讯超时策略
    ///
    /// - disable: 不启用
    /// - enable: 自定义超时时限
    public enum TimeoutPolicy {
        /// 不启用
        case disable
        /// 自定义超时时限
        case enable(DispatchTimeInterval)

        var timeout: DispatchTimeInterval? {
            if case let TimeoutPolicy.enable(value) = self { return value }
            return nil
        }
    }

    /// 事件输出流
    ///
    /// - centralDelegator: 中心设备事件
    /// - peripheralDelegator: 外围设备器事件
    /// - state: 状态变更事件
    public enum Event {
        /// 中心设备事件
        case centralDelegator(CentralManagerDelegator.Event)
        /// 外围设备器事件
        case peripheralDelegator(PeripheralDelegator.Event)
        /// 状态变更事件
        case state(CBManagerState)
        /// 错误事件
        case error(Error)
    }

    /// 错误类型
    ///
    /// - bluetoothNotAvailable: 当前蓝牙不可用
    /// - scanCancelByNewScanRequest: 当前扫描被新的扫描请求取消了
    /// - peripheralServiceNotFound: 外设服务没找到
    /// - peripheralCharacteristicNotFound: 外设特征值没找到
    /// - peripheralCharacteristicPropertiesIllegal: 外设特征值不合法
    /// - bleError: 系统蓝牙通信错误
    public enum Error: Swift.Error {
        /// 当前蓝牙不可用
        case bluetoothNotAvailable
        /// 当前连接被新的请求取消
        case connectCancelByNewRequest
        /// 连接超时错误
        case connectTimeout(TimeInterval)
        /// 当前扫描被新的扫描请求取消了
        case scanCancelByNewScanRequest
        /// 蓝牙中断，扫描失败
        case scanInterruptCauseBluetoothUnavailable
        /// 外设服务没找到
        case peripheralServiceNotFound(BLEKit.PeripheralAction.ServiceID)
        /// 外设特征值没找到
        case peripheralCharacteristicNotFound(BLEKit.PeripheralAction.CharacteristicID)
        /// 外设特征值不合法
        case peripheralCharacteristicPropertiesIllegal(CBCharacteristicProperties)
        /// 系统蓝牙通信错误
        case bleError(Swift.Error)
        /// 写操作的数据为空
        case writeDataIsEmpty
        /// 读超时错误
        case timeout(TimeoutPolicy, Request)
        /// Notify 设置超时错误
        case notifySetTimeout(TimeoutPolicy, Request)
        /// 发现服务超时错误
        case findServiceTimeout(TimeoutPolicy, Request)
        /// 发现特征值超时错误
        case findCharacteristicTimeout(TimeoutPolicy, Request)
        /// 外设还没连接
        case peripheralNotConnected(CBPeripheralState)
    }

    public enum CBCentralManagerScanOption: CaseIterable {
        case allowDuplicatesKey
        case solicitedServiceUUIDsKey

        public var rawValue: String {
            switch self {
            case .allowDuplicatesKey: return CBCentralManagerScanOptionAllowDuplicatesKey
            case .solicitedServiceUUIDsKey: return CBCentralManagerScanOptionSolicitedServiceUUIDsKey
            }
        }

        public static func from(_ value: String) -> CBCentralManagerScanOption? {
            return CBCentralManagerScanOption.allCases.filter { $0.rawValue == value }.first
        }
    }

    public enum PeripheralStubPolicy {
        case disable
        case enable([PeripheralCompatible])

        var isEnable: Bool {
            if case PeripheralStubPolicy.disable = self { return false }
            return true
        }

        var peripherals: [PeripheralCompatible]? {
            if case let PeripheralStubPolicy.enable(value) = self { return value }
            return nil
        }
    }

    struct Constants {
        public static let EquipmentRestoreIdentifier = "com.netease.flyblekit.restoreIdentifier"
        public static let BLEQueueName = "com.netease.flyblekit.blequeue"
        public static let PropertyQueue = "com.netease.flyblekit.propertyqueue"
    }
}

// MARK: - Typealias

extension BLEKit {
    public typealias ActionResult = PeripheralAction.ActionResult
    public typealias Request = PeripheralAction.Request
    public typealias ServiceID = PeripheralAction.ServiceID
    public typealias CharacteristicID = PeripheralAction.CharacteristicID
    public typealias Action = PeripheralAction.Action
    public typealias NotifyStatus = PeripheralAction.Action.NotifyStatus
    public typealias MockCharacteristic = PeripheralSimulator.MockCharacteristic
    public typealias MockService = PeripheralSimulator.MockService
}

extension PeripheralCompatible {
    var address: String {
        // <_TtCC9FlyBLEKit9FlyBLEKit19PeripheralSimulator: 0x7fc3abd25a40>
        return "\(ObjectIdentifier(self).hashValue)"
    }
}
