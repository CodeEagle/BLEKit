import CoreBluetooth

extension BLEKit {
    public final class PeripheralAction {
        public typealias ActionResult = (Result<Data?, BLEKit.Error>) -> Void

        // MARK: - properties

        public weak var peripheral: PeripheralBox?
        public let action: Action

        // MARK: - life cycle methods

        public init(peripheral: PeripheralBox, action: Action) {
            self.peripheral = peripheral
            self.action = action
        }

        // MARK: - methods

        public func execute() {
            peripheral?.perform(action: action)
        }

        // MARK: - type define

        /// 动作
        public enum Action {
            /// 写操作的参数
            public struct WriteParam {
                public let data: Data
                public let type: CBCharacteristicWriteType
                public let action: ActionResult?
                public let responseRequest: Request
            }

            /// 读取
            case read(Request, ActionResult)
            /// 写入
            case write(Request, WriteParam)
            /// 通知
            case notify(Request, NotifyStatus)

            public var request: Request {
                switch self {
                case let .read(request, _): return request
                case let .write(request, _): return request
                case let .notify(request, _): return request
                }
            }

            public var property: CBCharacteristicProperties {
                switch self {
                case let .write(_, param):
                    switch param.type {
                    case .withResponse: return .write
                    case .withoutResponse: return .writeWithoutResponse
                    @unknown default: fatalError()
                    }
                case .read: return .read
                case .notify: return .notify
                }
            }

            public var handler: ActionResult? {
                switch self {
                case let .notify(_, v): return v.handler
                case let .read(_, h): return h
                case let .write(_, param): return param.action
                }
            }

            public enum Write {
                case noResponse(ActionResult?)
                case withResponse(ActionResult)

                public var isWithResponse: Bool {
                    if case Write.withResponse = self { return true }
                    return false
                }

                public var handler: ActionResult? {
                    switch self {
                    case let .withResponse(v): return v
                    case let .noResponse(v): return v
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

            /// 初始化
            ///
            /// - Parameters:
            ///   - characteristicString: 特征值字符串
            ///   - serviceString: 服务字符串
            public init(_ characteristicString: String, _ serviceString: String) {
                self.init(characteristicID: .init(characteristicString), serviceID: .init(serviceString))
            }

            /// 初始化
            ///
            /// - Parameters:
            ///   - characteristicID: 特征值ID
            ///   - serviceID: 服务ID
            public init(characteristicID: CharacteristicID, serviceID: ServiceID) {
                self.characteristicID = characteristicID
                self.serviceID = serviceID
            }

            /// 初始化
            ///
            /// - Parameters:
            ///   - characteristic: 蓝牙特征值
            ///   - service: 蓝牙服务
            public init(characteristic: CBCharacteristic, service: CBService) {
                self.init(characteristic.uuid.uuidString, service.uuid.uuidString)
            }

            /// 初始化
            ///
            /// - Parameters:
            ///   - characteristic: 蓝牙特征值
            ///   - service: 蓝牙服务
            public init(characteristic: CharacteristicCompatible, service: ServiceCompatible) {
                self.init(characteristicID: .init(characteristic.uuid.uuidString), serviceID: .init(service.uuid.uuidString))
            }

            public static let none = Request("", "")

            public var description: String { return "service: 0x\(serviceID.id), characteristic: 0x\(characteristicID.id) " }
        }

        public struct CharacteristicID: ExpressibleByStringLiteral, Hashable {
            public typealias StringLiteralType = String
            public let id: StringLiteralType

            public init(stringLiteral value: StringLiteralType) { id = value.uppercased() }
            public init(_ value: StringLiteralType) { id = value.uppercased() }

            public static let none = CharacteristicID("")
        }

        public struct ServiceID: ExpressibleByStringLiteral, Hashable {
            public typealias StringLiteralType = String
            public let id: StringLiteralType

            public init(stringLiteral value: StringLiteralType) { id = value.uppercased() }
            public init(_ value: StringLiteralType) { id = value.uppercased() }

            public static let none = ServiceID("")
        }
    }
}
