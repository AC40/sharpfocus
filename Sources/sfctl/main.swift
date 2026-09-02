import Foundation

// Tiny control CLI for a running SharpFocus instance.
//
//   sfctl engine backdrop|capture|dim
//   sfctl mode focusedWindow|frontApp
//   sfctl grayscale 0..1
//   sfctl blur 0..40
//   sfctl dim 0..0.9
//   sfctl enabled 1|0
//   sfctl mc-pause 1|0

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else {
    print("usage: sfctl <key> <value>   (engine|mode|grayscale|blur|dim|enabled|mc-pause)")
    exit(64)
}

DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("de.beyond925.SharpFocus.command"),
    object: "\(arguments[0])=\(arguments[1])",
    userInfo: nil,
    deliverImmediately: true
)
// Give distnoted a moment to hand the message off before exiting.
usleep(100_000)
