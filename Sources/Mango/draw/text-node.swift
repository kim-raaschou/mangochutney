// not in mango: the text nodes (pango and cairo buffers, scene nodes, the font cache, jump labels and
// bar decorations, their geometry, close buttons and colours) are the port's, behind MangoBarDecoration
// and MangoJumpLabel (Sources/Boundary)

package extension MangoServer {

    // not in mango: the config's fields over mango's defaults (set_value_default), the data that
    // mango_bar_decoration_apply_config and mango_jump_label_node_apply_config copy into the node
    func mangoBarDecorationApplyConfig(_ set: DecorateStyle, mango: DecorateStyle) -> DecorateStyle {
        set.filled(from: mango)
    }
}
