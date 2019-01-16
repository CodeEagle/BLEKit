import CoreBluetooth

public protocol ServiceCompatible: NSObjectProtocol {
    var mockCharacteristics: [CharacteristicCompatible] { get }
    var mockPeripheral: PeripheralCompatible { get }

    func addMockCharacteristic(_ value: CharacteristicCompatible)

    var uuid: CBUUID { get }
    var peripheral: CBPeripheral { get }
    var isPrimary: Bool { get }
    var includedServices: [CBService]? { get }
    var characteristics: [CBCharacteristic]? { get }
}

extension CBService: ServiceCompatible {
    public func addMockCharacteristic(_ value: CharacteristicCompatible) { }
    public var mockPeripheral: PeripheralCompatible { fatalError(BLEKit.forbidden) }
    public var mockCharacteristics: [CharacteristicCompatible] { return [] }
}
