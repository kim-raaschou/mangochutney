import AppKit
import SwiftUI
import Mango

@MainActor
public final class LayoutPalette {
    public static let shared = LayoutPalette()
    private var panel: HotkeysPanel?
    private let model = LayoutPaletteModel()
    private var keyMonitor: Any?
    private weak var server: MangoServer?

    func toggle(_ server: MangoServer) {
        if panel?.isVisible == true { close() } else { show(server) }
    }

    public func show(_ server: MangoServer) {
        self.server = server
        model.look = HotkeysLook(config: server.config)
        model.width = CGFloat(server.config.chutneyLayoutPaletteWidth)
        model.circle = server.config.circleLayout
        model.editing = false
        model.grid = LayoutPaletteGrid(circle: model.circle, selecting: server.selectedMonitor?.layout ?? .tile)
        model.onChoose = { [weak self] in self?.choose($0) }
        model.onTick = { [weak self] in self?.tick($0) }
        if panel == nil {
            let p = HotkeysPanel(contentRect: NSRect(origin: .zero, size: model.size),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.level = .floating
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.onResign = { [weak self] in self?.close() }
            let glass = GlassBacking(material: .popover)
            let host = NSHostingView(rootView: LayoutPaletteView(model: model))
            host.translatesAutoresizingMaskIntoConstraints = false
            glass.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
                host.topAnchor.constraint(equalTo: glass.topAnchor),
                host.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            ])
            p.contentView = glass
            panel = p
        }
        panel?.appearance = model.look.macOS ? nil : NSAppearance(named: .darkAqua)
        (panel?.contentView as? GlassBacking)?.cornerRadius = model.look.cornerRadius
        place()
        server.holdNativeFocus = true
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self, self.panel?.isKeyWindow == true else { return e }
                return self.handle(e) ? nil : e
            }
        }
        panel?.makeKeyAndOrderFront(nil)
        if let p = panel { NativeFocus.focusOwn(windowID: CGWindowID(p.windowNumber)) }
        NSApp.activate()
        panel?.makeKeyAndOrderFront(nil)
    }

    private func place() {
        let size = model.size
        let id = server?.selectedMonitor?.screen.displayID
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            panel?.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                                   width: size.width, height: size.height), display: true)
        }
        panel?.invalidateShadow()
    }

    private func toggleEditing() {
        model.editing.toggle()
        model.grid = LayoutPaletteGrid(circle: model.editing ? [] : model.circle, selecting: model.grid.selected)
        place()
    }

    func tick(_ kind: LayoutKind) {
        guard let server, let names = CircleLayout.toggled(model.circle, kind) else { return }
        CircleLayout.set(names, server: server)
        model.circle = server.config.circleLayout
    }

    private func handle(_ e: NSEvent) -> Bool {
        switch e.keyCode {
        case 36, 76: choose(model.grid.selected)
        case 48: toggleEditing()
        case 49 where model.editing: tick(model.grid.selected)
        case 53: close()
        default:
            guard e.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let (dx, dy) = LayoutPaletteGrid.direction(keyCode: e.keyCode, characters: e.charactersIgnoringModifiers,
                                                             keys: server?.config.chutneyLayoutPaletteKeys ?? [])
            else { return true }
            model.grid.move(dx, dy)
        }
        return true
    }

    func choose(_ kind: LayoutKind) {
        close()
        server?.dispatch(Dispatch(name: "setlayout", args: [kind.name]))
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        guard panel?.isVisible == true else { return }
        panel?.orderOut(nil)
        guard let server else { return }
        server.holdNativeFocus = false
        if NSApp.keyWindow == nil, let c = server.focused { server.mac.focus(c, raise: true) }
    }
}

public struct LayoutPaletteGrid: Equatable {
    public static let all: [[LayoutKind?]] = [
        [.tile, .scroller, .grid, .deck, .fair],
        [.verticalTile, .verticalScroller, .verticalGrid, .verticalDeck, .verticalFair],
        [.monocle, .centerTile, .rightTile, .dwindle, nil],
    ]

    public static let columns = 5

    public let cells: [[LayoutKind?]]
    public private(set) var row = 0
    public private(set) var column = 0

    public init(circle: [String] = [], selecting kind: LayoutKind) {
        let kinds = CircleLayout.kinds(circle)
        let rows = (kinds.count + Self.columns - 1) / Self.columns
        let perRow = rows == 0 ? 0 : (kinds.count + rows - 1) / rows
        cells = kinds.isEmpty ? Self.all : stride(from: 0, to: kinds.count, by: perRow).map {
            Array(kinds[$0..<min($0 + perRow, kinds.count)])
        }
        for (r, cells) in cells.enumerated() {
            if let c = cells.firstIndex(of: kind) { row = r; column = c }
        }
    }

    public var selected: LayoutKind { cells[row][column]! }
    public var width: Int { cells.map(\.count).max() ?? 0 }

