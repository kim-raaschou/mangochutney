@MainActor
public protocol NagDisplay: AnyObject {
    func nagSetupSurface()
    func nagFork(_ button: NagButton)
    func nagDestroySurface()
}
