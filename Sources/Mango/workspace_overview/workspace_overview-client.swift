import CoreGraphics

// not in mango: no live projection; the port draws every window as a picture in its cell, so no cell
// mounts a client's surface live (wsov_cell_live_client_for, wsov_item_has_effect_border,
// wsov_cell_contains_live_client, wsov_live_owner_for_client, wsov_remove_live_surface,
// wsov_live_surface_commit, wsov_live_surface_destroy, wsov_live_surface_frame_done, wsov_live_client_add,
// wsov_live_surface_add, wsov_clear_cell_live_surfaces, wsov_destroy_cell_live_trees,
// wsov_create_cell_live_trees, wsov_order_live_projection, wsov_order_live_projections,
// wsov_order_live_clients, wsov_sync_live_client_layers, wsov_cell_live_projection_matches,
// wsov_build_cell_live_projection, wsov_update_live_desires, wsov_live_client_clip)

extension MangoServer {
    func wsovItemIsLive(_ cell: WsovCell?, _ item: WsovItem?) -> Bool {
        // not in mango: no cell has live surfaces
        return false
    }

    func wsovClearLiveProjection(_ markDirty: Bool) {
        wsov.liveCell = nil
    }

    /// mango wsov_sync_live_projection (client.c)
    // not in mango: only the live cell is kept (no live surfaces to mount)
    func wsovSyncLiveProjection(_ view: WsovCameraView) -> Bool {
        if wsov.closing {
            return false
        }
        guard let target = wsovCellForTag(wsov.targetTag), wsov.root != nil else { return false }
        wsov.liveCell = target
        return false
    }

    func wsovRebuildLiveProjection() {
        if wsov.closing || wsov.root == nil {
            return
        }
        wsovLayoutLiveProjection()
        _ = wsovRenderDirtyCells(false)
    }

    /// mango wsov_layout_live_projection_impl (client.c)
    // not in mango: no live surfaces to place
    func wsovLayoutLiveProjectionImpl() {
        if wsov.mon == nil || wsov.cells.count <= 0 {
            return
        }

        var view = WsovCameraView()
        if !wsovGetCameraView(wsov.progress, &view) {
            return
        }
        if !wsov.closing {
            _ = wsovSyncLiveProjection(view)
        }
    }

    func wsovLayoutLiveProjection() {
        if wsov.liveLayoutFlushing {
            return
        }
        wsov.liveLayoutDirty = false
        wsov.liveLayoutFlushing = true
        wsovLayoutLiveProjectionImpl()
        wsov.liveLayoutFlushing = false
    }

    func wsovMarkLiveLayoutDirty() {
        if !workspaceOverviewIsActive() {
            return
        }
        wsov.liveLayoutDirty = true
        if let m = wsov.mon {
            system.outputScheduleFrame(m)
        }
    }

    func wsovFlushLiveLayout() {
        if !wsov.liveLayoutDirty || wsov.liveLayoutFlushing ||
            !workspaceOverviewIsActive() {
            return
        }
        wsovLayoutLiveProjection()
    }
}
