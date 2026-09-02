#!/bin/bash
# Raycast Script Command — control Sharp Focus.
# Install: Raycast → Extensions → Script Commands → Add Directory → this folder.

# @raycast.schemaVersion 1
# @raycast.title Sharp Focus
# @raycast.mode silent
# @raycast.packageName Sharp Focus
# @raycast.icon 🔘
# @raycast.argument1 { "type": "dropdown", "placeholder": "Action", "data": [{"title": "Toggle", "value": "toggle"}, {"title": "Enable", "value": "enable"}, {"title": "Disable", "value": "disable"}, {"title": "Snooze 30 min", "value": "snooze"}, {"title": "Preset: Deep Work", "value": "preset:Deep Work"}, {"title": "Preset: Soft Focus", "value": "preset:Soft Focus"}, {"title": "Preset: Monochrome", "value": "preset:Monochrome"}] }

case "$1" in
  toggle)   open "sharpfocus://toggle" ;;
  enable)   open "sharpfocus://enable" ;;
  disable)  open "sharpfocus://disable" ;;
  snooze)   open "sharpfocus://snooze?minutes=30" ;;
  preset:*) name="${1#preset:}"; open "sharpfocus://preset?name=$(printf '%s' "$name" | sed 's/ /%20/g')" ;;
  *) echo "unknown action: $1"; exit 1 ;;
esac
