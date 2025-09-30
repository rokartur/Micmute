import Foundation
import SwiftUI
import AlinFoundation

enum GitHubReleaseConfiguration {
    static var owner: String? {
        let repoURL = AppInfo.repo
        let components = repoURL.pathComponents.filter { $0 != "/" }
        return components.first
    }

    static var repository: String? {
        let repoURL = AppInfo.repo
        let components = repoURL.pathComponents.filter { $0 != "/" }
        guard components.count >= 2 else { return nil }
        return components[1]
    }
}

extension Release {
    /// Returns a GitHub-flavoured markdown `AttributedString` for the release body.
    /// - Parameter overrideOwner: Optional owner that overrides the inferred one from `AppInfo`.
    /// - Parameter overrideRepository: Optional repo that overrides the inferred one from `AppInfo`.
    /// - Returns: An `AttributedString` styled using the system markdown parser with additional GitHub conveniences applied.
    func githubMarkdownBody(overrideOwner: String? = nil, overrideRepository: String? = nil) -> AttributedString? {
        let sanitizedBody = normalizedBody(body)
        guard !sanitizedBody.isEmpty else { return nil }

        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.allowsExtendedAttributes = true
        options.failurePolicy = .returnPartiallyParsedIfPossible

        guard var attributed = try? AttributedString(markdown: sanitizedBody, options: options) else {
            return nil
        }

        let owner = overrideOwner ?? GitHubReleaseConfiguration.owner
        let repository = overrideRepository ?? GitHubReleaseConfiguration.repository

        if let owner, let repository {
            addIssueLinks(to: &attributed, owner: owner, repository: repository)
        }

        addAutomaticLinks(to: &attributed)

        return attributed
    }

    private func normalizedBody(_ rawBody: String) -> String {
        let cleaned = rawBody
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "- [ ]", with: "- ☐")
            .replacingOccurrences(of: "- [x]", with: "- ☑︎")
            .replacingOccurrences(of: "- [X]", with: "- ☑︎")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return "" }

        return convertMarkdownLists(in: cleaned)
    }

    private func convertMarkdownLists(in body: String) -> String {
        let lines = body.components(separatedBy: "\n")

        let converted: [(text: String, isBullet: Bool)] = lines.map { line in
            guard let range = listMarker(in: line) else {
                return (line, false)
            }

            let indentation = String(line[..<range.lowerBound])
            let remainderStart = line[range.upperBound...]
            let trimmedRemainder = remainderStart.drop { $0.isWhitespace }
            let bulletLine = indentation + "• " + trimmedRemainder
            return (bulletLine, true)
        }

        guard let firstLine = converted.first else { return body }

        var result = firstLine.text
        for index in 1..<converted.count {
            let previous = converted[index - 1]
            result.append(previous.isBullet ? "  \n" : "\n")
            result.append(converted[index].text)
        }

        return result
    }

    private func listMarker(in line: String) -> Range<String.Index>? {
        guard let firstNonWhitespace = line.firstIndex(where: { !$0.isWhitespace }) else { return nil }

        let rest = line[firstNonWhitespace...]
        guard let marker = rest.first else { return nil }

        let unorderedMarkers: Set<Character> = ["-", "*", "+"]
        guard unorderedMarkers.contains(marker) else { return nil }

        let markerEnd = line.index(after: firstNonWhitespace)
        guard markerEnd < line.endIndex else { return nil }

        let nextCharacter = line[markerEnd]
        guard nextCharacter.isWhitespace else { return nil }

        return firstNonWhitespace..<markerEnd
    }

    private func addIssueLinks(to attributedString: inout AttributedString, owner: String, repository: String) {
        let plainText = String(attributedString.characters)
        guard !plainText.isEmpty else { return }

        let pattern = try? NSRegularExpression(pattern: "(?<!\\w)#(\\d+)")
        guard let regex = pattern else { return }

        let nsString = plainText as NSString
        let matches = regex.matches(in: plainText, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let numericRange = match.range(at: 1)
            let matchRange = match.range(at: 0)

            let precedingIndex = matchRange.location > 0 ? matchRange.location - 1 : NSNotFound
            if precedingIndex != NSNotFound {
                let precedingCharacter = nsString.substring(with: NSRange(location: precedingIndex, length: 1))
                // If the hashtag is part of an existing markdown link, skip it.
                if precedingCharacter == "]" { continue }
            }

            guard let scalarRange = Range(matchRange, in: plainText),
                  let attributedRange = Range(scalarRange, in: attributedString) else { continue }

            let issueNumber = nsString.substring(with: numericRange)
            guard let url = URL(string: "https://github.com/\(owner)/\(repository)/issues/\(issueNumber)") else { continue }

            attributedString[attributedRange].link = url
            attributedString[attributedRange].underlineStyle = .single
        }
    }

    private func addAutomaticLinks(to attributedString: inout AttributedString) {
        let plainText = String(attributedString.characters)
        guard !plainText.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }

        let nsString = plainText as NSString
        let matches = detector.matches(in: plainText, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard let url = match.url,
                  let swiftRange = Range(match.range, in: plainText),
                  let attributedRange = Range(swiftRange, in: attributedString) else { continue }

            attributedString[attributedRange].link = url
            attributedString[attributedRange].underlineStyle = .single
        }
    }
}
