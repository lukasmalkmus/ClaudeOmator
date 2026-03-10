import Foundation
import Observation
import SwiftUI

enum SidebarSelection: Hashable, Sendable {
    case workflow(UUID)
    case activity(workflowID: UUID, runID: UUID)
}

@Observable
final class NavigationState {
    var selection: SidebarSelection?
    var detailPath = NavigationPath()

    struct ActivityDestination: Hashable, Sendable {
        let workflowID: UUID
        let runID: UUID
    }
}
