import Foundation

/// Converts a constrained Markdown subset into sanitized HTML for the ticket/spec reader.
///
/// The renderer intentionally escapes raw input and only emits tags it owns. This keeps
/// WebKit useful for rich layout without treating remote ticket descriptions as trusted HTML.
struct MarkdownHTMLRenderer {
    func renderDocument(_ markdown: String, isDarkMode: Bool) -> String {
        renderDocument(markdown, colorScheme: isDarkMode ? "dark" : "light")
    }

    func renderDocument(_ markdown: String, colorScheme: String = "dark") -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root {
              color-scheme: \(colorScheme);
              --bg: transparent;
              --text: #e8ecf3;
              --muted: #a8afbc;
              --border: #3a4354;
              --surface: #1d2430;
              --code-bg: #111823;
              --accent: #8fb4ff;
              --keyword: #ff9ecb;
              --string: #b7f7c5;
              --comment: #7f8998;
              --number: #ffd58f;
            }
            @media (prefers-color-scheme: light) {
              :root {
                --text: #222631;
                --muted: #697182;
                --border: #d8deea;
                --surface: #f7f9fc;
                --code-bg: #f1f4f9;
                --accent: #315fd6;
                --keyword: #9d2365;
                --string: #14763f;
                --comment: #6d7584;
                --number: #9a5b00;
              }
            }
            body {
              margin: 0;
              background: var(--bg);
              color: var(--text);
              font: 14px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
              line-height: 1.58;
            }
            .markdown-body { padding: 0; }
            h1, h2, h3 { line-height: 1.25; margin: 1.15em 0 .45em; }
            h1 { font-size: 24px; }
            h2 { font-size: 20px; }
            h3 { font-size: 17px; }
            p { margin: .55em 0; }
            a { color: var(--accent); text-decoration: none; }
            a:hover { text-decoration: underline; }
            ul, ol { padding-left: 1.45rem; margin: .55em 0; }
            li { margin: .2em 0; }
            blockquote {
              margin: .8em 0;
              padding: .1em 0 .1em 1em;
              border-left: 3px solid var(--accent);
              color: var(--muted);
            }
            table {
              border-collapse: collapse;
              width: 100%;
              margin: .9em 0 1.1em;
              table-layout: auto;
              overflow: hidden;
              border-radius: 8px;
            }
            th, td {
              border: 1px solid var(--border);
              padding: 8px 10px;
              text-align: left;
              vertical-align: top;
            }
            th {
              background: var(--surface);
              font-weight: 700;
            }
            pre {
              position: relative;
              margin: .9em 0;
              padding: 14px 14px 14px;
              overflow-x: auto;
              border: 1px solid var(--border);
              border-radius: 8px;
              background: var(--code-bg);
            }
            pre::before {
              content: attr(data-language);
              display: block;
              margin-bottom: 8px;
              color: var(--muted);
              font: 11px ui-monospace, SFMono-Regular, Menlo, monospace;
              text-transform: uppercase;
              letter-spacing: .04em;
            }
            code {
              font: 13px ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
              white-space: pre;
            }
            :not(pre) > code {
              white-space: normal;
              padding: 1px 5px;
              border-radius: 5px;
              background: var(--code-bg);
            }
            .kw { color: var(--keyword); font-weight: 700; }
            .str { color: var(--string); }
            .com { color: var(--comment); font-style: italic; }
            .num { color: var(--number); }
            figure { margin: 1em 0; }
            img {
              max-width: 100%;
              height: auto;
              border-radius: 8px;
              border: 1px solid var(--border);
            }
            figcaption {
              margin-top: 6px;
              color: var(--muted);
              font-size: 12px;
            }
            .mermaid {
              margin: 1em 0;
              padding: 14px;
              border: 1px solid var(--border);
              border-radius: 8px;
              background: var(--surface);
            }
          </style>
          <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
          <script>
            function escapeHTML(value) {
              return value.replace(/[&<>]/g, function(ch) {
                return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[ch];
              });
            }
            function keywordPattern(language) {
              var sets = {
                swift: "actor|await|case|catch|class|enum|extension|false|final|for|func|guard|if|import|in|let|nil|private|public|return|static|struct|switch|throw|throws|true|try|var|while",
                java: "abstract|boolean|break|case|catch|class|else|enum|extends|final|for|if|implements|import|interface|new|null|private|protected|public|return|static|String|switch|throw|try|void|while",
                kotlin: "class|data|else|false|fun|if|import|interface|is|lateinit|null|object|override|private|return|sealed|true|val|var|when|while",
                javascript: "async|await|class|const|else|export|false|for|function|if|import|let|new|null|return|true|try|var|while",
                typescript: "async|await|class|const|else|export|false|for|function|if|import|interface|let|new|null|return|true|try|type|var|while",
                python: "and|as|class|def|elif|else|False|for|from|if|import|in|is|None|not|or|return|True|try|while|with",
                sql: "alter|and|by|create|delete|from|group|insert|join|limit|order|select|table|update|where",
                bash: "case|do|done|elif|else|esac|fi|for|function|if|in|then|while"
              };
              if (language === "js") language = "javascript";
              if (language === "ts") language = "typescript";
              if (language === "sh" || language === "zsh") language = "bash";
              return sets[language] || sets.javascript;
            }
            function colorize(code, language) {
              var html = escapeHTML(code);
              html = html.replace(/(\\/\\/.*|#.*)$/gm, '<span class="com">$1</span>');
              html = html.replace(/(&quot;[^&]*(?:&amp;quot;[^&]*)*&quot;|'[^']*')/g, '<span class="str">$1</span>');
              html = html.replace(/\\b(0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?)\\b/g, '<span class="num">$1</span>');
              var keywords = keywordPattern(language);
              html = html.replace(new RegExp("\\\\b(" + keywords + ")\\\\b", "g"), '<span class="kw">$1</span>');
              return html;
            }
            document.addEventListener("DOMContentLoaded", function() {
              document.querySelectorAll("pre code").forEach(function(node) {
                var language = (node.className || "").replace("language-", "").trim().toLowerCase();
                node.innerHTML = colorize(node.textContent, language);
              });
              if (window.mermaid) {
                mermaid.initialize({ startOnLoad: true, theme: "dark", securityLevel: "strict" });
              }
            });
          </script>
        </head>
        <body><main class="markdown-body">\(renderBody(markdown))</main></body>
        </html>
        """
    }

    func renderBody(_ markdown: String) -> String {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                var codeLines: [String] = []
                index += 1
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                result.append(renderCodeBlock(codeLines.joined(separator: "\n"), language: language))
            } else if isTableStart(at: index, in: lines) {
                let table = collectTable(startingAt: index, in: lines)
                result.append(renderTable(table.rows))
                index = table.nextIndex - 1
            } else if trimmed.hasPrefix("# ") {
                result.append("<h1>\(renderInline(String(trimmed.dropFirst(2))))</h1>")
            } else if trimmed.hasPrefix("## ") {
                result.append("<h2>\(renderInline(String(trimmed.dropFirst(3))))</h2>")
            } else if trimmed.hasPrefix("### ") {
                result.append("<h3>\(renderInline(String(trimmed.dropFirst(4))))</h3>")
            } else if trimmed.hasPrefix(">") {
                let quote = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                result.append("<blockquote>\(renderInline(quote))</blockquote>")
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let list = collectList(startingAt: index, in: lines)
                result.append("<ul>\(list.items.map { "<li>\(renderInline($0))</li>" }.joined())</ul>")
                index = list.nextIndex - 1
            } else if trimmed.isEmpty {
                result.append("")
            } else {
                result.append("<p>\(renderInline(line))</p>")
            }

            index += 1
        }

        return result.joined(separator: "\n")
    }

    private func renderCodeBlock(_ code: String, language rawLanguage: String) -> String {
        let language = rawLanguage.isEmpty ? "text" : rawLanguage.lowercased()
        if language == "mermaid" {
            return "<div class=\"mermaid\">\(escapeHTML(code))</div>"
        }

        return """
        <pre data-language="\(escapeAttribute(language))"><code class="language-\(escapeAttribute(language))">\(escapeHTML(code))</code></pre>
        """
    }

    private func renderTable(_ rows: [[String]]) -> String {
        guard let header = rows.first else { return "" }
        let bodyRows = rows.dropFirst()
        let head = "<thead><tr>\(header.map { "<th>\(renderInline($0))</th>" }.joined())</tr></thead>"
        let body = "<tbody>\(bodyRows.map { row in "<tr>\(row.map { "<td>\(renderInline($0))</td>" }.joined())</tr>" }.joined())</tbody>"
        return "<table>\(head)\(body)</table>"
    }

    private func renderInline(_ text: String) -> String {
        var output = escapeHTML(text)
        output = replaceMarkdownImages(in: output)
        output = replaceMarkdownLinks(in: output)
        output = replaceInlineCode(in: output)
        output = replaceDelimited(output, delimiter: "**", open: "<strong>", close: "</strong>")
        output = replaceDelimited(output, delimiter: "*", open: "<em>", close: "</em>")
        return output
    }

    private func replaceMarkdownImages(in html: String) -> String {
        replacePattern(#"!\[([^\]]*)\]\(([^)]+)\)"#, in: html) { match in
            let alt = String(match[1])
            let source = String(match[2])
            return """
            <figure><img src="\(escapeAttribute(source))" alt="\(escapeAttribute(alt))" loading="lazy"><figcaption>\(alt)</figcaption></figure>
            """
        }
    }

    private func replaceMarkdownLinks(in html: String) -> String {
        replacePattern(#"\[([^\]]+)\]\(([^)]+)\)"#, in: html) { match in
            "<a href=\"\(escapeAttribute(String(match[2])))\">\(String(match[1]))</a>"
        }
    }

    private func replaceInlineCode(in html: String) -> String {
        replacePattern(#"`([^`]+)`"#, in: html) { match in
            "<code>\(String(match[1]))</code>"
        }
    }

    private func replaceDelimited(_ input: String, delimiter: String, open: String, close: String) -> String {
        let parts = input.components(separatedBy: delimiter)
        guard parts.count > 2 else { return input }
        return parts.enumerated().map { index, part in
            index.isMultiple(of: 2) ? part : "\(open)\(part)\(close)"
        }.joined()
    }

    private func replacePattern(_ pattern: String, in input: String, transform: ([Substring]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
        var output = input
        for match in regex.matches(in: input, range: nsRange).reversed() {
            var captures: [Substring] = []
            for idx in 0..<match.numberOfRanges {
                guard let range = Range(match.range(at: idx), in: input) else { continue }
                captures.append(input[range])
            }
            guard let fullRange = Range(match.range(at: 0), in: output) else { continue }
            output.replaceSubrange(fullRange, with: transform(captures))
        }
        return output
    }

    private func highlight(_ escapedCode: String, language: String) -> String {
        let keywords: [String]
        switch language {
        case "swift":
            keywords = ["let", "var", "func", "struct", "class", "enum", "import", "return", "if", "else", "switch", "case", "for", "while", "guard", "try", "await"]
        case "java", "kotlin":
            keywords = ["class", "interface", "public", "private", "protected", "final", "return", "if", "else", "for", "while", "new", "null", "void", "int", "long", "String"]
        case "javascript", "js", "typescript", "ts":
            keywords = ["const", "let", "var", "function", "return", "if", "else", "for", "while", "class", "new", "await", "async", "import", "export"]
        case "sql":
            keywords = ["select", "from", "where", "join", "insert", "update", "delete", "group", "order", "by", "limit", "create", "table"]
        default:
            keywords = []
        }

        var output = escapedCode
        output = replacePattern(#"(&quot;.*?&quot;|'.*?')"#, in: output) { "<span class=\"str\">\($0[0])</span>" }
        output = replacePattern(#"(?m)(//.*)$"#, in: output) { "<span class=\"com\">\($0[1])</span>" }
        output = replacePattern(#"\b\d+\b"#, in: output) { "<span class=\"num\">\($0[0])</span>" }
        for keyword in keywords {
            output = replacePattern(#"\b\#(NSRegularExpression.escapedPattern(for: keyword))\b"#, in: output) {
                "<span class=\"kw\">\($0[0])</span>"
            }
        }
        return output
    }

    private func isTableStart(at index: Int, in lines: [String]) -> Bool {
        guard index + 1 < lines.count else { return false }
        return isPipeRow(lines[index]) && isTableSeparator(lines[index + 1])
    }

    private func collectTable(startingAt index: Int, in lines: [String]) -> (rows: [[String]], nextIndex: Int) {
        var rows = [splitPipeRow(lines[index])]
        var cursor = index + 2
        while cursor < lines.count, isPipeRow(lines[cursor]) {
            rows.append(splitPipeRow(lines[cursor]))
            cursor += 1
        }
        return (rows, cursor)
    }

    private func collectList(startingAt index: Int, in lines: [String]) -> (items: [String], nextIndex: Int) {
        var items: [String] = []
        var cursor = index
        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { break }
            items.append(String(trimmed.dropFirst(2)))
            cursor += 1
        }
        return (items, cursor)
    }

    private func isPipeRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.filter { $0 == "|" }.count >= 2
    }

    private func isTableSeparator(_ line: String) -> Bool {
        let cells = splitPipeRow(line)
        return !cells.isEmpty && cells.allSatisfy { cell in
            let normalized = cell.trimmingCharacters(in: .whitespaces)
            return normalized.count >= 3 && normalized.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private func splitPipeRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func escapeAttribute(_ value: String) -> String {
        escapeHTML(value).replacingOccurrences(of: "'", with: "&#39;")
    }
}
