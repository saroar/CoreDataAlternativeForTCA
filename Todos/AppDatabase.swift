import Foundation
import Dependencies
import GRDB

/// AppDatabase lets the application access the database.
///
/// It applies the pratices recommended at
/// <https://github.com/groue/GRDB.swift/blob/master/Documentation/GoodPracticesForDesigningRecordTypes.md>
public struct AppDatabase : Sendable{
    /// Creates an `AppDatabase`, and make sure the database schema is ready.
    init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try migrator.migrate(dbWriter)
    }

    /// Provides access to the database.
    ///
    /// Application can use a `DatabasePool`, while SwiftUI previews and tests
    /// can use a fast in-memory `DatabaseQueue`.
    ///
    /// See <https://github.com/groue/GRDB.swift/blob/master/README.md#database-connections>
    private let dbWriter: any DatabaseWriter

    /// The DatabaseMigrator that defines the database schema.
    ///
    /// See <https://swiftpackageindex.com/groue/grdb.swift/documentation/grdb/migrations>
    private var migrator: DatabaseMigrator {
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
}

// MARK: - Database Access: Writes

extension AppDatabase {
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

    /// Saves (inserts or updates) a player. When the method returns, the
    /// player is present in the database, and its id is not nil.
    @Sendable func savePlayer(_ todo: Todo.State) async throws {
        var todo = todo
        if todo.description.isEmpty {
            throw ValidationError.missingName
        }
        todo = try await dbWriter.write { [todo] db in
            try todo.saved(db)
        }
    }

    /// Delete the specified players
//    func deletePlayers(ids: [String]) async throws {
//        try await dbWriter.write { db in
//            _ = try TodoState.deleteAll(db, ids: ids)
//        }
//    }

    /// Delete all players
    func deleteAllTodos() async throws {
        try await dbWriter.write { db in
            _ = try TodoState.deleteAll(db)
        }
    }

    /// Refresh all players (by performing some random changes, for demo purpose).
    func refreshTodos() async throws {
        try await dbWriter.write { db in
            if try TodoState.all().isEmpty(db) {
                // When database is empty, insert new random players
                try createRandomPlayers(db)
            } else {
                // Insert a player
                if Bool.random() {
                    _ = try TodoState.makeRandom().inserted(db) // insert but ignore inserted id
                }

                // Delete a random player
                if Bool.random() {
                    try TodoState.order(sql: "RANDOM()").limit(1).deleteAll(db)
                }

                // Update some players
                for var player in try TodoState.fetchAll(db) where Bool.random() {
                    try player.updateChanges(db) {
                        $0.description = TodoState.randomScore()
                    }
                }
            }
        }
    }

    /// Create random players if the database is empty.
    func createRandomTodoStatesIfEmpty() throws -> [Todo.State] {
        var result: [TodoState] = []

        try dbWriter.write { db in
            if try TodoState.all().isEmpty(db) {
                result = try createRandomPlayers(db)
            } else {
                result = try TodoState.all().fetchAll(db)
            }
        }

        return result
    }

    static let uiTestPlayers = [

        TodoState(id: UUID(), description: "Hi", isComplete: false),
        TodoState(id: UUID(), description: "Hi", isComplete: false),
        TodoState(id: UUID(), description: "Hi", isComplete: false),
        TodoState(id: UUID(), description: "Hi", isComplete: false),
        TodoState(id: UUID(), description: "Hi", isComplete: false),
        TodoState(id: UUID(), description: "Hi", isComplete: false),
        TodoState(id: UUID(), description: "Hi", isComplete: false),
        TodoState(id: UUID(), description: "Hi", isComplete: false),
        TodoState(id: UUID(), description: "Hi", isComplete: false),
        TodoState(id: UUID(), description: "Hi", isComplete: false),
        TodoState(id: UUID(), description: "Hi", isComplete: false)
    ]

    func createPlayersForUITests() throws {
        try dbWriter.write { db in
            try AppDatabase.uiTestPlayers.forEach { todo in
                _ = try todo.inserted(db) // insert but ignore inserted id
            }
        }
    }

    /// Support for `createRandomPlayersIfEmpty()` and `refreshPlayers()`.
    private func createRandomPlayers(_ db: Database) throws -> [Todo.State] {
        var result: [TodoState] = []
        for _ in 0..<8 {
            result.append( try TodoState.makeRandom().inserted(db)) // insert but ignore inserted id
        }
        return result
    }
}

// MARK: - Database Access: Reads

// This demo app does not provide any specific reading method, and instead
// gives an unrestricted read-only access to the rest of the application.
// In your app, you are free to choose another path, and define focused
// reading methods.
extension AppDatabase {
    /// Provides a read-only access to the database
    var databaseReader: DatabaseReader {
        dbWriter
    }
}

extension AppDatabase {
    /// The database for the application
    static let shared = makeShared()

    private static func makeShared() -> AppDatabase {
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

            // Create the AppDatabase
            let appDatabase = try AppDatabase(dbPool)

            // Prepare the database with test fixtures if requested
            if CommandLine.arguments.contains("-fixedTestData") {
                _ = try appDatabase.createPlayersForUITests()
            } else {
                // Otherwise, populate the database if it is empty, for better
                // demo purpose.
                _ = try appDatabase.createRandomTodoStatesIfEmpty()
            }

            return appDatabase
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

    /// Creates an empty database for SwiftUI previews
    static func empty() -> AppDatabase {
        // Connect to an in-memory database
        // See https://github.com/groue/GRDB.swift/blob/master/README.md#database-connections
        let dbQueue = try! DatabaseQueue()
        return try! AppDatabase(dbQueue)
    }

    /// Creates a database full of random players for SwiftUI previews
    static func random() -> AppDatabase {
        let appDatabase = empty()
        _ = try! appDatabase.createRandomTodoStatesIfEmpty()
        return appDatabase
    }
}

extension AppDatabase: DependencyKey, TestDependencyKey {
    public static let previewValue: AppDatabase = .random()
    public static var liveValue: AppDatabase = .shared
    public static var testValue: AppDatabase = .empty()

}

extension DependencyValues {
    public var appDatabase: AppDatabase {
        get { self[AppDatabase.self] }
        set { self[AppDatabase.self] = newValue }
    }
}
