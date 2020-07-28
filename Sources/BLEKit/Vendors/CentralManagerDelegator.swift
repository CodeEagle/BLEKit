import CoreBluetooth

// MARK: - CentralManagerDelegater

extension BLEKit {
    public final class CentralManagerDelegator: NSObject {
        // MARK: - properties

        public private(set) lazy var eventPipeline = Delegated<Event, Void>()

        // MARK: - life cycle methods

        public override init() { super.init() }
    }
}

// MARK: - extension

// MARK: - type define

extension BLEKit.CentralManagerDelegator {
    public typealias WillRestoreBox = (central: CBCentralManager, dict: [String: Any])
    public typealias DidConnectBox = (central: CBCentralManager, peripheral: PeripheralCompatible)
    public typealias FailToConnectBox = (central: CBCentralManager, peripheral: PeripheralCompatible, error: Error?)
    public typealias DisconnectBox = FailToConnectBox

    public enum Event {
        case didUpdateState(CBCentralManager)
        case willRestoreState(WillRestoreBox)
        case didDiscover(BLEKit.PeripheralBox)
        case didConnect(DidConnectBox)
        case didFailToConnect(FailToConnectBox)
        case didDisconnect(DisconnectBox)
    }
}

// MARK: - methods

// MARK: - CBCentralManagerDelegate

extension BLEKit.CentralManagerDelegator: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) { eventPipeline.call(.didUpdateState(central)) }

    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) { eventPipeline.call(.willRestoreState((central, dict))) }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) { eventPipeline.call(.didDiscover(.init(central, peripheral, advertisementData, RSSI))) }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) { eventPipeline.call(.didConnect((central, peripheral))) }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) { eventPipeline.call(.didFailToConnect((central, peripheral, error))) }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) { eventPipeline.call(.didDisconnect((central, peripheral, error))) }
}
