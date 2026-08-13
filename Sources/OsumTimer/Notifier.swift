import AppKit
import UserNotifications

/// Alerting, layered.
///
/// Notifications alone are not enough: Focus modes silently swallow them, which is
/// fatal for a timer. So the sound is played directly by the app, never attached to
/// the notification, and the banner is best-effort on top.
final class Notifier {
    /// Held so a second alarm can cut the first one short rather than overlap it.
    private var sound: NSSound?

    /// `UNUserNotificationCenter.current()` traps in a bundle-less process
    /// (`swift run`), so notifications are only wired up when we have a bundle id.
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// `named` is the alarm tone; the caller reads it from preferences, keeping
    /// this type unaware of settings.
    func fire(tag: String?, duration: TimeInterval, sound named: String) {
        playSound(named)
        postNotification(tag: tag, duration: duration)
    }

    private func playSound(_ named: String) {
        // Resolved per alarm, not once at init: the preference can change, and a
        // sound the user has since deleted must still leave us with a beep.
        guard let sound = NSSound(named: named) ?? NSSound(named: SoundCatalog.fallback) else {
            return NSSound.beep()
        }
        self.sound?.stop()
        self.sound = sound
        sound.play()
    }

    private func postNotification(tag: String?, duration: TimeInterval) {
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = tag.map { "#\($0)" } ?? "Time"
        content.body = "\(Parser.echo(for: duration)) is up."
        content.interruptionLevel = .timeSensitive  // survives most Focus setups
        content.sound = nil                         // we play it ourselves

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
