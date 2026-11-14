import Foundation

/// Quoting for text that ends up on a shell line — command previews, Copy as bd Command.
public enum ShellQuoting {
    /// The value as one shell word, exactly. Single quotes, because inside double quotes the
    /// shell still expands `$(…)`, backticks, `$VAR` and `\` — and these values can come from a
    /// workspace database nobody here wrote.
    public static func quoted(_ argument: String) -> String {
        let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")
        if !argument.isEmpty, argument.allSatisfy(safe.contains) { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
