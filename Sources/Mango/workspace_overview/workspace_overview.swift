/* mango WorkspaceOverviewScope (common/types.h) */
let ALL_WORKSPACE: Int32 = 0, OCCUPIED_WORKSPACE: Int32 = 1
/* mango WorkspaceOverviewLayout (common/types.h) */
let WORKSPACE_OVERVIEW_GRID: Int32 = 0, WORKSPACE_OVERVIEW_SCROLL: Int32 = 1

extension MangoServer {
    func toggleWorkspaceOverview(_ arg: Arg) -> Int32 {
        // not in mango: the workspace overview is not ported yet (MangoCompat)
        return 0
    }

    func enterWorkspaceOverview(_ arg: Arg) -> Int32 {
        // not in mango: the workspace overview is not ported yet (MangoCompat)
        return 0
    }

    func leaveWorkspaceOverview(_ arg: Arg) -> Int32 {
        // not in mango: the workspace overview is not ported yet (MangoCompat)
        return 0
    }
}
