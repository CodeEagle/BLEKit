import Foundation
extension BLEKit {
    public enum Result<Value, E: Swift.Error> {
        case success(Value)
        case failure(E)

        public var value: Value? {
            switch self {
            case let .success(v): return v
            case .failure: return nil
            }
        }

        public var error: E? {
            switch self {
            case let .failure(v): return v
            case .success: return nil
            }
        }
    }
}
