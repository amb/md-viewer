import AppKit

/// Small lexical highlighter: one regex pass, native attributes, bounded grammar cache.
enum SyntaxHighlighter {
    enum Token {
        case comment, string, number, identifier, keyword, property, tag, type, added, removed
        var color: NSColor {
            switch self {
            case .comment: return CodeTheme.comment
            case .string, .added: return CodeTheme.string
            case .number: return CodeTheme.number
            case .keyword: return CodeTheme.keyword
            case .property, .tag: return CodeTheme.blue
            case .type: return CodeTheme.type
            case .removed: return CodeTheme.removed
            case .identifier: return CodeTheme.text
            }
        }
    }

    private final class Grammar: NSObject {
        let regex: NSRegularExpression
        let roles: [Token]
        let keywords: Set<String>
        let language: String

        init(_ language: String) {
            self.language = language
            let words: String
            switch language {
            case "swift": words = "actor any as associatedtype async await borrowing break case catch class consuming continue convenience copy default defer deinit didSet distributed do dynamic each else enum extension fallthrough false fileprivate final for func get guard if import in indirect infix init inout internal is isolated lazy let macro mutating nil nonisolated nonmutating open operator optional override package postfix precedencegroup prefix private protocol public repeat required rethrows return self Self sending set some static struct subscript super switch throws throw true try typealias unowned var weak where while willSet"
            case "python": words = "and as assert async await break case class continue def del elif else except False finally for from global if import in is lambda match None nonlocal not or pass raise return True try type while with yield"
            case "javascript": words = "abstract as async await break case catch class const continue debugger declare default delete do else enum export extends false finally for from function get if implements import in instanceof interface keyof let namespace new null of package private protected public readonly return satisfies set static super switch symbol this throw true try type typeof undefined var void while with yield"
            case "rust": words = "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while"
            case "c": words = "alignas alignof asm auto bool break case catch char class const constexpr consteval constinit continue decltype default delete do double else enum explicit export extern false final float for friend goto if inline int long mutable namespace new noexcept nullptr operator override private protected public register reinterpret_cast requires return short signed sizeof static static_assert static_cast struct switch template this thread_local throw true try typedef typename union unsigned using virtual void volatile wchar_t while"
            case "java": words = "abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for if implements import instanceof int interface long native new null package private protected public record return sealed short static strictfp super switch synchronized this throw throws transient true false try var void volatile while yield"
            case "csharp": words = "abstract as async await base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern false finally fixed float for foreach get goto if implicit in int interface internal is lock long namespace new null object operator out override params partial private protected public readonly record ref return sbyte sealed set short sizeof stackalloc static string struct switch this throw true try typeof uint ulong unchecked unsafe ushort using value var virtual void volatile while yield"
            case "go": words = "break case chan const continue default defer else fallthrough false for func go goto if import interface iota map nil package range return select struct switch true type var"
            case "shell": words = "case do done elif else esac export fi for function if in local readonly return select then time until while"
            case "ruby": words = "alias and begin break case class def defined do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield"
            case "sql": words = "add all alter and as asc between by case check column constraint create database default delete desc distinct drop else end exists false foreign from full group having in index inner insert into is join key left like limit not null offset on or order outer primary references right select set table then true union unique update values view when where with"
            case "json", "config": words = "true false null True False None yes no on off"
            default: words = ""
            }
            keywords = Set(words.split(separator: " ").map(String.init))
            var rules: [(Token, String)] = []
            if language == "diff" {
                rules = [(.tag, #"^(?:---|\+\+\+)[^\r\n]*"#), (.keyword, #"^@@[^\r\n]*"#),
                         (.added, #"^\+[^\r\n]*"#), (.removed, #"^-[^\r\n]*"#)]
            } else {
                let hashComments = ["python", "shell", "ruby", "config"].contains(language)
                if language == "html" { rules.append((.comment, #"<!--[\s\S]*?(?:-->|\z)"#)) }
                else if language == "sql" { rules.append((.comment, #"--[^\r\n]*|/\*[\s\S]*?(?:\*/|\z)"#)) }
                else if hashComments { rules.append((.comment, #"[#][^\r\n]*"#)) }
                else if language != "json" { rules.append((.comment, #"//[^\r\n]*|/\*[\s\S]*?(?:\*/|\z)"#)) }
                var strings = [#""(?:\\[\s\S]|[^"\\\r\n])*+""#, #"'(?:\\[^\r\n]|[^'\\\r\n])*+'"#]
                if language == "rust" { strings[1] = #"'(?:\\(?:u\{[\da-fA-F_]+\}|x[\da-fA-F]{2}|[^\r\n])|[^'\\\r\n])'"# }
                if language == "swift" || language == "python" {
                    strings.insert(#""""[\s\S]*?(?:"""|\z)|'''[\s\S]*?(?:'''|\z)"#, at: 0)
                }
                if language == "swift" { strings.insert(##"(?<raw>#+)"[\s\S]*?"\k<raw>"##, at: 0) }
                if language == "rust" { strings.insert(#"r(?<raw>[#]*)"[\s\S]*?"\k<raw>"#, at: 0) }
                if language == "javascript" || language == "shell" || language == "go" {
                    strings.insert(#"`(?:\\[\s\S]|[^`\\])*+`"#, at: 0)
                }
                rules.append((.string, strings.joined(separator: "|")))
                if language == "c" { rules.append((.keyword, #"[#]\s*(?:include|define|undef|if|ifdef|ifndef|elif|else|endif|pragma)\b"#)) }
                if language == "html" {
                    rules += [(.keyword, #"<![A-Za-z][^>]*>"#), (.tag, #"</?[\p{L}_][\w:.-]*|/?>"#),
                              (.property, #"[\w:.-]+(?=\s*=)"#)]
                } else {
                    if language == "css" { rules += [(.number, #"[#][\da-fA-F]{3,8}\b"#), (.keyword, #"@[\w-]+|!important\b"#)] }
                    if language == "shell" { rules.append((.property, #"\$(?:\{[^}\r\n]*\}|[\p{L}_]\w*|[\d?@#*!$-])"#)) }
                    rules += [(.number, #"\b(?:0[xX][\da-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)(?:[uUlLfF]+)?\b"#),
                              (.identifier, ["config", "css"].contains(language) ? #"[\p{L}_$][\p{L}\p{N}_$-]*"# : #"[\p{L}_$][\p{L}\p{N}_$]*"#)]
                }
            }
            roles = rules.map(\.0)
            // All patterns above are fixed source literals, never document-supplied regexes.
            regex = try! NSRegularExpression(pattern: rules.enumerated().map { "(?<t\($0.offset)>\($0.element.1))" }.joined(separator: "|"), options: .anchorsMatchLines)
            super.init()
        }
    }

    private static let aliases: [String: String] = [
        "swift": "swift", "py": "python", "python": "python", "python3": "python",
        "js": "javascript", "javascript": "javascript", "jsx": "javascript", "ts": "javascript", "typescript": "javascript", "tsx": "javascript",
        "rs": "rust", "rust": "rust", "c": "c", "h": "c", "cpp": "c", "c++": "c", "cxx": "c", "hpp": "c",
        "java": "java", "cs": "csharp", "c#": "csharp", "csharp": "csharp", "go": "go", "golang": "go",
        "sh": "shell", "bash": "shell", "zsh": "shell", "shell": "shell", "shellscript": "shell",
        "rb": "ruby", "ruby": "ruby", "sql": "sql", "json": "json", "jsonc": "javascript",
        "yaml": "config", "yml": "config", "toml": "config", "ini": "config",
        "html": "html", "xml": "html", "svg": "html", "css": "css", "diff": "diff", "patch": "diff"
    ]
    private static let cache: NSCache<NSString, Grammar> = {
        let cache = NSCache<NSString, Grammar>()
        cache.countLimit = 16
        return cache
    }()

    static func highlight(_ code: String, language: String?, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: code, attributes: attributes)
        let label = language?.split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
        guard let language = aliases[label], result.length <= 200_000 else { return result }
        let grammar = cache.object(forKey: language as NSString) ?? Grammar(language)
        cache.setObject(grammar, forKey: language as NSString)
        let source = code as NSString
        grammar.regex.enumerateMatches(in: code, range: NSRange(location: 0, length: source.length)) { match, _, _ in
            guard let match else { return }
            for (index, role) in grammar.roles.enumerated() {
                let range = match.range(withName: "t\(index)")
                guard range.location != NSNotFound else { continue }
                var token = role
                var next = NSMaxRange(range)
                while next < source.length, source.character(at: next) == 32 || source.character(at: next) == 9 { next += 1 }
                let following = next < source.length ? source.character(at: next) : 0
                if role == .identifier {
                    let word = source.substring(with: range)
                    if grammar.keywords.contains(language == "sql" ? word.lowercased() : word) { token = .keyword }
                    else if ["config", "css"].contains(language), following == 58 || following == 61 { token = .property }
                    else if following == 40 { token = .tag }
                    else if word.first?.isUppercase == true { token = .type }
                    else { break }
                } else if role == .string, language == "json", following == 58 { token = .property }
                result.addAttribute(.foregroundColor, value: token.color, range: range)
                break
            }
        }
        return result
    }
}
