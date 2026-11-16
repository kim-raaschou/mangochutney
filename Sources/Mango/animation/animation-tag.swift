import CoreGraphics

package extension MangoServer {
    func setTaginAnimation(_ m: Monitor, _ c: Client) {
        if c.animation.running {
            c.animainitGeom.origin.x = c.animation.current.minX
            c.animainitGeom.origin.y = c.animation.current.minY
            return
        }

        if (c.isglobal || c.isunglobal)
            || (m.pertag.prevtag > 0 && c.tags & (1 << (m.pertag.prevtag - 1)) != 0   // not in mango: prevtag 0 is not shifted
                && m.pertag.curtag > 0 && c.tags & (1 << (m.pertag.curtag - 1)) != 0) {
            c.animation.tagouting = false
            c.animation.tagouted = false
            c.animation.tagining = false
            c.animation.action = .move
            return
        }

        guard let mon = c.mon else { return }   // not in mango: c->mon is always set here
        let goingForward = m.carouselAnimDir != 0 ? m.carouselAnimDir > 0 : m.pertag.curtag > m.pertag.prevtag
        let vertical = config.tagAnimationDirection == VERTICAL
        let cm = mon.m, mm = m.m

        if goingForward {
            c.animainitGeom.origin.x = vertical ? c.animation.current.minX
                : max(cm.minX + cm.width, c.geom.minX + cm.width)
            c.animainitGeom.origin.y = vertical ? max(cm.minY + cm.height, c.geom.minY + cm.height)
                : c.animation.current.minY
        } else {
            c.animainitGeom.origin.x = vertical ? c.animation.current.minX
                : min(mm.minX - c.geom.width, c.geom.minX - cm.width)
            c.animainitGeom.origin.y = vertical ? min(mm.minY - c.geom.height, c.geom.minY - cm.height)
                : c.animation.current.minY
        }
    }

    func setArrangeVisible(_ m: Monitor, _ c: Client, _ wantAnimation: Bool) {
        c.tagVisible = true

        let wasEnabled = c.platform.sceneNodeEnabled
        let inPlace = wasEnabled && !c.animation.running && c.animation.current == c.geom
        let tagSwitch = !inPlace && !c.animation.tagFromRule && wantAnimation && m.pertag.prevtag != 0
            && m.pertag.curtag != 0 && clientAnimationsEnabled(c)

        if !ISTILED(c) || (!c.isClipToHide || !(c.mon?.layout.isScroller ?? false)) {
            c.isClipToHide = false
            clientUpdateVisibility(c)
        }

        /* Scratchpad clients slide in from above the monitor when shown */
        if SCRATCHPAD_SHOWN(c) && c.scratchpadTagin {
            c.scratchpadTagin = false
            c.animation.tagFromRule = false
            c.animation.tagouted = false
            /* Reverse an in-flight hide instead of restarting from the top. */
            let reversing = c.animation.tagouting && c.animation.running
                && c.animation.current != c.animation.initial
            c.animation.tagouting = false
            if clientAnimationsEnabled(c) {
                c.animation.tagining = true
                c.animainitGeom = c.geom
                if reversing {
                    c.animainitGeom.origin.x = c.animation.current.minX
                    c.animainitGeom.origin.y = c.animation.current.minY
                } else {
                    c.animainitGeom.origin.y = (c.mon?.m.minY ?? 0) - c.geom.height
                }
            } else {
                c.animation.tagining = false
                c.animainitGeom.origin.x = c.animation.current.minX
                c.animainitGeom.origin.y = c.animation.current.minY
            }
            resize(c, c.geom, ResizeOpts(skipOvEnterAnim: true))
            return
        }

        /* Special workspace clients slide in from above the monitor */
        if c.tags & TAG0_MASK != 0 {
            c.animation.tagFromRule = false
            c.animation.tagouting = false
            c.animation.tagouted = false
            if wantAnimation && clientAnimationsEnabled(c) {
                c.animation.tagining = true
                c.animainitGeom = c.geom
                c.animainitGeom.origin.y = (c.mon?.m.minY ?? 0) - c.geom.height
            } else {
                c.animainitGeom.origin.x = c.animation.current.minX
                c.animainitGeom.origin.y = c.animation.current.minY
            }
            resize(c, c.geom, ResizeOpts(skipOvEnterAnim: true))
            return
        }

        if tagSwitch {
            c.animation.tagining = true
            setTaginAnimation(m, c)
        } else {
            c.animainitGeom.origin.x = c.animation.current.minX
            c.animainitGeom.origin.y = c.animation.current.minY
        }

        c.animation.tagFromRule = false
        c.animation.tagouting = false
        c.animation.tagouted = false
        resize(c, c.geom, ResizeOpts(skipOvEnterAnim: true))
    }

    func setTagoutAnimation(_ m: Monitor, _ c: Client) {
        if (c.isglobal || c.isunglobal)
            || (m.pertag.prevtag > 0 && c.tags & (1 << (m.pertag.prevtag - 1)) != 0   // not in mango: prevtag 0 is not shifted
                && m.pertag.curtag > 0 && c.tags & (1 << (m.pertag.curtag - 1)) != 0) {
            c.animation.tagouting = false
            c.animation.tagouted = false
            c.animation.tagining = false
            c.animation.action = .move
            return
        }

        guard let mon = c.mon else { return }   // not in mango: c->mon is always set here
        let goingForward = m.carouselAnimDir != 0 ? m.carouselAnimDir > 0 : m.pertag.curtag > m.pertag.prevtag
        let vertical = config.tagAnimationDirection == VERTICAL
        let cm = mon.m
        if goingForward {
            c.pending = c.geom
            c.pending.origin.x = vertical ? c.animation.current.minX
                : min(cm.minX - c.geom.width, c.geom.minX - cm.width)
            c.pending.origin.y = vertical ? min(cm.minY - c.geom.height, c.geom.minY - cm.height)
                : c.animation.current.minY

            resize(c, c.geom, ResizeOpts(interact: false))
        } else {
            c.pending = c.geom
            c.pending.origin.x = vertical ? c.animation.current.minX
                : max(cm.minX + cm.width, c.geom.minX + cm.width)
            c.pending.origin.y = vertical ? max(cm.minY + cm.height, c.geom.minY + cm.height)
                : c.animation.current.minY
            resize(c, c.geom, ResizeOpts(interact: false))
        }
    }

    func setArrangeHidden(_ m: Monitor, _ c: Client, _ wantAnimation: Bool) {
        c.tagVisible = false

        // not in mango: the overview's card tree (ov_card_tree) is the port's pictures

        /* Scratchpad windows slide up and out when hidden */
        if c.tags & TAG0_MASK == 0 && c.isInScratchpad && c.isminimized {
            if clientAnimationsEnabled(c) && !c.animation.tagouted {
                c.animation.tagouting = true
                c.animation.tagining = false
                c.pending = c.geom
                c.pending.origin.y = (c.mon?.m.minY ?? 0) - c.geom.height
                resize(c, c.geom, ResizeOpts(interact: false))
            } else {
                c.animation.running = false
                c.animation.tagouting = false
                c.animation.tagining = false
                clientUpdateVisibility(c)
                c.animainitGeom = c.geom
                c.current = c.geom
                c.pending = c.geom
                c.animation.current = c.geom
            }
            return
        }

        /* Special workspace windows should animate out or hide when special
         * workspace is not active */
        if c.tags & TAG0_MASK != 0 {
            if wantAnimation && !m.isoverview && clientAnimationsEnabled(c) && !c.animation.tagouted {
                c.animation.tagouting = true
                c.animation.tagining = false
                c.pending = c.geom
                c.pending.origin.y = (c.mon?.m.minY ?? 0) - c.geom.height
                resize(c, c.geom, ResizeOpts(interact: false))
            } else {
                c.animation.running = false
                c.animation.tagouting = false
                c.animation.tagining = false
                clientUpdateVisibility(c)
                c.animainitGeom = c.geom
                c.current = c.geom
                c.pending = c.geom
                c.animation.current = c.geom
            }
            return
        }

        if !c.isTabHidden && !c.animation.tagouted
            && m.pertag.prevtag != 0 && c.tags & (1 << (m.pertag.prevtag - 1)) != 0   // not in mango: prevtag 0 is not shifted
            && m.pertag.curtag != 0 && clientAnimationsEnabled(c) {
            c.animation.tagouting = true
            c.animation.tagining = false
            setTagoutAnimation(m, c)
        } else {
            c.animation.running = false
            c.animation.tagining = false
            c.animation.tagouting = false
            c.animation.tagouted = true
            clientUpdateVisibility(c)
            c.animainitGeom = c.geom
            c.current = c.geom
            c.pending = c.geom
            c.animation.current = c.geom
        }
    }
}