    public mutating func move(_ dx: Int, _ dy: Int) {
        let r = row + dy
        guard cells.indices.contains(r) else { return }
        func indent(_ r: Int) -> Double { Double(width - cells[r].count) / 2 }
        let c = dy == 0 ? column + dx
            : min(cells[r].count - 1, max(0, Int((Double(column) + indent(row) - indent(r)).rounded())))
        guard cells[r].indices.contains(c), cells[r][c] != nil else { return }
        row = r
        column = c
    }

    public static func direction(keyCode: UInt16, characters: String?, keys: [String]) -> (Int, Int)? {
        switch keyCode {
        case 123: return (-1, 0)
        case 125: return (0, 1)
        case 126: return (0, -1)
        case 124: return (1, 0)
        default: break
        }
        let steps = [(-1, 0), (0, 1), (0, -1), (1, 0)]
        guard let ch = characters?.lowercased(), ch.count == 1, let i = keys.firstIndex(of: ch), i < 4 else { return nil }
        return steps[i]
    }
}

@MainActor
final class LayoutPaletteModel: ObservableObject {
    @Published var grid = LayoutPaletteGrid(selecting: .tile)
    @Published var circle: [String] = []
    @Published var editing = false
    var onChoose: (LayoutKind) -> Void = { _ in }
    var onTick: (LayoutKind) -> Void = { _ in }
    @Published var look = HotkeysLook(macOS: false)
    @Published var width: CGFloat = 560

    var cell: CGSize {
        let w = (width - look.padding * 2) / CGFloat(LayoutPaletteGrid.columns)
        return CGSize(width: w, height: w * 0.8)
    }
    var footerHeight: CGFloat { 22 }
    var size: CGSize {
        CGSize(width: cell.width * CGFloat(max(grid.width, 2)) + look.padding * 2,
               height: cell.height * CGFloat(grid.cells.count) + footerHeight + look.padding * 2)
    }
}

struct LayoutPaletteView: View {
    @ObservedObject var model: LayoutPaletteModel

    var body: some View {
        let look = model.look
        VStack(spacing: 0) {
            ForEach(0..<model.grid.cells.count, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<model.grid.cells[r].count, id: \.self) { c in
                        cell(model.grid.cells[r][c], selected: model.grid.row == r && model.grid.column == c)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Text(model.editing ? "space  in or out of circle_layout     ⇥  done"
                               : "↩  set     ⇥  choose layouts")
                .font(look.font(10)).foregroundColor(look.dim)
                .frame(maxWidth: .infinity, minHeight: model.footerHeight, alignment: .bottom)
        }
        .padding(look.padding)
        .background(look.background)
        .overlay { if !look.macOS { Rectangle().stroke(look.frame, lineWidth: 1) } }
    }

    @ViewBuilder
    private func cell(_ kind: LayoutKind?, selected: Bool) -> some View {
        let look = model.look
        VStack(spacing: 6) {
            if let kind {
                LayoutIcon(kind: kind, selected: selected, tint: look.accent, size: CGSize(width: model.cell.width * 0.58, height: model.cell.width * 0.39))
                Text(kind.name).font(look.font(max(9, model.cell.width * 0.105))).foregroundColor(selected ? look.selectionText : look.text)
                    .lineLimit(1)
            }
        }
        .frame(width: model.cell.width - 6, height: model.cell.height - 6)
        .background { RoundedRectangle(cornerRadius: look.macOS ? 8 : 0).fill(selected ? look.selectionFill : .clear) }
        .overlay(alignment: .topTrailing) {
            if model.editing, let kind {
                let ticked = CircleLayout.contains(model.circle, kind)
                Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: max(11, model.cell.width * 0.11)))
                    .foregroundColor(selected ? look.selectionText : ticked ? look.accent : look.dim)
                    .padding(6)
                    .contentShape(Rectangle())
                    .onTapGesture { model.onTick(kind) }
            }
        }
        .frame(width: model.cell.width, height: model.cell.height)
        .contentShape(Rectangle())
        .onTapGesture { if let kind { model.onChoose(kind) } }
    }
}

public enum CircleLayout {
    public static func kinds(_ circle: [String]) -> [LayoutKind] {
        var kinds: [LayoutKind] = []
        for name in circle { if let k = LayoutKind(name: name), !kinds.contains(k) { kinds.append(k) } }
        return kinds
    }

    public static func contains(_ circle: [String], _ kind: LayoutKind) -> Bool {
        kinds(circle).isEmpty || kinds(circle).contains(kind)
    }

    public static func toggled(_ circle: [String], _ kind: LayoutKind) -> [String]? {
        var names = kinds(circle).isEmpty ? LayoutKind.allCases.map(\.name) : circle
        if contains(circle, kind) {
            guard kinds(names).count > 1 else { return nil }
            names.removeAll { $0 == kind.name }
        } else {
            names.append(kind.name)
        }
        return names
    }

    @MainActor
    public static func set(_ names: [String], server: MangoServer) {
        let value = names.joined(separator: ",")
        server.dispatch(Dispatch(name: "setoption", args: ["circle_layout", value]))
        if let url = MenuSave.url(server.config, configURL: server.configURL) { MenuSave.set("circle_layout", value, in: url) }
    }
}
