import CoreGraphics

/// mango's MangoJumpLabel (include/mango/draw/text-node.h) with its scene node.
/// The port draws it, as scenefx draws mango's; the core holds it where mango does, on the client.
@MainActor
package protocol MangoJumpLabel: AnyObject {
    /// scene->node.enabled
    var enabled: Bool { get }
    /// logical_width and logical_height: the label's size after mango_jump_label_node_update.
    var logicalWidth: CGFloat { get }
    var logicalHeight: CGFloat { get }
    /// wlr_scene_node_set_enabled
    func setEnabled(_ enabled: Bool)
    /// wlr_scene_node_set_position; not in mango: on the screen, as the port has no client scene tree
    func setPosition(_ x: CGFloat, _ y: CGFloat)
    /// wlr_scene_node_raise_to_top
    func raiseToTop()
    func update(_ text: String, _ scale: Double)
    func applyConfig(_ data: DecorateDrawData)
    func destroy()
}
