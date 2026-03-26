import KeyboardShortcuts
internal import AppKit

extension KeyboardShortcuts.Name {
    static let togglePopover = Self("togglePopover", default: .init(.b, modifiers: [.control, .option]))
}
