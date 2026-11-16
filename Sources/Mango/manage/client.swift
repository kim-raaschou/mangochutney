import CoreGraphics

package extension MangoServer {
    func clientGetClip(_ c: Client) -> CGRect {
        // not in mango: the xdg geometry's offset (clip->x, clip->y) is 0
        CGRect(x: 0, y: 0, width: c.geom.width - 2 * c.bw, height: c.geom.height - 2 * c.bw)
    }

    func clientSetSizeBound(_ c: Client) {
        let state = system.clientSizeHints(c)   // not in mango: the port's toplevel->current min and max size

        if c.geom.width - 2 * c.bw < state.minWidth && state.minWidth > 0 {
            c.geom.size.width = state.minWidth + 2 * c.bw
        }
        if c.geom.height - 2 * c.bw < state.minHeight && state.minHeight > 0 {
            c.geom.size.height = state.minHeight + 2 * c.bw
        }
        if c.geom.width - 2 * c.bw > state.maxWidth && state.maxWidth > 0 {
            c.geom.size.width = state.maxWidth + 2 * c.bw
        }
        if c.geom.height - 2 * c.bw > state.maxHeight && state.maxHeight > 0 {
            c.geom.size.height = state.maxHeight + 2 * c.bw
        }
    }

    func clientSetBounds(_ c: Client, _ bbox: CGRect) {
        /* set minimum possible */
        c.geom.size.width = max(1 + 2 * c.bw, c.geom.width)
        c.geom.size.height = max(1 + 2 * c.bw, c.geom.height)

        if c.geom.minX >= bbox.minX + bbox.width { c.geom.origin.x = bbox.minX + bbox.width - c.geom.width }
        if c.geom.minY >= bbox.minY + bbox.height { c.geom.origin.y = bbox.minY + bbox.height - c.geom.height }
        if c.geom.minX + c.geom.width <= bbox.minX { c.geom.origin.x = bbox.minX }
        if c.geom.minY + c.geom.height <= bbox.minY { c.geom.origin.y = bbox.minY }
    }

    /* Single place judging whether a window's nodes should be enabled.
     * Each flag below is owned by the mechanism that sets it; this only reads. */
    func clientShouldVisible(_ c: Client) -> Bool {
        // not in mango: no snapshot_temp_visible (no close animation)

        if c.isminimized && !c.animation.tagouting { return false }

        if c.isClipToHide { return false }

        // not in mango: the overview's card tree (ov_card_tree) and overview_scene_surface are the port's pictures

        if c.isTabHidden { return false }

        if c.iskilling { return false }

        if c.animation.tagouting { return true }

        if clientGestureDriven(c) && (c.animation.tagining || c.animation.tagouting) { return true }

        return c.tagVisible
    }

    func clientUpdateVisibility(_ c: Client) {
        // not in mango: client_update_input_penetration (macOS gives a moving window its clicks)

        let show = clientShouldVisible(c)

        if c.platform.sceneNodeEnabled != show {
            system.sceneNodeSetEnabled(c, show)   // not in mango: the port's wlr_scene_node_set_enabled
        }

        let surfaceShow = !c.isSurfaceHidden

        if c.platform.sceneSurfaceEnabled != surfaceShow {
            system.sceneSurfaceSetEnabled(c, surfaceShow)   // not in mango: the port's wlr_scene_node_set_enabled
        }
    }
}
