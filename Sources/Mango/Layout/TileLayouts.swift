import Foundation
import CoreGraphics

package struct IRect: Equatable {
    var x: Int, y: Int, w: Int, h: Int
    init(_ x: Int, _ y: Int, _ w: Int, _ h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }
    init(_ r: CGRect) {
        x = Int(r.minX.rounded()); y = Int(r.minY.rounded())
        w = Int(r.width.rounded()); h = Int(r.height.rounded())
    }
    var cg: CGRect { CGRect(x: x, y: y, width: max(1, w), height: max(1, h)) }
    var transposed: IRect { IRect(y, x, h, w) }
}

package struct IGaps {
    var ih: Int, iv: Int, oh: Int, ov: Int
    init(_ g: Gaps) {
        ih = Int(g.ih.rounded()); iv = Int(g.iv.rounded())
        oh = Int(g.oh.rounded()); ov = Int(g.ov.rounded())
    }
    init(ih: Int, iv: Int, oh: Int, ov: Int) { self.ih = ih; self.iv = iv; self.oh = oh; self.ov = ov }
    var transposed: IGaps { IGaps(ih: iv, iv: ih, oh: ov, ov: oh) }
}

package enum LayoutSupport {
    /// Not in mango: assembles the layout result.
    static func finish(_ input: LayoutInput, _ frames: [ClientID: IRect], hidden: Set<ClientID> = [],
                       applyFullscreen: Bool = true) -> LayoutResult {
        var out: [ClientID: CGRect] = [:]
        let g = IGaps(input.gaps)
        let w = IRect(input.workArea)
        for c in input.clients {
            var r = frames[c.id] ?? IRect(w.x + g.oh, w.y + g.ov, w.w - 2 * g.oh, w.h - 2 * g.ov)
            if applyFullscreen {
                if c.isFullscreen {
                    r = IRect(input.monitorFrame)
                } else if c.isMaximized {
                    r = IRect(w.x + g.oh, w.y + g.ov, w.w - 2 * g.oh, w.h - 2 * g.ov)
                }
            }
            out[c.id] = r.cg
        }
        var hid = hidden.intersection(Set(input.clients.map(\.id)))
        if applyFullscreen {
            for c in input.clients where (c.isFullscreen || c.isMaximized) && c.id == input.focusedID {
                hid.remove(c.id)
            }
        }
        return LayoutResult(frames: out, hidden: hid)
    }

    /// Not in mango: x/y swap so vertical layouts reuse horizontal.
    static func transposed(_ input: LayoutInput) -> LayoutInput {
        var t = input
        t.workArea = CGRect(x: input.workArea.minY, y: input.workArea.minX,
                            width: input.workArea.height, height: input.workArea.width)
        t.monitorFrame = CGRect(x: input.monitorFrame.minY, y: input.monitorFrame.minX,
                                width: input.monitorFrame.height, height: input.monitorFrame.width)
        t.gaps = Gaps(ih: input.gaps.iv, iv: input.gaps.ih, oh: input.gaps.ov, ov: input.gaps.oh)
        t.clients = input.clients.map { c in
            var c = c
            c.currentFrame = CGRect(x: c.currentFrame.minY, y: c.currentFrame.minX,
                                    width: c.currentFrame.height, height: c.currentFrame.width)
            return c
        }
        t.cursor = CGPoint(x: input.cursor.y, y: input.cursor.x)
        return t
    }

/// mango stores
    static func f32(_ v: CGFloat) -> Double { Double(Float(v)) }

    /// Not in mango: picks the window shown in deck/monocle.
    static func visibleOne(_ candidates: [ClientID], focused: ClientID?) -> ClientID? {
        if let f = focused, candidates.contains(f) { return f }
        return candidates.first
    }
}

public enum TileLayouts {
    public static func tile(_ input: LayoutInput) -> LayoutResult {
        LayoutSupport.finish(input, tileCore(input, right: false))
    }

    public static func rightTile(_ input: LayoutInput) -> LayoutResult {
        LayoutSupport.finish(input, tileCore(input, right: true))
    }

