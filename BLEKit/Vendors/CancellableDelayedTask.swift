import Foundation

public final class CancellableDelayedTask {
    /// init
    ///
    /// - Parameters:
    ///   - delay: milliseconds level
    ///   - task: your task
    public init(delay: Double, task: @escaping () -> Void) {
        let time = DispatchTime.now() + DispatchTimeInterval.milliseconds(Int(delay * 1000))
        DispatchQueue.main.asyncAfter(deadline: time) { [weak self] in
            guard self?._cancelled == false else { return }
            task()
        }
    }

    public init(delay: DispatchTimeInterval, task: @escaping () -> Void) {
        let time = DispatchTime.now() + delay
        DispatchQueue.main.asyncAfter(deadline: time) { [weak self] in
            guard self?._cancelled == false else { return }
            task()
        }
    }

    private lazy var _cancelled = false

    public func cancel() { _cancelled = true }
}
