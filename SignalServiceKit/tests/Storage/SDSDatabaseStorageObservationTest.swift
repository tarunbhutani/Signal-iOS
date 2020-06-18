//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
@testable import SignalServiceKit

class MockObserver {
    var updateCount: UInt = 0
    var externalUpdateCount: UInt = 0
    var resetCount: UInt = 0
    var lastChange: SDSDatabaseStorageChange?

    private var expectation: XCTestExpectation?

    init() {
        AssertIsOnMainThread()

        SDSDatabaseStorage.shared.appendUIDatabaseSnapshotDelegate(self)
    }

    func set(expectation: XCTestExpectation) {
        AssertIsOnMainThread()

        self.expectation = expectation
    }

    func clear() {
        updateCount = 0
        externalUpdateCount = 0
        resetCount = 0
        lastChange = nil
    }
}

// MARK: -

extension MockObserver: UIDatabaseSnapshotDelegate {

    func uiDatabaseSnapshotWillUpdate() {
        AssertIsOnMainThread()
    }

    func uiDatabaseSnapshotDidUpdate(databaseChanges: UIDatabaseChanges) {
        AssertIsOnMainThread()

        updateCount += 1
        lastChange = change

        expectation?.fulfill()
        expectation = nil
    }

    func uiDatabaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()

        Logger.verbose("")

        externalUpdateCount += 1

        expectation?.fulfill()
        expectation = nil
    }

    func uiDatabaseSnapshotDidReset() {
        AssertIsOnMainThread()

        Logger.verbose("")

        resetCount += 1

        expectation?.fulfill()
        expectation = nil
    }
}

// MARK: -

class SDSDatabaseStorageObservationTest: SSKBaseTestSwift {

    // MARK: - Dependencies

    var storageCoordinator: StorageCoordinator {
        return SSKEnvironment.shared.storageCoordinator
    }

    // MARK: - GRDB