    private static func tileCore(_ input: LayoutInput, right: Bool) -> [ClientID: IRect] {
        let n = input.clients.count
        guard n > 0 else { return [:] }
        let m = IRect(input.workArea), g = IGaps(input.smartGapped(n == 1))
        let nmasters = max(0, input.pertag.nmaster)
        let masterNum = min(n, nmasters)
        let stackNum = n - masterNum
        let mfact = LayoutSupport.f32(input.mfact)

        let mw: Int
        if n > nmasters {
            mw = nmasters > 0 ? Int(Double(m.w + g.ih) * mfact) : 0
        } else {
            mw = m.w - 2 * g.oh + g.ih
        }
        var my = g.ov, ty = g.ov
        var masterSurplus = m.h - 2 * g.ov - g.iv * (masterNum - 1)
        var masterRatio: Float = 1
        var slaveSurplus = m.h - 2 * g.ov - g.iv * (stackNum - 1)
        var slaveRatio: Float = 1

        var frames: [ClientID: IRect] = [:]
        for (i, c) in input.clients.enumerated() {
            let share = Double(i < nmasters ? c.masterInnerPer : c.stackInnerPer)
            if i < nmasters {
                let r = min(n, nmasters) - i
                var h: Int
                if share > 0 && masterRatio > 0 {
                    h = Int(Double(masterSurplus) * share / Double(masterRatio))
                    // not in mango: the last one takes the rest, as in mango's center_tile (a mango bug, docs/afvigelser.md §6).
                    if r == 1 { h = m.h - my - g.ov }
                    masterSurplus -= h; masterRatio = Float(Double(masterRatio) - share)
                } else {
                    h = (m.h - my - g.ov - g.iv * (r - 1)) / r
                }
                let x = right ? m.x + m.w - mw - g.oh + g.ih : m.x + g.oh
                frames[c.id] = IRect(x, m.y + my, mw - g.ih, h)
                my += h + g.iv
            } else {
                let r = n - i
                var h: Int
                if share > 0 && slaveRatio > 0 {
                    h = Int(Double(slaveSurplus) * share / Double(slaveRatio))
                    // not in mango: the last one takes the rest, as in mango's center_tile (a mango bug, docs/afvigelser.md §6).
                    if r == 1 { h = m.h - ty - g.ov }
                    slaveSurplus -= h; slaveRatio = Float(Double(slaveRatio) - share)
                } else {
                    h = (m.h - ty - g.ov - g.iv * (r - 1)) / r
                }
                let x = right ? m.x + g.oh : m.x + mw + g.oh
                frames[c.id] = IRect(x, m.y + ty, m.w - mw - 2 * g.oh, h)
                ty += h + g.iv
            }
        }
        return frames
    }

