import Combine

@MainActor
final class MainLayoutState: ObservableObject {
    @Published var isSidebarCollapsed = false
}
