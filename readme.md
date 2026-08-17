# OsumTimer

A menu bar timer for macOS that you drive by typing.

Every timer lives as its own item in the menu bar, counting down in plain sight. No Dock icon, no window to hunt for, no app to switch to — you type `25`, hit return, and the number is up there in the corner until it's done.

```
  ⌥ 24:07   #therapy 2:12   0:45   ●  Thu 9:41 PM
```

---

## Type it the way you'd say it

One field. It takes whatever you'd naturally write, and echoes back what it understood while you type.

| You type | You get |
| --- | --- |
| `25` | 25 minutes — a bare number is minutes, because that's what people mean |
| `45m` · `2h` · `30s` · `1.5h` | exactly that |
| `1h30m` | compounds work |
| `3 minutes` | so do words — `sec`, `min`, `mins`, `hr`, `hours`, `day` |
| `1:30` | 1 min 30 sec — right-anchored, like a stopwatch reads |
| `1:30:45` | 1 hr 30 min 45 sec |
| `@5pm` | until 5pm — and if it's already past, tomorrow at 5pm |
| `till 5pm` · `until 14:00` · `to 9:30am` | same thing, however you'd phrase it |
| `#deepwork 25` | a 25 minute timer tagged **deepwork** |

Tags go anywhere in the line and get stripped out of the timing. Turn on **Show label in menu bar** and a tagged timer reads `therapy 2:12` in the corner, so three running timers are three things you can tell apart at a glance.

Anything it can't make sense of says so under the field, before you commit to it.

## Alarms that actually reach you

A timer you sleep through is a timer that failed. So:

- **The sound is played by the app, not attached to the notification.** Focus modes silently swallow notification sounds — this one comes through anyway.
- **It rings, it doesn't chime.** Pick how long: once, 10 seconds, 30 seconds, or a full minute. Anything past "once" loops until the time is up.
- **It stops the moment you've noticed.** Clicking the item, clearing it, starting another timer — anything that shows you're aware silences it. It's there to reach you, not to outlast you.
- **The ringing item is singled out** in the menu bar, so with several timers at `0:00`, the one making the noise is obviously the one asking for you.
- Choose the tone from every sound on your Mac. Previews play as you browse the list, so you pick by ear.

Notifications are best-effort on top, marked time-sensitive so they survive most Focus setups.

## Several timers, all at once

Add as many as you want — each one gets its own menu bar item, and you can drag them into whatever order you like. Pause, resume, reset, or clear any of them independently. Clearing keeps the item; removing takes it away.

A finished timer sits at `0:00` and waits for you rather than quietly vanishing — an item that cleans up after itself leaves you wondering whether it ever ran at all.

## It remembers

- **Countdowns survive a relaunch.** State is stored as absolute end times, so a restored timer isn't approximately right — it's still simply correct, whether you quit for a second or rebooted an hour ago.
- **Recent timers come back as the words that made them.** `@5pm` reused tomorrow means 5pm tomorrow, not "however many hours that happened to be yesterday." Your last four are one click away.

## Out of the way

- **Menu bar only** — no Dock icon, no app switcher clutter, no main menu.
- **Opens at login** by default, so it's there before you think to want it.
- **Light, dark, or system**, independent of everything else you're running.
- Native SwiftUI and AppKit. No Electron, no frameworks, no network access — it never talks to anything.

---

## Install

Grab the `.dmg` from [Releases](../../releases) and drag OsumTimer to your Applications folder.

The build is ad-hoc signed rather than notarized, so the first launch needs a right-click → **Open** (or System Settings → Privacy & Security → *Open Anyway*). After that it opens normally.

> Launch it from `/Applications`. The login item registers whatever path the app is at when it first runs, so opening it once from `~/Downloads` and moving it later leaves a registration pointing at nothing.

## Build it yourself

Requires macOS 14+ and a Swift 5.9 toolchain (Xcode 15 or the Command Line Tools).

```sh
make package   # builds build/OsumTimer.app and a drag-and-drop .dmg
make run       # run it straight from source
make debug     # same, but restarts on every file change (needs fswatch)
make test      # unit tests
```

`make run` produces a bare executable rather than an `.app` bundle, so "Open at login" is greyed out there — it needs a real bundle for macOS to register. Everything else behaves identically.

