import XCTest
import GRDB
@testable import Todos

class AppDatabaseTests: XCTestCase {
    func test_database_schema() throws {
        // Given an empty database
        let dbQueue = try DatabaseQueue()

        // When we instantiate an AppDatabase
        _ = try AppDatabase(dbQueue)

        // Then the player table exists, with id, name & score columns
        try dbQueue.read { db in
            try XCTAssert(db.tableExists("todoState"))
            let columns = try db.columns(in: "todoState")
            let columnNames = Set(columns.map { $0.name })
            XCTAssertEqual(columnNames, ["id", "description", "isComplete"])
        }
    }
}
