import AppKit

/// Polls the system cursor at a fixed rate on the main thread.
///
/// ponytail: DispatchSourceTimer rather than Timer, because a Timer subclass
/// cannot take a closure init and the block-based Timer API wants @Sendable
/// under Swift 6 strict concurrency. The .main queue runs on the main thread,
/// so the callback is main-actor work.
@MainActor
final class CursorPoller {
    private var timer: DispatchSourceTimer?
    private(set) var tickCount = 0
    private let onMove: (NSPoint) -> Void

    init(hz: Int, onMove: @escaping (NSPoint) -> Void) {
        self.onMove = onMove
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: 1.0 / Double(hz))
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.tickCount += 1
                self?.onMove(NSEvent.mouseLocation)
            }
        }
        source.resume()
        timer = source
    }
}
