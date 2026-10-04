//  RSSFeedAdapter.swift
//  Status pages that publish nothing but an RSS incident feed. Grok (xAI).
//
//  status.x.ai sits behind a Cloudflare rule that blocks every endpoint except
//  /feed.xml, so there is no component list and no page indicator to read —
//  only incidents, one item per incident per component, titled
//  "[Grok (Web)] Models outage". The bracketed name is matched against the
//  registry's exactMatches/patterns, and component health is INFERRED from the
//  absence of an open incident. Like Gemini, that is a weaker claim than a
//  Statuspage component state, so it carries `.derivedFromIncidents`.

import Foundation

struct RSSFeedAdapter: Sendable {
    let client: any StatusAPIClient

    func check(_ definition: ServiceDefinition, feedURL: URL, now: Date) async throws -> ServiceSnapshot {
        let data = try await client.data(from: feedURL)
        let items = try RSSFeed.parse(data)

        let parsed = items.map { item -> (incident: Incident, component: String, indicator: StatusIndicator) in
            let component = item.componentName.lowercased()
            let watched = definition.components.contains { Self.matches($0, component) }
            let indicator = Self.indicator(forOpenIncidentSeverity: item.severity)
            return (Self.normalize(item, indicator: indicator, affectsWatched: watched), component, indicator)
        }

        let pruned = IncidentPruner.prune(parsed.map(\.incident), now: now)
        let prunedIDs = Set(pruned.map(\.id))
        let open = parsed.filter { prunedIDs.contains($0.incident.id) && !$0.incident.isResolved }

        let components = definition.components.map { component -> ComponentState in
            let hits = open.filter { Self.matches(component, $0.component) }
            let indicator = hits.isEmpty
                ? StatusIndicator.operational
                : RollUp(hits.map(\.indicator)).indicator

            return ComponentState(
                id: component.id,
                label: component.label,
                isPrimary: component.isPrimary,
                matched: true,
                matchedName: component.label,
                rawStatus: indicator.rawValue,
                indicator: indicator,
                detail: hits.first?.incident.name,
                provenance: .derivedFromIncidents
            )
        }

        let rollUp = RollUp(components.map(\.indicator))

        return ServiceSnapshot(
            id: definition.id,
            name: definition.name,
            indicator: rollUp.indicator,
            pageIndicator: rollUp.indicator,
            componentsResolved: components.count,
            componentsWatched: components.count,
            unresolvedCount: rollUp.unresolved,
            components: components,
            incidents: pruned,
            affectedComponents: components.filter(\.isAffected).map(\.label),
            error: nil,
            checkedAt: now
        )
    }

    static func matches(_ component: ComponentDefinition, _ name: String) -> Bool {
        component.exactMatches.contains(name)
            || component.patterns.contains { ComponentMatcher.matches(pattern: $0, in: name) }
    }

    /// An OPEN incident is never "operational", whatever its severity says.
    /// Every item in the captured feed reads "Severity: available" — that is
    /// the component's state *after* resolution — and the vocabulary for a live
    /// incident has never been observed. So: trust a recognisable word, and
    /// otherwise floor at minor rather than let an open incident pass as fine.
    static func indicator(forOpenIncidentSeverity raw: String?) -> StatusIndicator {
        let key = (raw ?? "").lowercased()
        switch StatusIndicator(componentStatus: key) {
        case .minor:    return .minor
        case .major:    return .major
        case .critical: return .critical
        case .operational, .unknown:
            if key.contains("outage") || key.contains("unavailable") || key.contains("down") {
                return .major
            }
            return .minor
        }
    }

    private static func normalize(
        _ item: RSSFeed.Item, indicator: StatusIndicator, affectsWatched: Bool
    ) -> Incident {
        let impact: IncidentImpact = switch indicator {
        case .critical: .critical
        case .major:    .major
        default:        .minor
        }
        return Incident(
            id: item.guid,
            name: item.incidentName,
            status: item.isResolved ? "resolved" : (item.status ?? "investigating"),
            impact: impact,
            createdAt: item.published,
            resolvedAt: item.isResolved ? (item.resolvedAt ?? item.published) : nil,
            shortlink: item.link,
            affectedComponents: [item.componentName],
            affectsWatched: affectsWatched,
            updates: item.updates.prefix(2).map {
                IncidentUpdate(body: $0.body, createdAt: $0.date, status: $0.title)
            }
        )
    }
}

