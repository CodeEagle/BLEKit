import CoreBluetooth

extension BLEKit {
    public final class PeripheralAction {
        public typealias ActionResult = (Result<Data?, BLEKit.Error>) -> Void
        public unowned let peripheral: PeripheralBox
        public let action: Action

        public init(peripheral: PeripheralBox, action: Action) {
            self.peripheral = peripheral
            self.action = action
        }

        public func execute() {
            peripheral.perform(action: action)
        }

        public enum Action {
            case read(Request, ActionResult)
            case write(Request, Data, CBCharacteristicWriteType, ActionResult?)
            case notify(Request, NotifyStatus)

            public var request: Request {
                switch self {
                case let .read(request, _): return request
                case let .write(request, _, _, _): return request
                case let .notify(request, _): return request
                }
            }

            public var property: CBCharacteristicProperties {
                switch self {
                case let .write(_, _, v, _):
                    switch v {
                    case .withResponse: return .write
                    case .withoutResponse: return .writeWithoutResponse
                    }
                case .read: return .read
                case .notify: return .notify
                }
            }

            public var handler: ActionResult? {
                switch self {
                case let .notify(_, v): return v.handler
                case let .read(_, h): return h
                case let .write(_, _, _, h): return h
                }
            }

            public enum Write {
                case noResponse
                case withResponse(ActionResult)

                public var isWithResponse: Bool {
                    if case Write.withResponse = self { return true }
                    return false
                }

                public var handler: ActionResult? {
                    switch self {
                    case let .withResponse(v): return v
                    case .noResponse: return nil
                    }
                }
            }
            
            public enum NotifyStatus {
                case enable(ActionResult)
                case disable

                public var value: Bool {
                    if case NotifyStatus.disable = self { return false }
                    return true
                }

                public var handler: ActionResult? {
                    switch self {
                    case let .enable(v): return v
                    case .disable: return nil
                    }
                }
            }
        }

        public struct Request: Hashable, CustomStringConvertible {
            public let characteristicID: CharacteristicID
            public let serviceID: ServiceID

            public init(characteristicID: CharacteristicID, serviceID: ServiceID) {
                self.characteristicID = characteristicID
                self.serviceID = serviceID
            }

            public init(characteristic: CBCharacteristic, service: CBService) {
                self.init(characteristicID: .init(characteristic.uuid.uuidString), serviceID: .init(service.uuid.uuidString))
            }

            public init(characteristic: CharacteristicCompatible, service: ServiceCompatible) {
                self.init(characteristicID: .init(characteristic.uuid.uuidString), serviceID: .init(service.uuid.uuidString))
            }

            public static let none = Request(characteristicID: "", serviceID: "")

            public var description: String { return "service: 0x\(serviceID.id), characteristic: 0x\(characteristicID.id) " }
        }

        public struct CharacteristicID: ExpressibleByStringLiteral, Hashable {
            public typealias StringLiteralType = String
            public let id: StringLiteralType

            public init(stringLiteral value: StringLiteralType) { id = value }
            public init(_ value: StringLiteralType) { id = value }

            public static let none = CharacteristicID(stringLiteral: "")
        }

        public struct ServiceID: ExpressibleByStringLiteral, Hashable {
            public typealias StringLiteralType = String
            public let id: StringLiteralType

            public init(stringLiteral value: StringLiteralType) { id = value }
            public init(_ value: StringLiteralType) { id = value }

            public static let none = ServiceID(stringLiteral: "")
        }
    }
}