    public static func centerTile(_ input: LayoutInput) -> LayoutResult {
        let n = input.clients.count
        guard n > 0 else { return LayoutResult() }
        let m = IRect(input.workArea), g = IGaps(input.smartGapped(n == 1)), cfg = input.config
        let nmasters = max(0, input.pertag.nmaster)
        let masterNum = min(n, nmasters)
        let stackNum = n - masterNum
        let mfact = LayoutSupport.f32(input.mfact)

        var mw = m.w
        var mx = g.oh
        var my = g.ov
        var tw = mw

        let shouldOverspread = cfg.centerMasterOverspread && n <= nmasters

        var leftNum = 0, rightNum = 0
        for j in 0..<max(0, stackNum) {
            if (j % 2 == 1) != (n % 2 == 0) { rightNum += 1 } else { leftNum += 1 }
        }
        var masterSurplus = m.h - 2 * g.ov - g.iv * max(0, masterNum - 1)
        var masterRatio: Float = 1
        var leftSurplus = m.h - 2 * g.ov - g.iv * max(0, leftNum - 1)
        var leftRatio: Float = 1
        var rightSurplus = m.h - 2 * g.ov - g.iv * max(0, rightNum - 1)
        var rightRatio: Float = 1
        let singleStackSurplus = m.h - 2 * g.ov - g.iv * max(0, stackNum - 1)

        if n > nmasters || !shouldOverspread {
            mw = nmasters > 0 ? Int(Double(m.w - 2 * g.oh - g.ih) * mfact) : 0
            if n - nmasters > 1 {
                tw = (m.w - mw) / 2 - g.oh - g.ih
                mx = g.oh + tw + g.ih
            } else if n - nmasters == 1 {
                if cfg.centerWhenSingleStack {
                    tw = (m.w - mw) / 2 - g.oh - g.ih
                    mx = g.oh + tw + g.ih
                } else {
                    tw = m.w - mw - 2 * g.oh - g.ih
                    mx = g.oh
                }
            } else {
                tw = (m.w - mw) / 2 - g.oh - g.ih
                mx = g.oh + tw + g.ih
            }
        } else {
            mw = m.w - 2 * g.oh
            mx = g.oh
            tw = 0
        }

        var oty = g.ov, ety = g.ov
        var frames: [ClientID: IRect] = [:]
        for (i, c) in input.clients.enumerated() {
            let share = Double(i < nmasters ? c.masterInnerPer : c.stackInnerPer)
            if i < nmasters {
                let r = min(n, nmasters) - i
                var h: Int
                if share > 0 && masterRatio > 0 {
                    h = Int(Double(masterSurplus) * share / Double(masterRatio))
                    if r == 1 { h = m.h - my - g.ov }
                    masterSurplus -= h; masterRatio = Float(Double(masterRatio) - share)
                } else {
                    h = (m.h - my - g.ov - g.iv * (r - 1)) / r
                    if r == 1 { h = m.h - my - g.ov }
                }
                frames[c.id] = IRect(m.x + mx, m.y + my, mw, h)
                my += h + g.iv
            } else {
                let stackIndex = i - nmasters
                if n - nmasters == 1 {
                    let r = n - i
                    var h: Int
                    if share > 0 {
                        h = Int(Double(singleStackSurplus) * share)
                        if r == 1 { h = m.h - ety - g.ov }
                    } else {
                        h = (m.h - ety - g.ov - g.iv * (r - 1)) / r
                        if r == 1 { h = m.h - ety - g.ov }
                    }
                    frames[c.id] = IRect(m.x + mx + mw + g.ih, m.y + ety, tw, h)
                    ety += h + g.iv
                } else {
                    let r = (n - i + 1) / 2
                    if (stackIndex % 2 == 1) != (n % 2 == 0) {
                        var h: Int
                        if share > 0 && rightRatio > 0 {
                            h = Int(Double(rightSurplus) * share / Double(rightRatio))
                            if r == 1 { h = m.h - ety - g.ov }
                            rightSurplus -= h; rightRatio = Float(Double(rightRatio) - share)
                        } else {
                            h = (m.h - ety - g.ov - g.iv * (r - 1)) / r
                            if r == 1 { h = m.h - ety - g.ov }
                        }
                        frames[c.id] = IRect(m.x + mx + mw + g.ih, m.y + ety, tw, h)
                        ety += h + g.iv
                    } else {
                        var h: Int
                        if share > 0 && leftRatio > 0 {
                            h = Int(Double(leftSurplus) * share / Double(leftRatio))
                            if r == 1 { h = m.h - oty - g.ov }
                            leftSurplus -= h; leftRatio = Float(Double(leftRatio) - share)
                        } else {
                            h = (m.h - oty - g.ov - g.iv * (r - 1)) / r
                            if r == 1 { h = m.h - oty - g.ov }
                        }
                        frames[c.id] = IRect(m.x + g.oh, m.y + oty, tw, h)
                        oty += h + g.iv
                    }
                }
            }
        }
        return LayoutSupport.finish(input, frames)
    }