// MARK: - Wire format

enum RSSFeed {
    struct Update: Sendable, Hashable {
        let date: Date?
        let title: String
        let body: String
    }

    struct Item: Sendable, Hashable {
        let guid: String
        /// "Grok (Web)" from "[Grok (Web)] Models outage"; empty if unbracketed.
        let componentName: String
        let incidentName: String
        let link: URL?
        let published: Date?
        /// Lower-cased, e.g. "resolved", "investigating".
        let status: String?
        let severity: String?
        let resolvedAt: Date?
        let updates: [Update]

        var isResolved: Bool {
            guard let status else { return resolvedAt != nil }
            return status.contains("resolved") || status.contains("closed") || status.contains("completed")
        }
    }

    static func parse(_ data: Data) throws -> [Item] {
        let collector = Collector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        guard parser.parse() else {
            let reason = parser.parserError.map { String(describing: $0) } ?? "not XML"
            throw APIError.decoding("RSS: \(reason)".prefix(160).description)
        }
        return collector.raw.map(item(from:))
    }

    private static func item(from raw: Collector.RawItem) -> Item {
        let (component, name) = splitTitle(raw.title)
        let html = raw.description
        let status = firstMatch(#"Status:\s*([^<]+)"#, in: html)?.lowercased()
            // Fall back to the categories ("available", "resolved").
            ?? raw.categories.first { ["resolved", "investigating", "identified", "monitoring"].contains($0.lowercased()) }?.lowercased()
        let severity = firstMatch(#"Severity:\s*([^<]+)"#, in: html)
            ?? raw.categories.first { !["resolved", "investigating", "identified", "monitoring"].contains($0.lowercased()) }

        return Item(
            guid: raw.guid.isEmpty ? raw.link : raw.guid,
            componentName: component,
            incidentName: name,
            link: URL(string: raw.link),
            published: date(raw.pubDate),
            status: status,
            severity: severity,
            resolvedAt: firstMatch(#"Resolved:\s*([^<]+)"#, in: html).flatMap(date),
            updates: updates(in: html)
        )
    }

    static func splitTitle(_ title: String) -> (component: String, name: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") else {
            return ("", trimmed)
        }
        let component = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
        let name = trimmed[trimmed.index(after: close)...]
        return (component.trimmingCharacters(in: .whitespaces),
                name.trimmingCharacters(in: .whitespaces))
    }

    /// Each update is `<p><strong>DATE</strong></p><h3>TITLE</h3><p>BODY</p>`,
    /// newest first.
    private static func updates(in html: String) -> [Update] {
        let pattern = #"<strong>([^<]+)</strong>\s*</p>\s*<h3>([^<]*)</h3>\s*<p>([^<]*)</p>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            func group(_ index: Int) -> String {
                Range(match.range(at: index), in: html).map { String(html[$0]) } ?? ""
            }
            return Update(
                date: date(group(1)),
                title: group(2).trimmingCharacters(in: .whitespacesAndNewlines),
                body: group(3).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        let value = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// RFC 822, as RSS 2.0 requires: "Tue, 22 Sep 2026 01:02:42 GMT".
    static func date(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Accumulates <item> children. Text arrives in pieces, and the
    /// description arrives as CDATA, so both paths append to the same buffer.
    private final class Collector: NSObject, XMLParserDelegate {
        struct RawItem {
            var title = "", link = "", guid = "", pubDate = "", description = ""
            var categories: [String] = []
        }

        var raw: [RawItem] = []
        private var current: RawItem?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            if element == "item" { current = RawItem() }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, foundCDATA block: Data) {
            text += String(decoding: block, as: UTF8.self)
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                    qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch element {
            case "item":
                if let current { raw.append(current) }
                current = nil
            case "title":       current?.title = value
            case "link":        current?.link = value
            case "guid":        current?.guid = value
            case "pubDate":     current?.pubDate = value
            case "description": current?.description = value
            case "category":    current?.categories.append(value)
            default:            break
            }
            text = ""
        }
    }
}
