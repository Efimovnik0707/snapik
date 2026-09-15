// Port of tests 25-26 (`SingleInstanceActivation`'s exact-command check, `IsShowCommand`),
// adapted to the macOS `DistributedNotificationCenter` channel (SPEC §9.6, §8.2).
//
// The Windows tests assert byte-exact matching of a 5-byte `"SHOW\n"` wire command; the Mac port
// has no wire protocol (SPEC §9.6: "уведомления доставляются асинхронно и без подтверждения"), so
// this instead verifies the one thing that plays the same role — the observer only reacts to the
// exact notification name *and* the exact command payload, not anything else broadcast on
// `DistributedNotificationCenter`.
import Foundation
import XCTest
import SnapikCore

@testable import SnapikMac

final class SingleInstanceCoordinatorTests: XCTestCase {
    func test_observer_reacts_only_to_the_exact_activation_command() {
        let expectation = expectation(description: "activation handler called")
        expectation.expectedFulfillmentCount = 1
        expectation.assertForOverFulfill = true

        let token = SingleInstanceCoordinator.observeActivationRequests {
            expectation.fulfill()
        }
        defer { SingleInstanceCoordinator.stopObserving(token) }

        // Wrong object payload: must be ignored.
        DistributedNotificationCenter.default().postNotificationName(
            SingleInstanceCoordinator.activationNotificationName, object: "OPEN", userInfo: nil,
            deliverImmediately: true)
        // Wrong notification name: must be ignored.
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.snapik.activation.other"), object: SingleInstanceCoordinator.activationCommand,
            userInfo: nil, deliverImmediately: true)
        // Exact match: must fire exactly once.
        DistributedNotificationCenter.default().postNotificationName(
            SingleInstanceCoordinator.activationNotificationName, object: SingleInstanceCoordinator.activationCommand,
            userInfo: nil, deliverImmediately: true)

        wait(for: [expectation], timeout: 2)
    }
}
