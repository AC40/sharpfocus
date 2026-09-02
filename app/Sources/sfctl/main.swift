import Foundation

// Control CLI for a running Sharp Focus instance.
//
//   sfctl enabled 1|0          sfctl toggle
//   sfctl grayscale 0..1       sfctl blur 0..40        sfctl dim 0..0.9
//   sfctl mode focusedWindow|frontApp
//   sfctl preset "Deep Work"   sfctl snooze <minutes>
//   sfctl mc-pause 1|0

let arguments = Array(CommandLine.arguments.dropFirst())
guard let key = arguments.first, !["-h", "--help", "help"].contains(key) else {
    print("""
    usage: sfctl <command> [value]
      enabled 1|0            master switch
      toggle                 flip the master switch
      grayscale 0..1         desaturation amount
      blur 0..40             blur radius in points
      dim 0..0.9             dimming amount
      mode focusedWindow|frontApp
      preset <name>          apply a preset (and enable)
      snooze <minutes>       turn off temporarily
      mc-pause 1|0           pause in Mission Control
      settings               open the settings window
    """)
    exit(arguments.isEmpty ? 64 : 0)
}

let value = arguments.dropFirst().joined(separator: " ")
let line = value.isEmpty ? key : "\(key)=\(value)"

DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("de.beyond925.SharpFocus.command"),
    object: line,
    userInfo: nil,
    deliverImmediately: true
)
// Give distnoted a moment to hand the message off before exiting.
usleep(100_000)
