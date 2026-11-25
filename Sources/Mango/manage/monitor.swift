import CoreGraphics
import Foundation

/// not in mango: C's fixed per-tag arrays (PERTAG_SLOTS), indexed by mango's uint32_t tag.
public struct PertagSlots<Element>: Sequence {
    var a: [Element]
    init(_ value: @autoclosure () -> Element) { a = (0..<Int(PERTAG_SLOTS)).map { _ in value() } }
    public subscript(i: UInt32) -> Element {
        get { a[Int(i)] }
        set { a[Int(i)] = newValue }
    }
    public subscript(i: Int) -> Element {
        get { a[i] }
        set { a[i] = newValue }
    }
    public func makeIterator() -> IndexingIterator<[Element]> { a.makeIterator() }
}

public let tag_num_MAX: UInt32 = 31
public let PERTAG_SLOTS: UInt32 = tag_num_MAX + 1

@MainActor
public final class Pertag {
    public var curtag: UInt32 = 0, prevtag: UInt32 = 0
    public var nmasters = PertagSlots<Int32>(0)
    public var mfacts = PertagSlots<Float>(0)
    public var noHide = PertagSlots<Bool>(false)
    public var noRenderBorder = PertagSlots<Bool>(false)
    public var openAsFloating = PertagSlots<Bool>(false)
    public var scrollerDefaultProportion = PertagSlots<Float>(0)
    public var scrollerDefaultProportionSingle = PertagSlots<Float>(0)
    public var scrollerIgnoreProportionSingle = PertagSlots<Bool>(false)
    package var dwindleRoot = PertagSlots<DwindleNode?>(nil)
    public var configLtidxs = PertagSlots<LayoutKind>(.tile)
    public var ltidxs = PertagSlots<LayoutKind>(.tile)
    package var scrollerState = PertagSlots<TagScrollerState?>(nil)
    package var tabState = PertagSlots<TagTabState?>(nil)
    package var tagRatioState = PertagSlots<TagRatioState?>(nil)
}

@MainActor
public final class Monitor {
    public var screen: Screen   // not in mango: the port's output (wlr_output)
    public var m: CGRect      /* monitor area, layout-relative */
    public var w: CGRect      /* window area, layout-relative */
    public var seltags = 0
    public var tagset: [UInt32] = [1, 1]
    var frameSerial: UInt32 = 1
    package var lastResizeFrame: UInt32 = 0   // not in mango: package, for the port's fit (chutney_fit_layout)

    public var gappih: Int32 /* horizontal gap between windows */
    public var gappiv: Int32 /* vertical gap between windows */
    public var gappoh: Int32 /* horizontal outer gaps */
    public var gappov: Int32 /* vertical outer gaps */
    // special workspace gaps, per monitor
    public var specialGappih: Int32
    public var specialGappiv: Int32
    public var specialGappoh: Int32
    public var specialGappov: Int32
    public let pertag = Pertag()
    public var ovbkCurrentTagset: UInt32 = 0
    public var ovbkPrevTagset: UInt32 = 0
    public weak var sel: Client?   // not in mango: weak, a closed client's pointer is not kept
    public weak var prevsel: Client?
    public var isoverview = false
    public var isWsOverview = false
    public var workspaceOverviewScope: Int32 = ALL_WORKSPACE
    public var isJumpMode = false
    public var isInHotarea = false
    public var ovNormalMode = false /* Uses the normal grid layout when entering via the
                                       hot area. */
    public var ovTabLayout = false  /* Uses the centered tab layout when entering via
                                       overcircle. */
    public var specialEmptyView = false // user intentionally opened the empty special view
    public var visibleClients: Int32 = 0
    public var visibleTilingClients: Int32 = 0
    public var visibleScrollTilingClients: Int32 = 0
    public var visibleFakeTilingClients: Int32 = 0
    public var hideClients: UInt32 = 0
    package var titleMessageBar: MangoBarDecoration?
    public var carouselAnimDir = 0
    // not in mango: the cards, where client_tile_resize puts the clients in overview (the port's windows stay under its pictures)
    package var ovCards: [ClientID: CGRect] = [:]
    // not in mango: the port shows pictures of the windows (screen capture granted)
    package var ovThumbnails = false

    // not in mango: the layout of the tag in view, m->pertag->ltidxs[get_mon_curtag(m)]
    public var layout: LayoutKind { pertag.ltidxs[getMonCurtag(self)] }

