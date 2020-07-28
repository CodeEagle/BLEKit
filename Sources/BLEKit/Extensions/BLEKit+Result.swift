import Foundation

extension Result {
    public struct Util {
        private let base: Result<Success, Failure>

        init(_ target: Result<Success, Failure>) {
            base = target
        }

        public var isSuccess: Bool {
            switch base {
            case .failure: return false
            case .success: return true
            }
        }

        public var value: Success? {
            switch base {
            case .failure: return nil
            case let .success(value): return value
            }
        }

        public var error: Failure? {
            switch base {
            case let .failure(value): return value
            case .success: return nil
            }
        }
    }

    public var util: Util { return Util(self) }
}
