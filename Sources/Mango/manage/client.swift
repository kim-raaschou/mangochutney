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

    private func dwindleNodeDepth(_ node: DwindleNode?) -> Int32 {
        var depth: Int32 = 0
        var n = node
        while let x = n, x.parent != nil {
            depth += 1
            n = x.parent
        }
        return depth
    }

    private func dwindleNodeLca(_ a: DwindleNode?, _ b: DwindleNode?) -> DwindleNode? {
        guard var a, var b else { return nil }

        var da = dwindleNodeDepth(a)
        var db = dwindleNodeDepth(b)
        while da > db, let p = a.parent {
            a = p
            da -= 1
        }
        while db > da, let p = b.parent {
            b = p
            db -= 1
        }
        while a !== b {
            guard let pa = a.parent, let pb = b.parent else { return nil }
            a = pa
            b = pb
        }
        return a
    }

    /* Dwindle keeps a binary split tree. The focus memory may only kick in when the
     * target `sc` lives in the branch that is directly attached to `fc`, i.e. the
     * sibling subtree created when `fc` itself was split. If the target sits in a
     * higher ancestor branch, it is not part of fc's own subtree and the move is
     * left untouched. Within that directly attached branch the most recently
     * focused client wins, so the focus order is remembered for any tree shape. */
    func dwindleFocusBlockRoot(_ root: DwindleNode?, _ sc: Client, _ fc: Client?) -> DwindleNode? {
        let scLeaf = dwindleFindLeaf(root, sc)
        let fcLeaf = fc.flatMap { dwindleFindLeaf(root, $0) }
        guard let scLeaf, let fcLeaf, scLeaf !== fcLeaf, fcLeaf.parent != nil else { return nil }

        /* sc must be inside the branch that is directly attached to fc, so the
         * lca of both leaves has to be fc's own parent. Anything above it is an
         * ancestor branch of fc and must not use the focus memory. */
        guard let lca = dwindleNodeLca(scLeaf, fcLeaf), lca === fcLeaf.parent else { return nil }

        guard let branch = lca.first === fcLeaf ? lca.second : lca.first, branch.isSplit else { return nil }
        return branch
    }

    func dwindleFocusBlockHasClient(_ node: DwindleNode?, _ c: Client) -> Bool {
        guard let node else { return false }
        if !node.isSplit { return node.client === c }
        return dwindleFocusBlockHasClient(node.first, c) || dwindleFocusBlockHasClient(node.second, c)
    }

    func clientTileResize(_ c: Client, _ box: CGRect, _ interact: Bool, _ ctx: LayoutContext?) {
        var geo = box
        if let ctx, let probe = ctx.probe {
            if c === probe { ctx.out = geo }
            return
        }

        guard ISFAKETILED(c), let m = c.mon else { return }

        if !m.isoverview && !c.isfullscreen && clientWantsGroupBar(c) {
            geo.origin.y = geo.minY + CGFloat(config.groupBarHeight)
            geo.size.height -= CGFloat(config.groupBarHeight)
        }

        // not in mango: c->tab_prev || c->tab_next; the tab chain is the view's members (docs/afvigelser.md §5)
        if !m.isoverview && !c.isfullscreen && config.tabBarHeight > 0 && tabMembers(m).contains(where: { $0 === c }) {
            geo.origin.y = geo.minY + CGFloat(config.tabBarHeight)
            geo.size.height -= CGFloat(config.tabBarHeight)
        }

        if (!c.isfullscreen && !c.ismaximizescreen) || m.layout.isScroller {
            resize(c, geo, ResizeOpts(interact: interact))
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
