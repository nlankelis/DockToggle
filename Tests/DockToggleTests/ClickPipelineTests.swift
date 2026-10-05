import Foundation
import Dispatch
import DockToggleCore

struct ClickPipelineTests {
    private let point = Point(x: 40, y: 60)
    private func click(_ sequence: UInt64 = 1, epoch: UInt64 = 0) -> Click {
        Click(sequence: sequence, epoch: epoch, point: point, activeApp: nil, startedAt: 10)
    }
    func testOnlyCompletedPlainShortClickIsAccepted() {
        var recognizer = ClickRecognizer()
        expect(recognizer.begin(click(), modified: false) != nil)
        expect(recognizer.finish(at: point, time: 10.1, modified: false) != nil)
        expect(recognizer.finish(at: point, time: 10.2, modified: false) == nil)
        expect(recognizer.begin(click(), modified: true) == nil)
        expect(recognizer.finish(at: point, time: 10.1, modified: false) == nil)
        _ = recognizer.begin(click(), modified: false)
        expect(recognizer.finish(at: point, time: 10.1, modified: true) == nil)
        _ = recognizer.begin(click(), modified: false)
        expect(recognizer.finish(at: point, time: 10.6, modified: false) == nil)
    }
    func testDragRemainsCancelledAfterReturningToOrigin() {
        var recognizer = ClickRecognizer()
        _ = recognizer.begin(click(), modified: false)
        recognizer.cancel() // Any leftMouseDragged event, even below movement threshold.
        expect(recognizer.finish(at: point, time: 10.1, modified: false) == nil)
        _ = recognizer.begin(click(), modified: false)
        expect(recognizer.finish(at: Point(x: 45, y: 60), time: 10.1, modified: false) == nil)
    }
    func testTenThousandRapidClicksHaveOnePendingSlotAndOneDrain() {
        let mailbox = ClickMailbox()
        var drainStarts = 0
        var last: Click!
        for _ in 0..<10_000 {
            last = click(mailbox.nextSequence())
            if mailbox.offer(last) { drainStarts += 1 }
            last.releasedAt = 10.1
            if mailbox.offer(last) { drainStarts += 1 }
        }
        expect(drainStarts == 1)
        expect(mailbox.take() == last)
        expect(mailbox.take() == nil)
        let next = click(mailbox.nextSequence())
        expect(mailbox.offer(next)) // The worker can restart after going idle.
    }
    func testNewClickInvalidatesInFlightActionAndDeadlineDropsLateWork() {
        let mailbox = ClickMailbox()
        var first = click(mailbox.nextSequence())
        first.releasedAt = 10.1
        expect(mailbox.offer(first))
        expect(mailbox.take() == first)
        expect(mailbox.isCurrent(first, now: 10.2))
        expect(!(mailbox.isCurrent(first, now: 10.351)))
        let second = click(mailbox.nextSequence())
        expect(!(mailbox.isCurrent(first, now: 10.2)))
        expect(!(mailbox.offer(first)))
        expect(!(mailbox.offer(second))) // Existing drain is still running.
        expect(mailbox.take() == second)
    }
    func testPermissionOrSleepEpochRejectsOldGesture() {
        let mailbox = ClickMailbox()
        let old = click(mailbox.nextSequence())
        expect(mailbox.offer(old))
        mailbox.invalidate(epoch: 1)
        expect(mailbox.take() == nil)
        expect(!(mailbox.offer(old)))
        expect(!(mailbox.isCurrent(old, now: 10.1)))
        let fresh = click(mailbox.nextSequence(), epoch: 1)
        expect(mailbox.offer(fresh))
    }
    func testReleaseInvalidatesUnfinishedPreflightButAllowsPreparedAction() {
        let mailbox = ClickMailbox()
        let down = click(mailbox.nextSequence())
        expect(mailbox.offer(down))
        expect(mailbox.take() == down)
        expect(mailbox.isCurrent(down, now: 10.05))
        var up = down
        up.releasedAt = 10.1
        _ = mailbox.offer(up)
        expect(!mailbox.isCurrent(down, now: 10.11))
        expect(mailbox.isCurrent(up, now: 10.11))
    }
    func testMailboxConcurrentProducerAndConsumerPreserveNewestSequence() {
        let mailbox = ClickMailbox()
        let group = DispatchGroup()
        let consumer = DispatchQueue(label: "test.consumer")
        group.enter()
        consumer.async {
            for _ in 0..<10_000 { _ = mailbox.take() }
            group.leave()
        }
        for _ in 0..<10_000 {
            let next = click(mailbox.nextSequence())
            _ = mailbox.offer(next)
        }
        expect(group.wait(timeout: .now() + 5) == .success)
        mailbox.invalidate()
        let final = click(mailbox.nextSequence())
        _ = mailbox.offer(final)
        expect(mailbox.take() == final)
        expect(mailbox.take() == nil)
    }
}
