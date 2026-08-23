//  SparklineView.swift
//  Seven days of history, one column per three-hour bucket, coloured by the
//  worst state seen in that bucket.
//
//  Flat and nearly invisible when healthy — which is the point. It exists to
//  answer "was it down at 2pm, or was it me?", a question the extension cannot
//  answer at all because it keeps nothing beyond the last snapshot.

import SwiftUI

struct SparklineView: View {
    let samples: [HistorySample]
    var bucketCount: Int = 56          // 7 days × 8 buckets/day
    var now: Date = .now

    private var buckets: [StatusIndicator?] {
        let span: TimeInterval = 7 * 86_400
        let bucketSpan = span / Double(bucketCount)
        let start = now.addingTimeInterval(-span)

        var result = [StatusIndicator?](repeating: nil, count: bucketCount)
        for sample in samples {
            let offset = sample.t.timeIntervalSince(start)
            guard offset >= 0 else { continue }
            let index = min(bucketCount - 1, Int(offset / bucketSpan))

            // Worst state seen in the bucket wins — a 20-minute outage inside a
            // healthy 3-hour window must not average away.
            if let existing = result[index] {
                let worse = (sample.indicator.severity ?? -1) > (existing.severity ?? -1)
                result[index] = worse ? sample.indicator : existing
            } else {
                result[index] = sample.indicator
            }
        }
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width / CGFloat(bucketCount)
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { _, indicator in
                    Rectangle()
                        .fill(fill(indicator))
                        .frame(width: max(1, width - 0.5), height: height(indicator, in: geometry.size.height))
                        .frame(height: geometry.size.height, alignment: .bottom)
                }
            }
        }
        .frame(height: 12)
        .accessibilityElement()
        .accessibilityLabel(summary)
    }

    private func fill(_ indicator: StatusIndicator?) -> Color {
        guard let indicator else { return Color.secondary.opacity(0.12) }
        return Color.status(indicator).opacity(indicator == .operational ? 0.45 : 0.95)
    }

    private func height(_ indicator: StatusIndicator?, in total: CGFloat) -> CGFloat {
        guard let indicator else { return 2 }
        return switch indicator {
        case .operational: total * 0.25
        case .unknown:     total * 0.35
        case .minor:       total * 0.55
        case .major:       total * 0.78
        case .critical:    total
        }
    }

    private var summary: String {
        let bad = buckets.compactMap { $0 }.count { $0 != .operational && $0 != .unknown }
        return bad == 0
            ? String(localized: "7-day history: no issues recorded")
            : String(localized: "7-day history: \(bad) periods with issues")
    }
}