    init(screen: Screen, config: Config) {
        self.screen = screen
        m = screen.frame
        w = screen.workArea
        gappih = Int32(config.gappih)
        gappiv = Int32(config.gappiv)
        gappoh = Int32(config.gappoh)
        gappov = Int32(config.gappov)
        specialGappih = Int32(config.specialGappih)
        specialGappiv = Int32(config.specialGappiv)
        specialGappoh = Int32(config.specialGappoh)
        specialGappov = Int32(config.specialGappov)
        pertag.curtag = 1
        pertag.prevtag = 1
        for i in 0...config.tagNum {
            pertag.nmasters[i] = Int32(config.defaultNmaster)
            pertag.mfacts[i] = config.defaultMfact
            pertag.ltidxs[i] = .tile
        }
    }
}

/// mango INSIDEMON (manage/monitor.h).
@MainActor func INSIDEMON(_ a: Client) -> Bool {
    guard let m = a.mon else { return false }
    let g = a.geom, mm = m.m
    return g.minX >= mm.minX && g.minY >= mm.minY && g.minX + g.width <= mm.minX + mm.width
        && g.minY + g.height <= mm.minY + mm.height
}

/// mango GEOMINSIDEMON (manage/monitor.h).
@MainActor func GEOMINSIDEMON(_ a: CGRect, _ m: Monitor) -> Bool {
    let mm = m.m
    return a.minX >= mm.minX && a.minY >= mm.minY && a.minX + a.width <= mm.minX + mm.width
        && a.minY + a.height <= mm.minY + mm.height
}

@MainActor public func isSpecialActive(_ m: Monitor?) -> Bool {
    guard let m else { return false }
    return !m.isoverview && (m.tagset[m.seltags] & TAG0_MASK) != 0
}

@MainActor public func getMonCurtag(_ m: Monitor?) -> UInt32 {
    guard let m else { return 0 }
    // special workspace uses slot 0; all-tags is an ordinary multi-tag view
    // and follows its first tag
    if isSpecialActive(m) { return 0 }
    return m.pertag.curtag != 0 ? m.pertag.curtag : 1
}

