import AppKit
import UserNotifications

/// Alerting, layered.
///
/// Notifications alone are not enough: Focus modes silently swallow them, which is
/// fatal for a timer. So the sound is played directly by the app, never attached to
/// the notification, and the banner is best-effort on top.
final class Notifier {
    /// Held so a second alarm can cut the first one short rather than overlap it,
    /// and so anything that counts as "I heard you" can stop it early.
    private var sound: NSSound?

    /// Pending end of the current ring, cancelled whenever the sound is stopped.
    private var stopWork: DispatchWorkItem?

    /// `UNUserNotificationCenter.current()` traps in a bundle-less process
    /// (`swift run`), so notifications are only wired up when we have a bundle id.
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// `named` is the alarm tone and `ringFor` how long it keeps sounding; the
    /// caller reads both from preferences, keeping this type unaware of settings.
    func fire(tag: String?, duration: TimeInterval, sound named: String, ringFor seconds: TimeInterval) {
        playSound(named, ringFor: seconds)
        postNotification(tag: tag, duration: duration)
    }

    /// Stops a ringing alarm. Called when you deal with the timer — the point of
    /// a long ring is to reach you, not to outlast you once it has.
    func silence() {
        stopWork?.cancel()
        stopWork = nil
        sound?.stop()
        sound = nil
    }

    private func playSound(_ named: String, ringFor seconds: TimeInterval) {
        // Resolved per alarm, not once at init: the preference can change, and a
        // sound the user has since deleted must still leave us with a beep.
        guard let sound = NSSound(named: named) ?? NSSound(named: SoundCatalog.fallback) else {
            return NSSound.beep()
        }
        silence()

        // The system sounds are all a second or two long, which is a chime, not
        // an alarm. Looping one turns it into something that keeps going until
        // it has your attention — no bundled audio needed.
        sound.loops = seconds > 0
        self.sound = sound
        sound.play()

        guard seconds > 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.sound?.stop()
            self?.sound = nil
            self?.stopWork = nil
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
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
