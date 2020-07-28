import CoreBluetooth

public protocol PeripheralCompatible: NSObjectProtocol {
    var isSimulator: Bool { get }

    var mockDelegate: BLEKit.PeripheralDelegator? { get set }

    var mockAdvertisementData: [String: Any] { get }

    var mockRSSI: NSNumber { get }

    var mockState: CBPeripheralState { get set }

    var mockServices: [ServiceCompatible] { get }

    func mockReadValue(for action: BLEKit.PeripheralAction.Action)

    func mockWriteValue(_ data: Data, for action: BLEKit.PeripheralAction.Action, type: CBCharacteristicWriteType)

    func mockSetNotifyValue(_ enabled: Bool, for action: BLEKit.PeripheralAction.Action)

    func addMockServices(_ services: [ServiceCompatible])

    @available(iOS 7.0, *)
    var identifier: UUID { get }

    var delegate: CBPeripheralDelegate? { get set }

    var name: String? { get }

    @available(iOS, introduced: 5.0, deprecated: 8.0)
    var rssi: NSNumber? { get }

    var state: CBPeripheralState { get }

    var services: [CBService]? { get }

    @available(iOS 11.0, *)
    var canSendWriteWithoutResponse: Bool { get }

    func readRSSI()

    func discoverServices(_ serviceUUIDs: [CBUUID]?)

    func discoverIncludedServices(_ includedServiceUUIDs: [CBUUID]?, for service: CBService)

    func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService)

    func readValue(for characteristic: CBCharacteristic)

    @available(iOS 9.0, *)
    func maximumWriteValueLength(for type: CBCharacteristicWriteType) -> Int

    func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType)

    func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic)

    func discoverDescriptors(for characteristic: CBCharacteristic)

    func readValue(for descriptor: CBDescriptor)

    func writeValue(_ data: Data, for descriptor: CBDescriptor)

    @available(iOS 11.0, OSX 10.14, *)
    func openL2CAPChannel(_ PSM: CBL2CAPPSM)
}

// MARK: - CBPeripheral @ PeripheralCompatible

extension CBPeripheral: PeripheralCompatible {
    public var mockServices: [ServiceCompatible] { return [] }
    public var isSimulator: Bool { return false }
    public var mockAdvertisementData: [String: Any] { return [:] }
    public var mockRSSI: NSNumber { return -82 }
    public var mockDelegate: BLEKit.PeripheralDelegator? {
        get { return nil }
        set {}
    }

    public var mockState: CBPeripheralState {
        get { return state }
        set {}
    }

    public func mockReadValue(for _: BLEKit.PeripheralAction.Action) {}

    public func mockWriteValue(_: Data, for _: BLEKit.PeripheralAction.Action, type _: CBCharacteristicWriteType) {}

    public func mockSetNotifyValue(_: Bool, for _: BLEKit.PeripheralAction.Action) {}

    public func addMockServices(_: [ServiceCompatible]) {}
}