    func testGRDBSyncWrite() {

        try! databaseStorage.grdbStorage.setupUIDatabase()

        // Make sure there's already at least one thread.
        var someThread: TSThread?
        self.write { transaction in
            let recipient = SignalServiceAddress(phoneNumber: "+1222333444")
            someThread = TSContactThread.getOrCreateThread(withContactAddress: recipient, transaction: transaction)
        }

        // First flush any pending notifications in SDSDatabaseStorageObservation
        // from setup.
        let flushExpectation = self.expectation(description: "Database Storage Observer")
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                flushExpectation.fulfill()
            }
        }
        self.waitForExpectations(timeout: 1.0, handler: nil)

        let mockObserver = MockObserver()

        XCTAssertEqual(0, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertNil(mockObserver.lastChange)
        mockObserver.clear()

        mockObserver.set(expectation: self.expectation(description: "Database Storage Observer"))

        let keyValueStore = SDSKeyValueStore(collection: "test")
        let otherKeyValueStore = SDSKeyValueStore(collection: "other")
        self.write { transaction in
            keyValueStore.setBool(true, key: "test", transaction: transaction)

            Logger.verbose("write 1 complete")
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertNotNil(mockObserver.lastChange)
        if let lastChange = mockObserver.lastChange {
            XCTAssertFalse(lastChange.didUpdateInteractions)
            XCTAssertFalse(lastChange.didUpdateThreads)
            XCTAssertFalse(lastChange.didUpdateInteractionsOrThreads)
            XCTAssertFalse(lastChange.didUpdateModel(collection: OWSDevice.collection()))
            XCTAssertFalse(lastChange.didUpdateModel(collection: "invalid collection name"))
            XCTAssertTrue(lastChange.didUpdate(keyValueStore: keyValueStore))
            // Note: For GRDB, didUpdate(keyValueStore:) currently returns true
            //       if any key value stores was updated.
            if self.storageCoordinator.state == .YDB ||
                self.storageCoordinator.state == .ydbTests {
                XCTAssertFalse(lastChange.didUpdate(keyValueStore: otherKeyValueStore))
            } else {
                XCTAssertTrue(lastChange.didUpdate(keyValueStore: otherKeyValueStore))
            }
        }
        mockObserver.clear()

        mockObserver.set(expectation: self.expectation(description: "Database Storage Observer"))

        self.write { transaction in
            let recipient = SignalServiceAddress(phoneNumber: "+15551234567")
            _ = TSContactThread.getOrCreateThread(withContactAddress: recipient, transaction: transaction)

            Logger.verbose("write 2 complete")
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertNotNil(mockObserver.lastChange)
        if let lastChange = mockObserver.lastChange {
            XCTAssertFalse(lastChange.didUpdateInteractions)
            XCTAssertTrue(lastChange.didUpdateThreads)
            XCTAssertTrue(lastChange.didUpdateInteractionsOrThreads)
            XCTAssertFalse(lastChange.didUpdateModel(collection: OWSDevice.collection()))
            XCTAssertFalse(lastChange.didUpdateModel(collection: "invalid collection name"))
            XCTAssertFalse(lastChange.didUpdate(keyValueStore: keyValueStore))
            XCTAssertFalse(lastChange.didUpdate(keyValueStore: otherKeyValueStore))
        }
        mockObserver.clear()

        mockObserver.set(expectation: self.expectation(description: "Database Storage Observer"))

        var lastMessage: TSInteraction?
        var unsavedMessage: TSInteraction?
        self.write { transaction in
            let recipient = SignalServiceAddress(phoneNumber: "+12345678900")
            let thread = TSContactThread.getOrCreateThread(withContactAddress: recipient, transaction: transaction)
            let message = TSOutgoingMessage(in: thread, messageBody: "Hello Alice", attachmentId: nil)
            message.anyInsert(transaction: transaction)
            message.anyReload(transaction: transaction)
            lastMessage = message

            unsavedMessage = TSOutgoingMessage(in: thread, messageBody: "Goodbyte Alice", attachmentId: nil)

            Logger.verbose("write 3 complete")
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertNotNil(mockObserver.lastChange)
        if let lastChange = mockObserver.lastChange {
            XCTAssertTrue(lastChange.didUpdateInteractions)
            XCTAssertTrue(lastChange.didUpdateThreads)
            XCTAssertTrue(lastChange.didUpdateInteractionsOrThreads)
            XCTAssertFalse(lastChange.didUpdateModel(collection: OWSDevice.collection()))
            XCTAssertFalse(lastChange.didUpdateModel(collection: "invalid collection name"))
            XCTAssertFalse(lastChange.didUpdate(keyValueStore: keyValueStore))
            XCTAssertFalse(lastChange.didUpdate(keyValueStore: otherKeyValueStore))
            XCTAssertTrue(lastChange.didUpdate(interaction: lastMessage!))
            XCTAssertFalse(lastChange.didUpdate(interaction: unsavedMessage!))
        }
        mockObserver.clear()

        mockObserver.set(expectation: self.expectation(description: "Database Storage Observer"))

        self.write { transaction in
            self.databaseStorage.touch(thread: someThread!, transaction: transaction)
            Logger.verbose("Touch complete")
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertNotNil(mockObserver.lastChange)
        if let lastChange = mockObserver.lastChange {
            XCTAssertFalse(lastChange.didUpdateInteractions)
            XCTAssertTrue(lastChange.didUpdateThreads)
            XCTAssertTrue(lastChange.didUpdateInteractionsOrThreads)
            XCTAssertFalse(lastChange.didUpdateModel(collection: OWSDevice.collection()))
            XCTAssertFalse(lastChange.didUpdateModel(collection: "invalid collection name"))
            XCTAssertFalse(lastChange.didUpdate(keyValueStore: keyValueStore))
            XCTAssertFalse(lastChange.didUpdate(keyValueStore: otherKeyValueStore))
            XCTAssertFalse(lastChange.didUpdate(interaction: lastMessage!))
            XCTAssertFalse(lastChange.didUpdate(interaction: unsavedMessage!))
        }
        mockObserver.clear()

        mockObserver.set(expectation: self.expectation(description: "Database Storage Observer"))

        self.write { transaction in
            self.databaseStorage.touch(interaction: lastMessage!, transaction: transaction)
            Logger.verbose("Touch complete")
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertNotNil(mockObserver.lastChange)
        if let lastChange = mockObserver.lastChange {
            XCTAssertTrue(lastChange.didUpdateInteractions)
            XCTAssertFalse(lastChange.didUpdateThreads)
            XCTAssertTrue(lastChange.didUpdateInteractionsOrThreads)
            XCTAssertFalse(lastChange.didUpdateModel(collection: OWSDevice.collection()))
            XCTAssertFalse(lastChange.didUpdateModel(collection: "invalid collection name"))
            XCTAssertFalse(lastChange.didUpdate(keyValueStore: keyValueStore))
            XCTAssertFalse(lastChange.didUpdate(keyValueStore: otherKeyValueStore))
            XCTAssertTrue(lastChange.didUpdate(interaction: lastMessage!))
            XCTAssertFalse(lastChange.didUpdate(interaction: unsavedMessage!))
        }
        mockObserver.clear()
    }

    func testGRDBAsyncWrite() {

        try! databaseStorage.grdbStorage.setupUIDatabase()

        // Make sure there's already at least one thread.
        var someThread: TSThread?
        self.write { transaction in
            let recipient = SignalServiceAddress(phoneNumber: "+1222333444")
            someThread = TSContactThread.getOrCreateThread(withContactAddress: recipient, transaction: transaction)
        }

        // First flush any pending notifications in SDSDatabaseStorageObservation
        // from setup.
        let flushExpectation = self.expectation(description: "Database Storage Observer")
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                flushExpectation.fulfill()
            }
        }
        self.waitForExpectations(timeout: 1.0, handler: nil)

        let mockObserver = MockObserver()

        XCTAssertEqual(0, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertNil(mockObserver.lastChange)
        mockObserver.clear()

        mockObserver.set(expectation: self.expectation(description: "Database Storage Observer"))

        let keyValueStore = SDSKeyValueStore(collection: "test")
        let otherKeyValueStore = SDSKeyValueStore(collection: "other")
        self.asyncWrite { transaction in
            keyValueStore.setBool(true, key: "test", transaction: transaction)

            Logger.verbose("write 1 complete")
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertNotNil(mockObserver.lastChange)
        if let lastChange = mockObserver.lastChange {
            XCTAssertFalse(lastChange.didUpdateInteractions)
            XCTAssertFalse(lastChange.didUpdateThreads)
            XCTAssertFalse(lastChange.didUpdateInteractionsOrThreads)
            XCTAssertFalse(lastChange.didUpdateModel(collection: OWSDevice.collection()))
            XCTAssertFalse(lastChange.didUpdateModel(collection: "invalid collection name"))
            XCTAssertTrue(lastChange.didUpdate(keyValueStore: keyValueStore))
            // Note: For GRDB, didUpdate(keyValueStore:) currently returns true
            //       if any key value stores was updated.
            if self.storageCoordinator.state == .YDB ||
                self.storageCoordinator.state == .ydbTests {
                XCTAssertFalse(lastChange.didUpdate(keyValueStore: otherKeyValueStore))
            } else {
                XCTAssertTrue(lastChange.didUpdate(keyValueStore: otherKeyValueStore))
            }
        }
        mockObserver.clear()

        mockObserver.set(expectation: self.expectation(description: "Database Storage Observer"))

        self.asyncWrite { transaction in
            let recipient = SignalServiceAddress(phoneNumber: "+15551234567")
            _ = TSContactThread.getOrCreateThread(withContactAddress: recipient, transaction: transaction)

            Logger.verbose("write 2 complete")
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertNotNil(mockObserver.lastChange)
        if let lastChange = mockObserver.lastChange {
            XCTAssertFalse(lastChange.didUpdateInteractions)
            XCTAssertTrue(lastChange.didUpdateThreads)
            XCTAssertTrue(lastChange.didUpdateInteractionsOrThreads)
            XCTAssertFalse(lastChange.didUpdateModel(collection: OWSDevice.collection()))
            XCTAssertFalse(lastChange.didUpdateModel(collection: "invalid collection name"))
            XCTAssertFalse(lastChange.didUpdate(keyValueStore: keyValueStore))
            XCTAssertFalse(lastChange.didUpdate(keyValueStore: otherKeyValueStore))
        }
        mockObserver.clear()

        mockObserver.set(expectation: self.expectation(description: "Database Storage Observer"))

        var lastMessage: TSInteraction?
        var unsavedMessage: TSInteraction?
        self.asyncWrite { transaction in
            let recipient = SignalServiceAddress(phoneNumber: "+12345678900")
            let thread = TSContactThread.getOrCreateThread(withContactAddress: recipient, transaction: transaction)
            let message = TSOutgoingMessage(in: thread, messageBody: "Hello Alice", attachmentId: nil)
            message.anyInsert(transaction: transaction)
            message.anyReload(transaction: transaction)
            lastMessage = message

            unsavedMessage = TSOutgoingMessage(in: thread, messageBody: "Goodbyte Alice", attachmentId: nil)

            Logger.verbose("write 3 complete")
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertNotNil(mockObserver.lastChange)
        if let lastChange = mockObserver.lastChange {
            XCTAssertTrue(lastChange.didUpdateInteractions)
            XCTAssertTrue(lastChange.didUpdateThreads)
            XCTAssertTrue(lastChange.didUpdateInteractionsOrThreads)
            XCTAssertFalse(lastChange.didUpdateModel(collection: OWSDevice.collection()))
            XCTAssertFalse(lastChange.didUpdateModel(collection: "invalid collection name"))
            XCTAssertFalse(lastChange.didUpdate(keyValueStore: keyValueStore))
            XCTAssertFalse(lastChange.didUpdate(keyValueStore: otherKeyValueStore))
            XCTAssertTrue(lastChange.didUpdate(interaction: lastMessage!))
            XCTAssertFalse(lastChange.didUpdate(interaction: unsavedMessage!))
        }
        mockObserver.clear()

        mockObserver.set(expectation: self.expectation(description: "Database Storage Observer"))

        self.asyncWrite { transaction in
            self.databaseStorage.touch(thread: someThread!, transaction: transaction)
            Logger.verbose("Touch complete")
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertNotNil(mockObserver.lastChange)
        if let lastChange = mockObserver.lastChange {
            XCTAssertFalse(lastChange.didUpdateInteractions)
            XCTAssertTrue(lastChange.didUpdateThreads)
            XCTAssertTrue(lastChange.didUpdateInteractionsOrThreads)
            XCTAssertFalse(lastChange.didUpdateModel(collection: OWSDevice.collection()))
            XCTAssertFalse(lastChange.didUpdateModel(collection: "invalid collection name"))
            XCTAssertFalse(lastChange.didUpdate(keyValueStore: keyValueStore))
            XCTAssertFalse(lastChange.didUpdate(keyValueStore: otherKeyValueStore))
            XCTAssertFalse(lastChange.didUpdate(interaction: lastMessage!))
            XCTAssertFalse(lastChange.didUpdate(interaction: unsavedMessage!))
        }
        mockObserver.clear()

        mockObserver.set(expectation: self.expectation(description: "Database Storage Observer"))

        self.asyncWrite { transaction in
            self.databaseStorage.touch(interaction: lastMessage!, transaction: transaction)
            Logger.verbose("Touch complete")
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertNotNil(mockObserver.lastChange)
        if let lastChange = mockObserver.lastChange {
            XCTAssertTrue(lastChange.didUpdateInteractions)
            XCTAssertFalse(lastChange.didUpdateThreads)
            XCTAssertTrue(lastChange.didUpdateInteractionsOrThreads)
            XCTAssertFalse(lastChange.didUpdateModel(collection: OWSDevice.collection()))
            XCTAssertFalse(lastChange.didUpdateModel(collection: "invalid collection name"))
            XCTAssertFalse(lastChange.didUpdate(keyValueStore: keyValueStore))
            XCTAssertFalse(lastChange.didUpdate(keyValueStore: otherKeyValueStore))
            XCTAssertTrue(lastChange.didUpdate(interaction: lastMessage!))
            XCTAssertFalse(lastChange.didUpdate(interaction: unsavedMessage!))
        }
        mockObserver.clear()
    }
}
