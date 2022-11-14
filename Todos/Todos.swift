import ComposableArchitecture
@preconcurrency import SwiftUI
import GRDB
//
//class SqlTest {
//
//    init() {
//        do {
//            let db = try Connection("path/to/db.sqlite3")
//        } catch {
//
//        }
//
//        let users = Table("words")
//    }
//}


enum Filter: LocalizedStringKey, CaseIterable, Hashable {
  case all = "All"
  case active = "Active"
  case completed = "Completed"
}

struct Todos: ReducerProtocol, Sendable {
  struct State: Equatable {
    var editMode: EditMode = .inactive
    var filter: Filter = .all
    var todos: IdentifiedArrayOf<Todo.State> = []

    var filteredTodos: IdentifiedArrayOf<Todo.State> {
      switch filter {
      case .active: return self.todos.filter { !$0.isComplete }
      case .all: return self.todos
      case .completed: return self.todos.filter(\.isComplete)
      }
    }
  }

    enum Action: Equatable, Sendable {
    case onAppear
    case addTodoButtonTapped
    case clearCompletedButtonTapped
    case delete(IndexSet)
    case editModeChanged(EditMode)
    case filterPicked(Filter)
    case move(IndexSet, Int)
    case sortCompletedTodos
    case todo(id: Todo.State.ID, action: Todo.Action)
    case fetchTodoStateFromLocalData(TaskResult<[Todo.State]>)
  }

  @Dependency(\.continuousClock) var clock
  @Dependency(\.uuid) var uuid
  @Dependency(\.localDatabase) private var appDatabase

  private enum TodoCompletionID {}

  var body: some ReducerProtocol<State, Action> {
    Reduce { state, action in
      switch action {
      case .onAppear:

          return .run { send in
              do {
                  let res = try await appDatabase.find()
                  await send(.fetchTodoStateFromLocalData(.success(res)))
              } catch {

              }
          }

      case .fetchTodoStateFromLocalData(.success(let res)):
          state.todos = .init(uniqueElements: res)
          return .none
      case  .fetchTodoStateFromLocalData(.failure):
          return .none

      case .addTodoButtonTapped:
          let todoState = Todo.State(id: self.uuid())
          state.todos.insert(todoState, at: 0)

          return .run { _ in
              do {
                  try await self.appDatabase.create(Todo.State(id: self.uuid(), description: "Demo", isComplete: true))
              } catch {
                  print("error")
              }
          }

      case .clearCompletedButtonTapped:
        state.todos.removeAll(where: \.isComplete)
        return .none

      case let .delete(indexSet):
        state.todos.remove(atOffsets: indexSet)
        return .none

      case let .editModeChanged(editMode):
        state.editMode = editMode
        return .none

      case let .filterPicked(filter):
        state.filter = filter
        return .none

      case var .move(source, destination):
        if state.filter == .completed {
          source = IndexSet(
            source
              .map { state.filteredTodos[$0] }
              .compactMap { state.todos.index(id: $0.id) }
          )
          destination =
            (destination < state.filteredTodos.endIndex
              ? state.todos.index(id: state.filteredTodos[destination].id)
              : state.todos.endIndex)
            ?? destination
        }

        state.todos.move(fromOffsets: source, toOffset: destination)

        return .task {
          try await self.clock.sleep(for: .milliseconds(100))
          return .sortCompletedTodos
        }

      case .sortCompletedTodos:
        state.todos.sort { $1.isComplete && !$0.isComplete }
        return .none

      case .todo(id: _, action: .checkBoxToggled):
        return .run { send in
          try await self.clock.sleep(for: .seconds(1))
          await send(.sortCompletedTodos, animation: .default)
        }
        .cancellable(id: TodoCompletionID.self, cancelInFlight: true)

      case .todo:
        return .none

      }
    }
    .forEach(\.todos, action: /Action.todo(id:action:)) {
      Todo()
    }
  }
}

struct AppView: View {
  let store: StoreOf<Todos>
  @ObservedObject var viewStore: ViewStore<ViewState, Todos.Action>

  init(store: StoreOf<Todos>) {
    self.store = store
    self.viewStore = ViewStore(self.store.scope(state: ViewState.init(state:)))
  }

  struct ViewState: Equatable {
    let editMode: EditMode
    let filter: Filter
    let isClearCompletedButtonDisabled: Bool

    init(state: Todos.State) {
      self.editMode = state.editMode
      self.filter = state.filter
      self.isClearCompletedButtonDisabled = !state.todos.contains(where: \.isComplete)
    }
  }

  var body: some View {
    NavigationView {
      VStack(alignment: .leading) {
        Picker(
          "Filter",
          selection: self.viewStore.binding(
            get: \.filter,
            send: Todos.Action.filterPicked
          )
          .animation()
        ) {
          ForEach(Filter.allCases, id: \.self) { filter in
            Text(filter.rawValue).tag(filter)
          }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)

        List {
          ForEachStore(
            self.store.scope(state: \.filteredTodos, action: Todos.Action.todo(id:action:))
          ) {
            TodoView(store: $0)
          }
          .onDelete { self.viewStore.send(.delete($0)) }
          .onMove { self.viewStore.send(.move($0, $1)) }
        }
      }
      .onAppear { viewStore.send(.onAppear) }
      .navigationTitle("Todos")
      .navigationBarItems(
        trailing: HStack(spacing: 20) {
          EditButton()
          Button("Clear Completed") {
            self.viewStore.send(.clearCompletedButtonTapped, animation: .default)
          }
          .disabled(self.viewStore.isClearCompletedButtonDisabled)
          Button("Add Todo") { self.viewStore.send(.addTodoButtonTapped, animation: .default) }
        }
      )
      .environment(
        \.editMode,
        self.viewStore.binding(get: \.editMode, send: Todos.Action.editModeChanged)
      )
    }
    .navigationViewStyle(.stack)
  }
}

extension IdentifiedArray where ID == Todo.State.ID, Element == Todo.State {
  static let mock: Self = [
    Todo.State(
        id: UUID(uuidString: "DEADBEEF-DEAD-BEEF-DEAD-BEEDDEADBEEF")!,
      description: "Check Mail",
      isComplete: false
    ),
    Todo.State(
        id: UUID(uuidString: "CAFEBEEF-CAFE-BEEF-CAFE-BEEFCAFEBEEF")!,
      description: "Buy Milk",
      isComplete: false
    ),
    Todo.State(
        id: UUID(uuidString: "D00DCAFE-D00D-CAFE-D00D-CAFED00DCAFE")!,
      description: "Call Mom",
      isComplete: true
    ),
  ]
}

struct AppView_Previews: PreviewProvider {
  static var previews: some View {
    AppView(
      store: Store(
        initialState: Todos.State(todos: .mock),
        reducer: Todos()
      )
    )
  }
}
