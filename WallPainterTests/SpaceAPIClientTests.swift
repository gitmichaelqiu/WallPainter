import Foundation
import XCTest

@testable import WallPainter

final class SpaceAPIClientTests: XCTestCase {
    func testRequestPayloadUsesStructuredJSONRPCEnvelope() throws {
        let payload = try SpaceAPICodec.requestPayload(
            id: "request-1",
            method: "getSpaceSnapshot"
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(payload.utf8)
        ) as? [String: Any])

        XCTAssertEqual(object["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(object["id"] as? String, "request-1")
        XCTAssertEqual(object["method"] as? String, "getSpaceSnapshot")
        XCTAssertNil(object["params"])
    }

    func testResponseCorrelationAndAPIErrorDecoding() throws {
        let errorPayload = """
        {"jsonrpc":"2.0","id":"request-1","error":{"code":-32001,"message":"SpaceAPI is disabled."}}
        """

        XCTAssertEqual(try SpaceAPICodec.responseID(from: errorPayload), "request-1")
        XCTAssertEqual(
            try SpaceAPICodec.responseError(from: errorPayload),
            SpaceAPIError(code: -32001, message: "SpaceAPI is disabled.")
        )
    }

    func testSnapshotAndStateChangedEventDecodeFromPayload() throws {
        let snapshotPayload = snapshotResponse(revision: 7)
        let eventPayload = """
        {"jsonrpc":"2.0","method":"stateChanged","params":{"reason":"activeSpaceChanged","snapshot":\(snapshotJSON(revision: 8))}}
        """

        let snapshot = try SpaceAPICodec.decodeSnapshot(from: snapshotPayload)
        XCTAssertEqual(snapshot.revision, 7)
        XCTAssertEqual(snapshot.currentSpaceIDs, ["space-1", "space-2"])
        XCTAssertEqual(snapshot.spaces.count, 3)
        XCTAssertTrue(snapshot.spaces.contains { $0.isFullscreen })

        let eventSnapshot = try XCTUnwrap(
            SpaceAPICodec.decodeStateChangedEvent(from: eventPayload)
        )
        XCTAssertEqual(eventSnapshot.revision, 8)
        XCTAssertEqual(eventSnapshot.currentSpaceIDs, ["space-2"])
    }

    func testFocusedRegularSpaceTargetPrefersSpaceAPIFocusedSpace() {
        let snapshot = SpaceSnapshot(
            revision: 1,
            currentSpaceIDs: ["space-a", "space-b"],
            currentSpaceID: "space-b",
            currentDisplayID: "display-a",
            spaces: [
                makeSpace(id: "space-a", displayID: "display-a"),
                makeSpace(id: "space-b", displayID: "display-b")
            ]
        )

        XCTAssertEqual(
            snapshot.focusedRegularSpaceTarget,
            WallpaperSpaceTarget(
                spaceID: "space-b",
                displayID: "display-b",
                managedSpaceID: "managed-space-b"
            )
        )
    }

    func testFocusedRegularSpaceTargetFallsBackToCurrentDisplay() {
        let snapshot = SpaceSnapshot(
            revision: 1,
            currentSpaceIDs: ["space-a", "space-b"],
            currentDisplayID: "display-b",
            spaces: [
                makeSpace(id: "space-a", displayID: "display-a"),
                makeSpace(id: "space-b", displayID: "display-b")
            ]
        )

        XCTAssertEqual(
            snapshot.focusedRegularSpaceTarget?.spaceID,
            "space-b"
        )
    }

    func testFocusedRegularSpaceTargetDoesNotGuessWhenFocusIsAmbiguous() {
        let snapshot = SpaceSnapshot(
            revision: 1,
            currentSpaceIDs: ["space-a", "space-b"],
            spaces: [
                makeSpace(id: "space-a", displayID: "display-a"),
                makeSpace(id: "space-b", displayID: "display-b")
            ]
        )

        XCTAssertNil(snapshot.focusedRegularSpaceTarget)
    }

    func testLegacyManagedSpaceIDsAttachOnlyWhenCompleteLayoutsMatch() {
        let structuredSnapshot = SpaceSnapshot(
            revision: 7,
            currentSpaceIDs: ["space-a"],
            spaces: [
                makeSpace(id: "space-a", displayID: "display-a"),
                makeSpace(id: "space-b", displayID: "display-a")
            ]
        )
        let legacySpaces = [
            makeLegacySpace(id: "managed-a", displayID: "display-a", number: 1, name: "space-a"),
            makeLegacySpace(id: "managed-b", displayID: "display-a", number: 1, name: "space-b")
        ]

        let mapped = structuredSnapshot.attachingManagedSpaceIDs(from: legacySpaces)

        XCTAssertEqual(mapped?.spaces.map(\.managedSpaceID), ["managed-a", "managed-b"])
    }

    func testLegacyManagedSpaceIDsRejectPartialOrAmbiguousMatches() {
        let structuredSnapshot = SpaceSnapshot(
            revision: 7,
            currentSpaceIDs: ["space-a", "space-b"],
            spaces: [
                makeSpace(id: "space-a", displayID: "display-a"),
                makeSpace(id: "space-b", displayID: "display-b")
            ]
        )
        let incompleteLegacySnapshot = [
            makeLegacySpace(id: "managed-a", displayID: "display-a", number: 1, name: "space-a")
        ]
        let ambiguousLegacySnapshot = [
            makeLegacySpace(id: "managed-a", displayID: "display-a", number: 1, name: "space-a"),
            makeLegacySpace(id: "managed-b", displayID: "display-a", number: 1, name: "space-a")
        ]
        let ambiguousStructuredSnapshot = SpaceSnapshot(
            revision: 7,
            currentSpaceIDs: ["space-a", "space-b"],
            spaces: [
                makeSpace(id: "space-a", displayID: "display-a"),
                SpaceDescriptor(
                    id: "space-b",
                    name: "space-a",
                    displayID: "display-a",
                    displayName: "display-a",
                    number: 1,
                    isFullscreen: false
                )
            ]
        )

        XCTAssertNil(structuredSnapshot.attachingManagedSpaceIDs(from: incompleteLegacySnapshot))
        XCTAssertNil(structuredSnapshot.attachingManagedSpaceIDs(from: ambiguousLegacySnapshot))
        XCTAssertNil(ambiguousStructuredSnapshot.attachingManagedSpaceIDs(from: ambiguousLegacySnapshot))
    }

    func testRevisionTrackerRejectsStaleEventsAndRequestsResynchronizationAfterGap() {
        var tracker = SpaceAPIRevisionTracker()

        XCTAssertTrue(tracker.acceptSnapshot(revision: 10))
        XCTAssertEqual(tracker.evaluateEvent(revision: 9), .stale)
        XCTAssertEqual(tracker.evaluateEvent(revision: 12), .gap)
        XCTAssertEqual(tracker.evaluateEvent(revision: 11), .apply)
        XCTAssertEqual(tracker.revision, 11)
    }

    func testRevisionTrackerAcceptsNewSequenceAfterResynchronization() {
        var tracker = SpaceAPIRevisionTracker()

        XCTAssertTrue(tracker.acceptSnapshot(revision: 42))
        tracker.reset()

        XCTAssertTrue(tracker.acceptSnapshot(revision: 1))
        XCTAssertEqual(tracker.revision, 1)
    }

    func testRevisionTrackerAcceptsSameRevisionForSnapshotVerification() {
        var tracker = SpaceAPIRevisionTracker()

        XCTAssertTrue(tracker.acceptSnapshot(revision: 10))
        XCTAssertTrue(tracker.acceptVerifiedSnapshot(revision: 10))
        XCTAssertFalse(tracker.acceptVerifiedSnapshot(revision: 9))
        XCTAssertEqual(tracker.revision, 10)
    }

    private func snapshotResponse(revision: UInt64) -> String {
        """
        {"jsonrpc":"2.0","id":"snapshot-1","result":\(snapshotJSON(revision: revision))}
        """
    }

    private func snapshotJSON(revision: UInt64) -> String {
        let currentSpaceIDs = revision == 8
            ? "[\"space-2\"]"
            : "[\"space-1\",\"space-2\"]"
        return """
        {"apiVersion":"1.0.0","revision":\(revision),"timestamp":"2026-08-31T07:00:00Z","currentSpaceIDs":\(currentSpaceIDs),"currentSpaceName":"Writing","spaces":[{"id":"space-1","name":"Writing","displayID":"display-1","displayName":"Built-in Display","number":1,"isFullscreen":false},{"id":"space-2","name":"Research","displayID":"display-2","displayName":"External Display","number":2,"isFullscreen":false},{"id":"full-screen","name":"Video","displayID":"display-1","displayName":"Built-in Display","number":0,"isFullscreen":true,"appName":"Video"}]}
        """
    }

    private func makeSpace(
        id: String,
        displayID: String,
        isFullscreen: Bool = false
    ) -> SpaceDescriptor {
        SpaceDescriptor(
            id: id,
            name: id,
            displayID: displayID,
            displayName: displayID,
            number: 1,
            isFullscreen: isFullscreen,
            managedSpaceID: "managed-\(id)"
        )
    }

    private func makeLegacySpace(
        id: String,
        displayID: String,
        number: Int,
        name: String
    ) -> SpaceDescriptor {
        SpaceDescriptor(
            id: id,
            name: name,
            displayID: displayID,
            displayName: displayID,
            number: number,
            isFullscreen: false,
            managedSpaceID: id
        )
    }
}
