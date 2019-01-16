import CoreBluetooth

public final class BLEKit {
    public static let shared = BLEKit()

    public lazy var peripheralStubPolicy: PeripheralStubPolicy = .disable
    /// 超时策略
    public lazy var timeoutPolicy: TimeoutPolicy = .disable

    // MARK: 中心控制器和设备控制器

    public private(set) lazy var centralManager = CBCentralManager(delegate: nil, queue: nil)

    /// 蓝牙状态
    ///
    /// 变更会发送通知 Notification.Name.BluetoothStateChanged
    ///
    /// userInfo 结构为 ["state" : bleState]
    public private(set) var bleState: CBCentralManagerState = .unknown {
        didSet {
            let info: [AnyHashable : Any] = ["state" : bleState]
            NotificationCenter.default.post(name: .BluetoothStateChanged, object: nil, userInfo: info)
            eventPipeline.call(.state(bleState))
        }
    }

    public private(set) lazy var eventPipeline = Delegated<Event, Void>()

    private(set) lazy var centralManagerDelegator = CentralManagerDelegator()

    private let bleQueue: DispatchQueue = DispatchQueue(label: BLEKit.Constants.QueueName, qos: .userInitiated, attributes: .concurrent)

    // MARK: CentralManager Scan

    private var scanCompletionHandler: ([PeripheralBox], BLEKit.Error?) -> Void = { _, _ in }
    private var scanDidFindOneHandler: (PeripheralBox) -> Void = { _ in }
    private var scanNameFilter: ((String?) -> Bool)?
    private lazy var scanedPeripherals: [PeripheralBox] = []
    private var scanTask: CancellableDelayedTask?

    private let queue: DispatchQueue = DispatchQueue(label: "property", qos: .utility, attributes: .concurrent)

    private var _centralEventMonitors: [UUID: (CentralManagerDelegator.Event) -> Void] = [:]
    private var centralEventMonitors: [UUID: (CentralManagerDelegator.Event) -> Void] {
        get { return queue.sync { _centralEventMonitors } }
        set { queue.async(flags: .barrier) { self._centralEventMonitors = newValue } }
    }

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

    private init() { initCentralManager() }
}

// MARK: - Public API

extension BLEKit {
    /// 扫描蓝牙外设
    ///
    /// - Returns:
    public func scan(timeout: TimeInterval = 5,
                     nameFilter: ((String?) -> Bool)? = nil,
                     serviceUUID: [String]? = nil,
                     options: [CBCentralManagerScanOption: Any]? = nil,
                     didFindOne: @escaping (PeripheralBox) -> Void = { _ in },
                     completion handler: @escaping ([PeripheralBox], BLEKit.Error?) -> Void) {
        stopScan(isNewScanComing: true)
        scanCompletionHandler = handler
        scanDidFindOneHandler = didFindOne
        scanNameFilter = nameFilter
        bleCanUse { [weak self] canUse in
            guard let sself = self else { return }

            guard canUse else {
                handler([], BLEKit.Error.bluetoothNotAvailable)
                return
            }

            if let mockPeripherals = sself.peripheralStubPolicy.peripherals {
                let boxs = mockPeripherals.compactMap { item -> PeripheralBox? in
                    let box = PeripheralBox(sself.centralManager, item, item.mockAdvertisementData, item.mockRSSI)
                    if let filter = sself.scanNameFilter {
                        if filter(item.name) == true {
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
        guard centralManager.state == .poweredOn else { return }
        centralManager.stopScan()
    }

    private func scanDidComplete(isNewScanComing: Bool) {
        scanCompletionHandler(scanedPeripherals, isNewScanComing ? .scanCancelByNewScanRequest : nil)
    }
}

// MARK: Add or Remove CentralEventMonitor

extension BLEKit {
    func addCentralEventMonitor(for p: PeripheralCompatible, handler: @escaping (CentralManagerDelegator.Event) -> Void) {
        centralEventMonitors[p.identifier] = handler
    }

    func removeCentralEventMonitor(for p: PeripheralCompatible) {
        centralEventMonitors[p.identifier] = nil
    }
}

// MARK: - Queued Request

extension BLEKit {
    func request(action: PeripheralAction) {
        requestActions.append(action)
        executeReadWriteAction()
    }

    func doneExecute() {
        isReadyForReadWriteRequest = true
        executeReadWriteAction()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
            handler(self?.bleState == .poweredOn)
        }
    }

    private func initCentralManager() {
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
        centralManager = CBCentralManager(delegate: centralManagerDelegator, queue: bleQueue, options: option)
    }

    private func addEventMotinor() {
        centralManagerDelegator.eventPipeline.delegate(to: self) { monitor, event in
            DispatchQueue.main.async {
                switch event {
                case let .didUpdateState(central):
                    monitor.bleState = central.centralManagerState

                case let .didDiscover(result):
                    let central = result.central
                    let peripheral = result.peripheral
                    let advertisementData = result.advertisementData
                    let rssi = result.rssi
                    func add() {
                        if monitor.scanedPeripherals.contains(where: { $0.peripheral.identifier == peripheral.identifier }) == false {
                            monitor.scanedPeripherals.append(result)
                            monitor.scanDidFindOneHandler(result)
                        }
                    }
                    if let filter = monitor.scanNameFilter { if filter(peripheral.name) == true { add() } }
                    else { add() }

                    let registerMonitor = monitor.centralEventMonitors[peripheral.identifier]
                    registerMonitor?(event)

                case let .didConnect(_, peripheral):
                    let registerMonitor = monitor.centralEventMonitors[peripheral.identifier]
                    registerMonitor?(event)

                case let .didDisconnect(_, peripheral, _):
                    let registerMonitor = monitor.centralEventMonitors[peripheral.identifier]
                    registerMonitor?(event)

                case .didFailToConnect: break
                case .willRestoreState: break
                }
                monitor.eventPipeline.call(.centralDelegator(event))
            }
        }
    }
}

// MARK: - model

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
        case state(CBCentralManagerState)
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
        /// 超时错误
        case timeout(TimeoutPolicy)
        /// 外设还没连接
        case peripheralNotConnected(CBPeripheralState)
    }

    public enum CBCentralManagerScanOption: String {
        case allowDuplicatesKey
        case solicitedServiceUUIDsKey
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
        public static let EquipmentRestoreIdentifier = "app.selfstudio.restoreIdentifier"
        public static let QueueName = "app.selfstudio.BLEKitQueue"
    }
}
