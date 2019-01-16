import CoreBluetooth

extension BLEKit.PeripheralSimulator {
    public final class MockService: NSObject, ServiceCompatible {
        public private(set) var mockCharacteristics: [CharacteristicCompatible] = []

        public private(set) unowned var mockPeripheral: PeripheralCompatible

        public private(set) var uuid: CBUUID = CBUUID(nsuuid: UUID())

        public unowned var peripheral: CBPeripheral { fatalError(BLEKit.forbidden) }

        public private(set) var isPrimary: Bool = false

        public var includedServices: [CBService]? { return nil }

        public var characteristics: [CBCharacteristic]? { return nil }

        public init(id: String, peripheral value: PeripheralCompatible) {
            mockPeripheral = value
            uuid = CBUUID(string: id)
            super.init()
        }

        public func addMockCharacteristic(_ value: CharacteristicCompatible) {
            mockCharacteristics.append(value)
        }
    }
}
