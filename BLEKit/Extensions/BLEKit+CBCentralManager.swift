import CoreBluetooth

extension CBCentralManager {
    public var centralManagerState: CBCentralManagerState {
        return CBCentralManagerState(rawValue: state.rawValue) ?? .unknown
    }
}
