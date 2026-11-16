import Foundation
import IOKit.pwr_mgt

/// Keeps the display awake for the duration of one action, the way the shipped
/// service does ("Keeping the display awake while UI automation handles a request").
final class DisplayAssertion {
    private var assertionID: IOPMAssertionID = 0

    init?() {
        let reason = "GhostMouse action in progress" as CFString
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        if status != kIOReturnSuccess {
            assertionID = 0
            return nil
        }
    }

    func release() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }

    deinit { release() }
}
