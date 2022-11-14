import ComposableArchitecture
import SwiftUI
import GRDBQuery

@main
struct TodosApp: App {
  var body: some Scene {
    WindowGroup {
      AppView(
        store: Store(
          initialState: Todos.State(),
          reducer: Todos()._printChanges()
        )
      )
    }
  }
}

//private struct AppDatabaseKey: EnvironmentKey {
//    static var defaultValue: AppDatabase { .empty() }
//}
//
//extension EnvironmentValues {
//    var appDatabase: AppDatabase {
//        get { self[AppDatabaseKey.self] }
//        set { self[AppDatabaseKey.self] = newValue }
//    }
//}
//
//// In this demo app, views observe the database with the @Query property
//// wrapper, defined in the GRDBQuery package. Its documentation recommends to
//// define a dedicated initializer for `appDatabase` access, so we comply:
//
//extension Query where Request.DatabaseContext == AppDatabase {
//    /// Convenience initializer for requests that feed from `AppDatabase`.
//    init(_ request: Request) {
//        self.init(request, in: \.appDatabase)
//    }
//}
