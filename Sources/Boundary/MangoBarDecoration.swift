import CoreGraphics

/// mango's MangoBarDecoration (include/mango/draw/text-node.h) with its scene node.
/// The port draws it, as scenefx draws mango's; the core holds it where mango does.
@MainActor
package protocol MangoBarDecoration: AnyObject {
    /// scene->node.enabled
    var enabled: Bool { get }
    /// last_text and last_scale: what mango_bar_decoration_update drew last.
    var lastText: String? { get }
    var lastScale: Double { get }
    /// wlr_scene_node_set_enabled
    func setEnabled(_ enabled: Bool)
    /// wlr_scene_node_set_position
    func setPosition(_ x: CGFloat, _ y: CGFloat)
    /// wlr_scene_node_raise_to_top
    func raiseToTop()
    func update(_ text: String, _ scale: Double)
    func setSize(_ width: CGFloat, _ height: CGFloat)
    func setFocus(_ focused: Bool)
    func setCenterSecondaryLine(_ center: Bool)
    func applyConfig(_ data: DecorateDrawData)
    func destroy()
}
