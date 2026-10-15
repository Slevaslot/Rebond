import Foundation

extension String {
    /// A localized string with its automatic grammar agreement applied: "^[2 exercice](inflect: true)" gives
    /// "2 exercices". `String(localized:)` keeps the markup as is, and `Text` only applies it to a literal key:
    /// use this wherever the text is built as a `String` first.
    static func inflected(_ resource: LocalizedStringResource) -> String {
        String(AttributedString(localized: resource).characters)
    }
}
