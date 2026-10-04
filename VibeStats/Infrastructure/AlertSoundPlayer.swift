//  AlertSoundPlayer.swift
//  Plays an alert sound in-process, for previewing a choice in Settings.
//
//  Notifications carry their sound through UNNotificationContent; this is only
//  for the settings preview, where waiting for the next real outage to hear
//  what you picked is not a reasonable review loop.

import AppKit
import Foundation

protocol AlertSoundPlaying: Sendable {
    func play(_ sound: AlertSound)
}

struct SystemAlertSoundPlayer: AlertSoundPlaying {
    func play(_ sound: AlertSound) {
        guard let name = sound.systemName else {
            // The system alert sound, whatever the user has chosen in Sound
            // settings — which is exactly what `.default` means in a banner.
            NSSound.beep()
            return
        }
        guard let sound = NSSound(named: name) else {
            Log.notify.error("no system sound named \(name)")
            NSSound.beep()
            return
        }
        sound.play()
    }
}
