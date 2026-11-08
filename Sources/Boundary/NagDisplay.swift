/// Not in mango: mangonag's Wayland side (mangonag/mangonag.c), the port's. mango runs mangonag
/// as its own Wayland client: a connection, its outputs, a layer surface drawn with cairo and
/// pango, a pointer and a loop. Here mangonag's code (Sources/Mango/mangonag) runs in mango's
/// process, and the port stands where that client's Wayland side stands: it places and draws the
/// bar, gives mangonag's handlers the pointer, and runs the loop (nag.running, -T, nag_destroy).
@MainActor
public protocol NagDisplay: AnyObject {
    /// mangonag nag_setup_surface (mangonag.c): the bar on `nag.outputName`'s output at
    /// `nag.edge`, nag_compute_layout's height, and drawn as nag_render draws it, each button's
    /// place in `nag.buttons`.
    func nagSetupSurface()
    /// mangonag nag_run_action (mangonag.c), its fork: the button's action run with sh, or in a
    /// terminal (`terminal`). A fork in mango's process may do no more than exec.
    func nagFork(_ button: NagButton)
    /// mangonag nag_destroy (mangonag.c), its Wayland part: the layer surface gone.
    func nagDestroySurface()
}
