import Foundation

public struct Account: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var username: String
    public var iconSymbol: String

    public init(
        id: UUID = UUID(),
        name: String,
        username: String,
        iconSymbol: String = "icon-bug-ant-outline"
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.iconSymbol = iconSymbol
    }
}
