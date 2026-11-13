import Foundation
import Mango
import UserNotifications

/// Port extension: not in mango. chutney_fit_layout=2: a macOS notification where the layout can be
/// fitted, its Fit button (or a click on it) runs the fit; where it cannot, one that says so, with no
/// button. macOS asks once to allow notifications.
@MainActor
public final class FitNotification: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = FitNotification()
    nonisolated static let id = "chutney_fit_layout"
    nonisolated static let fitAction = "fit"
    static let infoCategory = "chutney_fit_layout_no_room"

    weak var server: MangoServer?
    private var asked = false

    /// The app's start: clicks on a notification left from before reach this mango.
    public func install(_ server: MangoServer) {
        self.server = server
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let fit = UNNotificationAction(identifier: Self.fitAction, title: "Fit", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.id, actions: [fit], intentIdentifiers: []),
                                          UNNotificationCategory(identifier: Self.infoCategory, actions: [], intentIdentifiers: [])])
    }

    func post(_ server: MangoServer, title: String, body: String, fit: Bool) {
        if self.server == nil { install(server) }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = fit ? Self.id : Self.infoCategory
        let request = UNNotificationRequest(identifier: Self.id, content: content, trigger: nil)
        let add = {
            center.add(request) { error in
                if let error { wlrLog(.error, "chutney_fit_layout: the notification was not shown: \(error.localizedDescription)") }
            }
        }
        wlrLog(.debug, "chutney_fit_layout: notification \(title): \(body)")
        guard !asked else { return add() }
        asked = true
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted { return add() }
            wlrLog(.error, "chutney_fit_layout: macOS does not allow notifications from Mango Chutney (System Settings › Notifications)\(error.map { ": \($0.localizedDescription)" } ?? "")")
        }
    }

    func remove() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.id])
        center.removePendingNotificationRequests(withIdentifiers: [Self.id])
    }

    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                                   withCompletionHandler done: @escaping () -> Void) {
        let action = response.actionIdentifier
        let fit = response.notification.request.content.categoryIdentifier == Self.id
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if fit, action == Self.fitAction || action == UNNotificationDefaultActionIdentifier, let server = self.server {
                    FitLayout.fit(server)
                }
            }
            done()
        }
    }

    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                                   withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list])
    }
}
