import CoreGraphics
import Foundation

package extension MangoServer {
    func workspaceOverviewHandleKey(_ sym: UInt32) -> Bool {
        if !workspaceOverviewIsActive() {
            return false
        }

        switch sym {
        case XKB_KEY_Escape:
            if !wsov.closing {
                wsovClose(wsov.targetTag, nil)
            }
            return true
        case XKB_KEY_Return, XKB_KEY_KP_Enter:
            if !wsov.closing {
                wsovClose(wsov.targetTag, nil)
            }
            return true
        case XKB_KEY_Left, XKB_KEY_h:
            if !wsov.closing {
                wsovSelectDirection(-1, 0)
            }
            return true
        case XKB_KEY_Right, XKB_KEY_l:
            if !wsov.closing {
                wsovSelectDirection(1, 0)
            }
            return true
        case XKB_KEY_Up, XKB_KEY_k:
            if !wsov.closing {
                wsovSelectDirection(0, -1)
            }
            return true
        case XKB_KEY_Down, XKB_KEY_j:
            if !wsov.closing {
                wsovSelectDirection(0, 1)
            }
            return true
        default:
            return false
        }
    }

    internal func wsovSloppyFocusAt(_ x: Double, _ y: Double) {
        guard config.sloppyfocus, !wsov.pressed, !wsov.closing, let m = wsov.mon else { return }

        let cell = wsovHitCellAt(x, y)
        guard let item = wsovItemAt(cell, x, y), !item.isSnapshot, wsovClientEligible(item.client),
              let focus = item.client else {
            return
        }

        let previous = m.sel
        if focus === previous && focus.isfocusing {
            return
        }

        clientFocus(focus, false)
        wsovRenderSelectionClients(previous, focus)
        wsovUpdateStyles()
        system.outputScheduleFrame(m)
    }

    func workspaceOverviewHandleMotion(_ x: Double, _ y: Double) {
        if !workspaceOverviewIsActive() || wsov.closing {
            return
        }

        if wsovSetTargetFromPoint(x, y) {
            wsovRefreshTargetSelection()
        }
        wsovSloppyFocusAt(x, y)

        if !wsov.pressed {
            return
        }
        guard let m = wsov.mon else { return }

        let dx = x - Double(wsov.dragStartX)
        let dy = y - Double(wsov.dragStartY)
        let dragThreshold = Double(config.workspaceOverviewDragThreshold)
        if !wsov.moved && dx * dx + dy * dy >= dragThreshold * dragThreshold {
            wsov.moved = true
            if !cursorHidden {
                system.setCursor("grabbing")
            }
            if wsov.hasDragClient {
                if let source = wsovCellForTag(wsov.sourceTag) {
                    var item: WsovItem?
                    for i in source.items where i.client === wsov.dragClient {
                        item = i
                        break
                    }
                    if let item {
                        _ = wsovCreateDragBuffer(item)
                        wsovBeginDragFloating(item.client)
                        let tags = wsovClientTags(item.client) |
                            wsovTagBit(wsov.sourceTag)
                        _ = wsovRefreshWorkspaceTags(tags)
                    }
                }
            }
        }

        if !wsov.moved {
            return
        }

        if let dragBuffer = wsov.dragBuffer {
            let sourceWidth = MANGO_MAX(1, wsov.dragSourceWidth)
            let sourceHeight = MANGO_MAX(1, wsov.dragSourceHeight)
            let windowHeight =
                MANGO_MAX(1, wsov.dragHeight - wsov.dragBarHeight)
            let grabX = lround(Double(wsov.dragGrabX) * Double(wsov.dragWidth) /
                Double(sourceWidth))
            let grabY = lround(Double(wsov.dragGrabY) * Double(windowHeight) /
                Double(sourceHeight))
            wsov.dragPreviewX = lround(x - m.m.minX) - grabX
            wsov.dragPreviewY =
                lround(y - m.m.minY) - wsov.dragBarHeight - grabY
            wsovPlaceBufferClipped(dragBuffer, nil, wsov.dragPreviewX,
                                   wsov.dragPreviewY, wsov.dragWidth,
                                   wsov.dragHeight)
        }
        wsovUpdateDragScroll(x, y)
        wsovUpdateDropIndicator(x, y)
        system.outputScheduleFrame(m)
    }

    /// mango workspace_overview_handle_button (input.c)
    // not in mango: the button is macOS's number (0 left, 1 right), the cursor the port's pointer
    func workspaceOverviewHandleButton(_ button: Int, _ pressed: Bool) -> Bool {
        if !workspaceOverviewIsActive() {
            return false
        }
        if wsov.closing {
            if !pressed {
                cursorMode = CurNormal
            }
            return true
        }
        guard let m = wsov.mon else { return true }
        let cursor = system.pointer

        if pressed {
            cursorMode = CurPressed
            let cell = wsovHitCellAt(cursor.x, cursor.y)
            let item = wsovItemAt(cell, cursor.x, cursor.y)

            if button == 1, let item, !item.isSnapshot, let client = item.client {
                pendingKillClient(client)
                return true
            }
            if button != 0 {
                return true
            }

            wsovHideDropIndicator()
            wsov.pressed = true
            wsov.moved = false
            wsov.dragScrollDirection = 0
            wsov.dragScrollFrameValid = false
            wsov.dragStartX = lround(cursor.x)
            wsov.dragStartY = lround(cursor.y)
            wsov.sourceTag = cell?.tag ?? 0
            wsov.targetTag = cell?.tag ?? 0
            wsov.dragReturnTag = wsov.targetTag
            wsovRefreshTargetSelection()
            wsov.hasDragClient = item != nil
            wsov.dragClient = item?.client
            if let item {
                let itemBox = wsovItemDisplayBox(cell, item)
                wsov.dragGrabX =
                    lround(cursor.x - m.m.minX - Double(itemBox.x))
                wsov.dragGrabY =
                    lround(cursor.y - m.m.minY - Double(itemBox.y))
            }
            wsovUpdateStyles()
            return true
        }

        if button != 0 {
            cursorMode = CurNormal
            return true
        }
        if wsov.moved && wsov.hasDragClient {
            wsovFinishDrop(cursor.x, cursor.y)
        } else {
            let cell = wsovHitCellAt(cursor.x, cursor.y)
            let tag = cell?.tag ?? wsov.sourceTag
            let item = wsovItemAt(cell, cursor.x, cursor.y)
            let focus = item?.client
            clientFocus(focus, true)
            wsovClose(tag, focus)
        }
        cursorMode = CurNormal
        return true
    }

    func workspaceOverviewHandleAxis(_ event: WlrPointerAxisEvent?) -> Bool {
        if !workspaceOverviewIsActive() {
            return false
        }
        guard !wsov.closing, let event else { return true }
        if wsov.layout != WORKSPACE_OVERVIEW_SCROLL {
            return true
        }
        if wsov.pressed && wsov.hasDragClient {
            return true
        }

        let notches = event.deltaDiscrete != 0 ? Double(event.deltaDiscrete) / 120.0
            : event.delta / 15.0
        if !notches.isFinite || abs(notches) < 0.001 {
            return true
        }

        var now = event.timeMsec
        if now == 0 {
            now = getNowInMs()
        }

        wsovApplyScrollWheel(notches, now)
        return true
    }
}
