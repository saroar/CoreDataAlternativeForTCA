import ComposableArchitecture
import SwiftUI
import GRDB
import Foundation

typealias TodoState = Todo.State

struct Todo: ReducerProtocol {
  struct State: Codable, Equatable, Identifiable {
    var id: UUID
    var description = ""
    var isComplete = false
  }

  enum Action: Equatable {
    case checkBoxToggled
    case textFieldChanged(String)
  }
    @Dependency(\.continuousClock) var clock
    @Dependency(\.localDatabase) private var localDatabase

  func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
    switch action {
    case .checkBoxToggled:
      state.isComplete.toggle()
      return .none

    case let .textFieldChanged(description):
      state.description = description
        return .run { [state = state] send in
            try await self.clock.sleep(for: .seconds(5))
            do {
                try await self.localDatabase.update(state.id, state)
            } catch {
                print(#line, "error \(error.localizedDescription)")
            }
        }

    }
  }
}

extension TodoState {
    private static let names = [
        "Arthur", "Anita", "Barbara", "Bernard", "Craig", "Chiara", "David",
        "Dean", "Éric", "Elena", "Fatima", "Frederik", "Gilbert", "Georgette",
        "Henriette", "Hassan", "Ignacio", "Irene", "Julie", "Jack", "Karl",
        "Kristel", "Louis", "Liz", "Masashi", "Mary", "Noam", "Nicole",
        "Ophelie", "Oleg", "Pascal", "Patricia", "Quentin", "Quinn", "Raoul",
        "Rachel", "Stephan", "Susie", "Tristan", "Tatiana", "Ursule", "Urbain",
        "Victor", "Violette", "Wilfried", "Wilhelmina", "Yvon", "Yann",
        "Zazie", "Zoé"]

    /// Creates a new player with empty name and zero score
    static func new() -> Todo.State {
        Todo.State(id: UUID(), description: "", isComplete: false)
    }

    /// Creates a new player with random name and random score
    static func makeRandom() -> Todo.State {
        Todo.State(id: UUID(), description: randomName(), isComplete: false)
    }

    /// Returns a random name
    static func randomName() -> String {
        names.randomElement()!
    }

    /// Returns a random score
    static func randomScore() -> String {
       "\(10 * Int.random(in: 0...100))"
    }
}

// MARK: - Persistence

/// Make Player a Codable Record.
///
/// See <https://github.com/groue/GRDB.swift/blob/master/README.md#records>
extension Todo.State: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "todoState"

    // Define database columns from CodingKeys
    fileprivate enum Columns {
        static let description = Column(CodingKeys.description)
        static let isComplete = Column(CodingKeys.isComplete)
    }

    /// Updates a player id after it has been inserted in the database.
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = UUID(uuidString: inserted.rowIDColumn ?? UUID().uuidString)!
    }
}

// MARK: - Player Database Requests

/// Define some player requests used by the application.
///
/// See <https://github.com/groue/GRDB.swift/blob/master/README.md#requests>
/// See <https://github.com/groue/GRDB.swift/blob/master/Documentation/GoodPracticesForDesigningRecordTypes.md>
extension DerivableRequest<TodoState> {
    /// A request of players ordered by name.
    ///
    /// For example:
    ///
    ///     let players: [Player] = try dbWriter.read { db in
    ///         try Player.all().orderedByName().fetchAll(db)
    ///     }
    func orderedByName() -> Self {
        // Sort by name in a localized case insensitive fashion
        // See https://github.com/groue/GRDB.swift/blob/master/README.md#string-comparison
        order(TodoState.Columns.description.collating(.localizedCaseInsensitiveCompare))
    }

    /// A request of players ordered by score.
    ///
    /// For example:
    ///
    ///     let players: [Player] = try dbWriter.read { db in
    ///         try Player.all().orderedByScore().fetchAll(db)
    ///     }
    ///     let bestPlayer: Player? = try dbWriter.read { db in
    ///         try Player.all().orderedByScore().fetchOne(db)
    ///     }
    func orderedByScore() -> Self {
        // Sort by descending score, and then by name, in a
        // localized case insensitive fashion
        // See https://github.com/groue/GRDB.swift/blob/master/README.md#string-comparison
        order(
            TodoState.Columns.description.desc,
            TodoState.Columns.description.collating(.localizedCaseInsensitiveCompare))
    }
}


struct TodoView: View {
  let store: StoreOf<Todo>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      HStack {
        Button(action: { viewStore.send(.checkBoxToggled) }) {
          Image(systemName: viewStore.isComplete ? "checkmark.square" : "square")
        }
        .buttonStyle(.plain)

        TextField(
          "Untitled Todo",
          text: viewStore.binding(get: \.description, send: Todo.Action.textFieldChanged)
        )
      }
      .foregroundColor(viewStore.isComplete ? .gray : nil)
    }
  }
}