    public static func verticalTile(_ input: LayoutInput) -> LayoutResult {
        let n = input.clients.count
        guard n > 0 else { return LayoutResult() }
        let m = IRect(input.workArea), g = IGaps(input.smartGapped(n == 1))
        let nmasters = max(0, input.pertag.nmaster)
        let masterNum = min(n, nmasters)
        let stackNum = n - masterNum
        let mfact = LayoutSupport.f32(input.mfact)

        let mh: Int
        if n > nmasters {
            mh = nmasters > 0 ? Int(Double(m.h + g.iv) * mfact) : 0
        } else {
            mh = m.h - 2 * g.ov + g.iv
        }
        var mx = g.oh, tx = g.oh
        var masterSurplus = m.w - 2 * g.oh - g.ih * (masterNum - 1)
        var masterRatio: Float = 1
        var slaveSurplus = m.w - 2 * g.oh - g.ih * (stackNum - 1)
        var slaveRatio: Float = 1

        var frames: [ClientID: IRect] = [:]
        for (i, c) in input.clients.enumerated() {
            let share = Double(i < nmasters ? c.masterInnerPer : c.stackInnerPer)
            if i < nmasters {
                let r = min(n, nmasters) - i
                var w: Int
                if share > 0 && masterRatio > 0 {
                    w = Int(Double(masterSurplus) * share / Double(masterRatio))
                    // not in mango: the last one takes the rest, as in mango's center_tile (a mango bug, docs/afvigelser.md §6).
                    if r == 1 { w = m.w - mx - g.oh }
                    masterSurplus -= w; masterRatio = Float(Double(masterRatio) - share)
                } else {
                    w = (m.w - mx - g.ih - g.ih * (r - 1)) / r
                }
                frames[c.id] = IRect(m.x + mx, m.y + g.ov, w, mh - g.iv)
                mx += w + g.ih
            } else {
                let r = n - i
                var w: Int
                if share > 0 && slaveRatio > 0 {
                    w = Int(Double(slaveSurplus) * share / Double(slaveRatio))
                    // not in mango: the last one takes the rest, as in mango's center_tile (a mango bug, docs/afvigelser.md §6).
                    if r == 1 { w = m.w - tx - g.oh }
                    slaveSurplus -= w; slaveRatio = Float(Double(slaveRatio) - share)
                } else {
                    w = (m.w - tx - g.ih - g.ih * (r - 1)) / r
                }
                frames[c.id] = IRect(m.x + tx, m.y + mh + g.ov, w, m.h - mh - 2 * g.ov)
                tx += w + g.ih
            }
        }
        return LayoutSupport.finish(input, frames)
    }

/// mango deck (horizontal.c). Not in mango: `hidden` keeps the ones under the focused one out of the port's minimum-size solver.
    public static func deck(_ input: LayoutInput) -> LayoutResult {
        let n = input.clients.count
        guard n > 0 else { return LayoutResult() }
        let m = IRect(input.workArea), g = IGaps(input.smartGapped(n == 1, iv: false))
        let nmasters = max(0, input.pertag.nmaster)
        let mfact = Float(input.mfact)

        let mw: Int
        if n > nmasters {
            mw = nmasters > 0 ? Int(Double(Float(m.w - 2 * g.oh) * mfact).rounded()) : 0
        } else {
            mw = m.w - 2 * g.oh
        }
        var my = 0
        var frames: [ClientID: IRect] = [:]
        var stack: [ClientID] = []
        for (i, c) in input.clients.enumerated() {
            if i < nmasters {
                let h = (m.h - 2 * g.ov - my) / (min(n, nmasters) - i)
                frames[c.id] = IRect(m.x + g.oh, m.y + g.ov + my, mw, h)
                my += h
            } else {
                frames[c.id] = IRect(m.x + mw + g.oh + g.ih, m.y + g.ov,
                                     m.w - mw - 2 * g.oh - g.ih, m.h - 2 * g.ov)
                stack.append(c.id)
            }
        }
        let shown = LayoutSupport.visibleOne(stack, focused: input.focusedID)
        let hidden = Set(stack.filter { $0 != shown })
        return LayoutSupport.finish(input, frames, hidden: hidden)
    }

    public static func verticalDeck(_ input: LayoutInput) -> LayoutResult {
        let n = input.clients.count
        guard n > 0 else { return LayoutResult() }
        let m = IRect(input.workArea), g = IGaps(input.smartGapped(n == 1, ih: false))
        let nmasters = max(0, input.pertag.nmaster)
        let mfact = Float(input.mfact)

        let mh: Int
        if n > nmasters {
            mh = nmasters > 0 ? Int(Double(Float(m.h - 2 * g.ov) * mfact).rounded()) : 0
        } else {
            mh = m.h - 2 * g.ov
        }
        var mx = 0
        var frames: [ClientID: IRect] = [:]
        var stack: [ClientID] = []
        for (i, c) in input.clients.enumerated() {
            if i < nmasters {
                let w = (m.w - 2 * g.oh - mx) / (min(n, nmasters) - i)
                frames[c.id] = IRect(m.x + g.oh + mx, m.y + g.ov, w, mh)
                mx += w
            } else {
                frames[c.id] = IRect(m.x + g.oh, m.y + mh + g.ov + g.iv,
                                     m.w - 2 * g.oh, m.h - mh - 2 * g.ov - g.iv)
                stack.append(c.id)
            }
        }
        let shown = LayoutSupport.visibleOne(stack, focused: input.focusedID)
        let hidden = Set(stack.filter { $0 != shown })
        return LayoutSupport.finish(input, frames, hidden: hidden)
    }

/// mango monocle (horizontal.c). Not in mango: `hidden` keeps the ones under the focused one out of the port's minimum-size solver.
    public static func monocle(_ input: LayoutInput) -> LayoutResult {
        guard !input.clients.isEmpty else { return LayoutResult() }
        let m = IRect(input.workArea), g = IGaps(input.smartGapped(input.clients.count == 1, ih: false, iv: false))
        let oh = input.config.monocleNoGap ? 0 : g.oh
        let ov = input.config.monocleNoGap ? 0 : g.ov
        let box = IRect(m.x + oh, m.y + ov, m.w - 2 * oh, m.h - 2 * ov)
        var frames: [ClientID: IRect] = [:]
        for c in input.clients { frames[c.id] = box }
        let ids = input.clients.map(\.id)
        let shown = LayoutSupport.visibleOne(ids, focused: input.focusedID)
        return LayoutSupport.finish(input, frames, hidden: Set(ids.filter { $0 != shown }))
    }
}