package extension MangoServer {
    // true if m still has a live (not minimized/destroyed) special window
    func specialHasClients(_ m: Monitor?) -> Bool {
        guard let m else { return false }
        for c in clients {
            if c.mon === m && !c.iskilling && !c.isminimized && (c.tags & TAG0_MASK) != 0 {
                return true
            }
        }
        return false
    }

    func getMonitorActiveTagset(_ m: Monitor?) -> UInt32 {
        guard let m else { return 0 }
        if isSpecialActive(m) {
            let prevSet = m.tagset[m.seltags ^ 1] & TAGMASK
            return prevSet != 0 ? prevSet : (m.pertag.prevtag != 0 ? (1 << (m.pertag.prevtag - 1)) : 1)
        }
        return m.tagset[m.seltags]
    }

    // not in mango: wlr_output_layout_adjacent_output and _farthest_output, from the selected monitor's position
    func monitorFromDirection(_ dir: Int32) -> Monitor? {
        guard let sm = selectedMonitor else { return nil }
        let ref = sm.m, p = ref.origin
        func inDirection(_ b: CGRect, _ dirs: [Int32]) -> Bool {
            dirs.contains { d in
                switch d {
                case LEFT: return b.maxX <= ref.minX
                case RIGHT: return b.minX >= ref.maxX
                case UP: return b.maxY <= ref.minY
                case DOWN: return b.minY >= ref.maxY
                default: return false
                }
            }
        }
        func distance(_ b: CGRect) -> CGFloat {
            let x = min(max(p.x, b.minX), b.maxX - 1), y = min(max(p.y, b.minY), b.maxY - 1)
            return (x - p.x) * (x - p.x) + (y - p.y) * (y - p.y)
        }
        let others = monitors.filter { $0 !== sm }
        if let next = others.filter({ inDirection($0.m, [dir]) }).min(by: { distance($0.m) < distance($1.m) }) {
            return next
        }
        let rest: [Int32] = [LEFT, RIGHT, UP, DOWN].filter { $0 != dir }
        var farthest: Monitor?, maxDistance: CGFloat = 0
        for o in others where inDirection(o.m, rest) {
            let d = distance(o.m)
            if d > maxDistance { maxDistance = d; farthest = o }
        }
        if let farthest { return farthest }
        return sm
    }

    func monitorFromCycle(_ dir: Int32) -> Monitor? {
        guard let sm = selectedMonitor, var i = monitors.firstIndex(where: { $0 === sm }) else { return nil }

        let nmons = monitors.count

        for _ in 0..<nmons {
            // not in mango: the wrap skips the list head, which mango reads as a monitor (a mango bug, docs/afvigelser.md §6)
            if dir == MON_NEXT {
                i = (i + 1) % nmons
            } else {
                i = (i - 1 + nmons) % nmons
            }
            let m = monitors[i]
            if m !== sm { return m }   // not in mango: no disabled outputs
        }
        return nil
    }

    func isScrollerLayout(_ m: Monitor) -> Bool {
        if m.pertag.ltidxs[getMonCurtag(m)] == .scroller { return true }

        if m.pertag.ltidxs[getMonCurtag(m)] == .verticalScroller { return true }

        return false
    }

    func isMonocleLayout(_ m: Monitor) -> Bool {
        if m.pertag.ltidxs[getMonCurtag(m)] == .monocle { return true }

        return false
    }

    func isCentertileLayout(_ m: Monitor) -> Bool {
        if m.pertag.ltidxs[getMonCurtag(m)] == .centerTile { return true }

        return false
    }

    func isOvercircleMode(_ m: Monitor?) -> Bool {
        guard let m else { return false }
        return m.isoverview && m.ovTabLayout && !m.isJumpMode && !m.ovNormalMode
    }

    // not in mango: special_sync_top_layer (macOS has no layer shell)

    // sync the special overlay dim layer to the monitor and view state
    func specialUpdateDim(_ m: Monitor?) {
        guard let m, drawsOverlays else { return }   // not in mango: drawsOverlays is the port's
        // not in mango: the port's dim rect, over the special windows
        system.showSpecialDim(on: m, alpha: isSpecialActive(m) ? config.specialDim : nil,
                              over: Set(clients.filter { $0.mon === m && $0.tags & TAG0_MASK != 0 && !$0.isminimized }.map(\.windowID)))
    }

    func getTagStatus(_ tag: UInt32, _ m: Monitor) -> UInt32 {
        var status: UInt32 = 0
        for c in clients {
            if c.mon === m && c.tags & (1 << (tag - 1)) & TAGMASK != 0 {
                if c.isurgent {
                    status = 2
                    break
                }
                status = 1
            }
        }
        return status
    }

    func getTagsFirstTagNum(_ sourceTags: UInt32) -> UInt32 {
        var i: UInt32 = 0, tag: UInt32 = 0

        if sourceTags == 0 { return 0 }

        if sourceTags & TAG0_MASK != 0 { return 0 }

        while tag & 1 == 0 && sourceTags != 0 && i < UInt32(config.tagNum) {
            tag = sourceTags >> i
            i += 1
        }

        if i == 1 {
            return 1
        } else if i >= UInt32(config.tagNum) {
            return UInt32(config.tagNum)
        } else {
            return i
        }
    }

    func monitorCopyTagLayout(_ target: Monitor, _ source: Monitor, _ tag: UInt32) {
        if tag >= PERTAG_SLOTS { return }

        let dst = target.pertag
        let src = source.pertag

        dst.nmasters[tag] = src.nmasters[tag]
        dst.mfacts[tag] = src.mfacts[tag]
        dst.noHide[tag] = src.noHide[tag]
        dst.noRenderBorder[tag] = src.noRenderBorder[tag]
        dst.openAsFloating[tag] = src.openAsFloating[tag]
        dst.scrollerDefaultProportion[tag] = src.scrollerDefaultProportion[tag]
        dst.scrollerDefaultProportionSingle[tag] = src.scrollerDefaultProportionSingle[tag]
        dst.scrollerIgnoreProportionSingle[tag] = src.scrollerIgnoreProportionSingle[tag]
        dst.ltidxs[tag] = src.ltidxs[tag]
        tagRatioStateCopy(target, tag, source, tag)

        /* Layout trees, scroller nodes, and tab chains are monitor-owned and
         * rebuilt on the target after the clients have moved. */
    }

    // Gets the tagmask of the first tag in tags.
    func getTagsFirstTag(_ sourceTags: UInt32) -> UInt32 {
        var i: UInt32 = 0, tag: UInt32 = 0

        if sourceTags == 0 {
            return isSpecialActive(selectedMonitor) ? TAG0_MASK
                : (selectedMonitor != nil
                    ? 1 << (selectedMonitor.pertag.curtag != 0 ? selectedMonitor.pertag.curtag - 1 : 0)
                    : 1)
        }

        if sourceTags & TAG0_MASK != 0 { return TAG0_MASK }

        while tag & 1 == 0 && sourceTags != 0 && i < UInt32(config.tagNum) {
            tag = sourceTags >> i
            i += 1
        }

        if i == 1 {
            return 1
        } else if i >= UInt32(config.tagNum) {
            return 1 << (UInt32(config.tagNum) - 1)
        } else {
            return 1 << (i - 1)
        }
    }

    // not in mango: wlr_output_layout_output_at over the monitors' boxes
    func monitorAtPoint(_ p: CGPoint) -> Monitor? {
        monitors.first { $0.m.contains(p) }
    }

    func getMonitorNearestTo(_ lx: Int32, _ ly: Int32) -> Monitor? {
        // not in mango: wlr_output_layout_closest_point and _output_at over the monitors' boxes
        var closestX = Double(lx), closestY = Double(ly), minDistance = Double.greatestFiniteMagnitude
        for m in monitors where !m.m.isEmpty {
            let box = m.m
            let x = Double(lx) < box.minX ? box.minX : (Double(lx) > box.maxX - 1 / 65536.0 ? box.maxX - 1 / 65536.0 : Double(lx))
            let y = Double(ly) < box.minY ? box.minY : (Double(ly) > box.maxY - 1 / 65536.0 ? box.maxY - 1 / 65536.0 : Double(ly))
            let distance = (x - Double(lx)) * (x - Double(lx)) + (y - Double(ly)) * (y - Double(ly))
            if distance < minDistance {
                minDistance = distance
                closestX = x
                closestY = y
            }
        }
        return monitorAtPoint(CGPoint(x: closestX, y: closestY))
    }

    func matchMonitorSpec(_ spec: String?, _ m: Monitor?) -> Bool {
        guard let spec, let m else { return false }

        // if the spec does not contain a colon, treat it as a match on the monitor
        // name
        if !spec.contains(":") {
            return regexMatch(spec, m.screen.name)
        }

        var nameRule: String?
        var makeRule: String?
        var modelRule: String?
        var serialRule: String?

        for token in spec.split(separator: "&") {
            if let colon = token.firstIndex(of: ":") {
                let key = token[..<colon]
                let value = String(token[token.index(after: colon)...])

                if key == "name" {
                    nameRule = value
                } else if key == "make" {
                    makeRule = value
                } else if key == "model" {
                    modelRule = value
                } else if key == "serial" {
                    serialRule = value
                }
            }
        }

        var match = true

        if let nameRule {
            if !regexMatch(nameRule, m.screen.name) {
                match = false
            }
        }
        if let makeRule {
            if m.screen.make == nil || makeRule != m.screen.make {
                match = false
            }
        }
        if let modelRule {
            if m.screen.model == nil || modelRule != m.screen.model {
                match = false
            }
        }
        if let serialRule {
            if m.screen.serial == nil || serialRule != m.screen.serial {
                match = false
            }
        }

        return match
    }

    // not in mango: the port reports a screen where wlroots reports a wlr_output; no modes, rules or scene to set up
    func handleNewOutput(_ screen: Screen) {
        let m = Monitor(screen: screen, config: config)

        // Adds it to the global monitor list.
        monitors.insert(m, at: 0)

        // Applies the tag rule.
        parseTagrule(m)

        specialUpdateDim(m)

        handleOutputLayoutChange()

        printstatus(.arrangge)
    }

    // not in mango: no iscleanuping, and no fade-out clients, layers, workspaces or scene to tear down
    func handleOutputDestroy(_ m: Monitor) {
        workspaceOverviewMonitorDestroy(m)

        monitors.removeAll { $0 === m }

        monitorClose(m)
        titleMessageBarFinish(m)

        cleanupMonitorScroller(m)   // not in mango: no cleanup_monitor_dwindle, ARC frees the trees
        cleanupMonitorTab(m)
        cleanupMonitorTagRatioStates(m)
    }

    func setSelectedMonitor(_ m: Monitor?) { selectedMonitor = m }

    func monitorClose(_ m: Monitor) {
        /* update selected_monitor if needed and
         * move closed monitor's clients to the focused one */
        let nmons = monitors.count

        if gestureDriveMon === m {
            gestureDriveActive = false
            gestureDriveMon = nil
        }

        if m.isoverview {
            // not in mango: the closed monitor's overview, not the selected one's (a mango bug, docs/afvigelser.md §6)
            let keep = selectedMonitor
            selectedMonitor = m
            toggleOverview(Arg())
            selectedMonitor = keep
        }

        if nmons == 0 {
            setSelectedMonitor(nil)
        } else if m === selectedMonitor {
            /* don't switch to disabled monitors */
            setSelectedMonitor(monitors.first)
        }

        for c in clients {
            if c.mon === m {
                if selectedMonitor == nil {
                    clientSetGroupMon(c, nil)
                } else {
                    clientSetGroupMon(c, selectedMonitor)
                }
                // record the oldmonname which is used to restore
                if c.oldmonname == nil {
                    clientUpdateOldmonnameRecord(c, m)
                }
            }
        }
        if let sm = selectedMonitor {
            clientFocus(clientFocusTop(sm), true)
            printstatus(.arrangge)
        }
    }

    func handleOutputLayoutChange() {
        /*
         * Called whenever the output layout changes: adding or removing a
         * monitor, changing an output's mode or position, etc. This is where
         * the change officially happens and we update geometry, window
         * positions, focus, and the stored configuration in wlroots'
         * output-manager implementation.
         */
        // not in mango: no disabled outputs, no background or lock rects; the port reports the screens it has

        for m in monitors {
            let oldx = m.m.minX
            let oldy = m.m.minY
            /* Get the effective monitor geometry to use for surfaces */
            m.m = m.screen.frame
            m.w = m.m
            let monPosOffsetx = m.m.minX - oldx
            let monPosOffsety = m.m.minY - oldy

            for c in clients {
                // floating window position auto adjust the change of monitor
                // position
                if c.isfloating && c.mon === m {
                    c.geom.origin.x += monPosOffsetx
                    c.geom.origin.y += monPosOffsety
                    c.floatGeom = c.geom
                    if VISIBLEON(c, m) { resize(c, c.geom, ResizeOpts(interact: true)) }
                }

                // restore window to old monitor
                // not in mango: oldmonname is the display's id, and every Client is mapped
                if let cm = c.mon, cm !== m, c.oldmonname == m.screen.displayID {
                    clientChangeMon(c, m)
                }
            }

            specialUpdateDim(m)

            /* Calculate the effective monitor geometry to use for clients */
            m.w = m.screen.workArea   // not in mango: arrange_layers, macOS's work area
            /* Don't move clients to the left output when plugging monitors */
            arrange(m, false, false)
            /* make sure fullscreen clients have the right size */
            if let c = clientFocusTop(m), c.isfullscreen {
                resize(c, m.m, ResizeOpts(interact: false))
            }

            if selectedMonitor == nil { setSelectedMonitor(m) }
        }

        if let sm = selectedMonitor {
            for c in clients {
                if c.mon == nil { c.mon = sm }
                if c.tags == 0 && !c.isInScratchpad {
                    c.tags = sm.tagset[sm.seltags]
                    setSizePer(sm, c)
                }
            }
            if started { clientFocus(clientFocusTop(sm), true) }   // not in mango: no focus before the port has its windows
        }

        for m in monitors {
            workspaceOverviewMonitorChanged(m)
        }

        // not in mango: no cursor image, output manager, xdg-output or XWayland to update
    }

    func handleOutputFrame(_ m: Monitor) {
        var needMoreFrames = false

        // not in mango: no session, wlr_output->enabled or allow_frame_scheduling; the port's monitors are
        // enabled and its frames scheduled

        m.frameSerial &+= 1

        // not in mango: no layers and no fade-out clients to draw (macOS draws them)

        for c in clients {
            needMoreFrames = clientDrawFrame(c) || needMoreFrames
        }
        if m.isWsOverview {
            workspaceOverviewPrepareOutputFrame(m)
        }

        // not in mango: no frame skipping while clients resize; the port commits nothing

        // not in mango: the port draws every client's border at once
        if bordersDirty {
            bordersDirty = false
            updateBorders()
        }

        // If more frames are needed, ensure the next frame is scheduled.
        if needMoreFrames {
            requestFreshAllMonitors()
        }
        // not in mango: wsov's frame listener on the output's frame (wsov_attach_frame_listener), after this one
        if wsov.frameActive && wsov.mon === m {
            wsovHandleFrame()
        }
    }

    func setgaps(_ oh: Int32, _ ov: Int32, _ ih: Int32, _ iv: Int32) {
        guard let sm = selectedMonitor else { return }
        if isSpecialActive(sm) {
            sm.specialGappoh = max(oh, 0)
            sm.specialGappov = max(ov, 0)
            sm.specialGappih = max(ih, 0)
            sm.specialGappiv = max(iv, 0)
        } else {
            sm.gappoh = max(oh, 0)
            sm.gappov = max(ov, 0)
            sm.gappih = max(ih, 0)
            sm.gappiv = max(iv, 0)
        }
        arrange(sm, false, false)
    }
}
