import Foundation
import Dependencies
import GRDB

public struct LocalDatabaseClient : Sendable {
    var create: @Sendable (TodoState) async throws -> Void
    var update: @Sendable (TodoState.ID, TodoState) async throws -> Void
    var find:  @Sendable () async throws -> [TodoState]
    var findBy: @Sendable (Todo.State.ID) async throws -> TodoState?
    var deleteBy: @Sendable (Todo.State.ID) async throws -> Void
}

extension LocalDatabaseClient {

    @Sendable  public static func dbWriter() throws -> DatabaseWriter {
        /// Provides access to the database.
        ///
        /// Application can use a `DatabasePool`, while SwiftUI previews and tests
        /// can use a fast in-memory `DatabaseQueue`.
        ///
        /// See <https://github.com/groue/GRDB.swift/blob/master/README.md#database-connections>
        let dbWriter: any DatabaseWriter

        /// The DatabaseMigrator that defines the database schema.
        ///
        /// See <https://swiftpackageindex.com/groue/grdb.swift/documentation/grdb/migrations>
        var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        // Speed up development by nuking the database when migrations change
        // See <https://swiftpackageindex.com/groue/grdb.swift/documentation/grdb/migrations>
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("createTodoState") { db in
            // Create a table
            // See https://github.com/groue/GRDB.swift#create-tables
            try db.create(table: "todoState") { t in
                t.column("id", .text).notNull().unique()
                t.primaryKey(["id"])
                t.column("description", .text).notNull()
                t.column("isComplete", .boolean).notNull()
            }
        }

        // Migrations for future application versions will be inserted here:
        // migrator.registerMigration(...) { db in
        //     ...
        // }

        return migrator
    }


        do {
            // Pick a folder for storing the SQLite database, as well as
            // the various temporary files created during normal database
            // operations (https://sqlite.org/tempfiles.html).
            let fileManager = FileManager()
            let folderURL = try fileManager.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                .appendingPathComponent("database", isDirectory: true)
            // /path/to/database.sqlite
            // Support for tests: delete the database if requested
            if CommandLine.arguments.contains("-reset") {
                try? fileManager.removeItem(at: folderURL)
            }

            // Create the database folder if needed
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

            // Connect to a database on disk
            // See https://github.com/groue/GRDB.swift/blob/master/README.md#database-connections
            let dbURL = folderURL.appendingPathComponent("db.sqlite")
            let dbPool = try DatabasePool(path: dbURL.path)
            dbWriter = dbPool

            // Prepare the database with test fixtures if requested
//            if CommandLine.arguments.contains("-fixedTestData") {
//                _ = try appDatabase.createPlayersForUITests()
//            } else {
//                // Otherwise, populate the database if it is empty, for better
//                // demo purpose.
//                _ = try appDatabase.createRandomTodoStatesIfEmpty()
//            }

            try migrator.migrate(dbWriter)

            return dbWriter
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate.
            //
            // Typical reasons for an error here include:
            // * The parent directory cannot be created, or disallows writing.
            // * The database is not accessible, due to permissions or data protection when the device is locked.
            // * The device is out of space.
            // * The database could not be migrated to its latest schema version.
            // Check the error message to determine what the actual problem was.
            fatalError("Unresolved error \(error)")
        }
    }

    // for make dynamic so cant be CURD for any model
//    public func load<A: Decodable>(_ type: A.Type, from fileName: String) async throws -> A
//    public func save<A: Encodable>(_ data: A, to fileName: String) async throws
}

extension LocalDatabaseClient {
    /// A validation error that prevents some players from being saved into
    /// the database.
    enum ValidationError: LocalizedError {
        case missingName

        var errorDescription: String? {
            switch self {
            case .missingName:
                return "Please provide a name"
            }
        }
    }

    public static var liveV: LocalDatabaseClient = .init(
        create: { todo in
            var todo = todo
            if todo.description.isEmpty {
                throw ValidationError.missingName
            }
            todo = try await dbWriter().write { [todo] db in
                try todo.saved(db)
            }
        },

        update: { id, todo in
            try await dbWriter().write { db in
                if var todo = try TodoState.fetchOne(db, id: id) {
                    todo = todo
                    try todo.update(db)
                }
            }
        },

        find: {
            try await dbWriter().write { db in
                try TodoState.all().fetchAll(db)
            }
        },

        findBy: { id in
            try await dbWriter().write { db in
                try TodoState.fetchOne(db, id: id)
            }
        },

        deleteBy: { id in
            try await dbWriter().write { db in
                if var todo = try TodoState.fetchOne(db, id: id) {
                    try todo.delete(db)
                }
            }
        }
    )

}

extension LocalDatabaseClient: DependencyKey {
    public static var liveValue: LocalDatabaseClient = .liveV
}


extension DependencyValues {
    public var localDatabase: LocalDatabaseClient {
        get { self[LocalDatabaseClient.self] }
        set { self[LocalDatabaseClient.self] = newValue }
    }
}
