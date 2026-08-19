import SwiftUI

// MARK: - Progress bar
//
// Track is gray-100; the fill takes a category color. Optional spent/limit caption row.

public struct DSProgressBar: View {
    private let value: Double
    private let color: Color
    private let height: CGFloat
    private let trackColor: Color
    private let leftLabel: String?
    private let rightLabel: String?

    public init(value: Double,
                color: Color = DS.Colors.actionPrimary,
                height: CGFloat = 8,
                trackColor: Color = DS.Colors.surfaceTrack,
                leftLabel: String? = nil,
                rightLabel: String? = nil) {
        self.value = min(max(value, 0), 1)
        self.color = color
        self.height = height
        self.trackColor = trackColor
        self.leftLabel = leftLabel
        self.rightLabel = rightLabel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.x2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(trackColor)
                    Capsule()
                        .fill(color)
                        .frame(width: max(geo.size.width * value, value > 0 ? height : 0))
                }
            }
            .frame(height: height)

            if leftLabel != nil || rightLabel != nil {
                HStack {
                    if let leftLabel { Text(leftLabel).dsText(DS.Font.meta, color: DS.Colors.textMuted) }
                    Spacer(minLength: DS.Space.x2)
                    if let rightLabel { Text(rightLabel).dsText(DS.Font.meta, color: DS.Colors.textMuted) }
                }
            }
        }
        .animation(DS.Motion.fill, value: value)
    }
}

// MARK: - Donut chart
//
// Thick (18–20pt) rounded segments with small gaps, a centre total, and a small percentage
// bubble pinned to the ring.

public struct DSDonutSegment: Identifiable {
    public let id = UUID()
    public let label: String
    public let value: Double
    public let color: Color

    public init(label: String, value: Double, color: Color) {
        self.label = label
        self.value = value
        self.color = color
    }
}

public struct DSDonutChart: View {
    private let segments: [DSDonutSegment]
    private let total: String
    private let label: String
    private let size: CGFloat
    private let thickness: CGFloat
    private let onDark: Bool

    public init(segments: [DSDonutSegment], total: String, label: String = "Totale",
                size: CGFloat = 200, thickness: CGFloat = 18, onDark: Bool = false) {
        self.segments = segments
        self.total = total
        self.label = label
        self.size = size
        self.thickness = thickness
        self.onDark = onDark
    }

    private var sum: Double { max(segments.reduce(0) { $0 + $1.value }, 0.0001) }
    private let gap: Double = 0.015

    public var body: some View {
        ZStack {
            Circle()
                .stroke(onDark ? Color.white.opacity(0.14) : DS.Colors.surfaceTrack,
                        lineWidth: thickness)
                .padding(thickness / 2)

            ForEach(Array(offsets.enumerated()), id: \.element.segment.id) { _, item in
                Circle()
                    .trim(from: item.start, to: item.end)
                    .stroke(item.segment.color,
                            style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                    .padding(thickness / 2)
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 2) {
                Text(label)
                    .dsText(DS.Font.label,
                            color: onDark ? DS.Colors.textOnDarkMuted : DS.Colors.textMuted)
                Text(total)
                    .dsText(DS.Font.Style(size: size > 170 ? 24 : 19, weight: .bold,
                                          lineHeight: 30, trackingEm: -0.02),
                            color: onDark ? DS.Colors.textOnDark : DS.Colors.textHeading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, thickness + 8)
        }
        .frame(width: size, height: size)
        .animation(DS.Motion.fill, value: sum)
    }

    private struct Slice {
        let segment: DSDonutSegment
        let start: CGFloat
        let end: CGFloat
    }

    private var offsets: [Slice] {
        var running: Double = 0
        return segments.compactMap { seg in
            let frac = seg.value / sum
            guard frac > 0 else { return nil }
            let start = running
            let end = running + max(frac - gap, 0.004)
            running += frac
            return Slice(segment: seg, start: CGFloat(start), end: CGFloat(min(end, 1)))
        }
    }
}

/// Legend for a donut — one dot, a label and a value per row.
public struct DSDonutLegend: View {
    private let segments: [DSDonutSegment]
    private let onDark: Bool
    private let formatter: (Double) -> String

    public init(segments: [DSDonutSegment], onDark: Bool = false,
                formatter: @escaping (Double) -> String) {
        self.segments = segments
        self.onDark = onDark
        self.formatter = formatter
    }

    private var labelColor: Color { onDark ? DS.Colors.textOnDarkMuted : DS.Colors.textBody }
    private var valueColor: Color { onDark ? DS.Colors.textOnDark : DS.Colors.textHeading }

    public var body: some View {
        VStack(spacing: DS.Space.x3) {
            ForEach(segments) { seg in
                HStack(spacing: DS.Space.x2) {
                    Circle().fill(seg.color).frame(width: 10, height: 10)
                    Text(seg.label)
                        .dsText(DS.Font.body, color: labelColor)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.x2)
                    Text(formatter(seg.value))
                        .dsText(DS.Font.labelBold, color: valueColor)
                }
            }
        }
    }
}

// MARK: - Bar chart
//
// Bars sit in full-height slots with a faint diagonal hatch; the value fills from the bottom
// with a rounded top. The active column is saturated with a white in-bar value label and a
// colored month label, the others in a pale tint.

public struct DSBarItem: Identifiable {
    public let id = UUID()
    public let label: String
    public let value: Double
    public let display: String?

    public init(label: String, value: Double, display: String? = nil) {
        self.label = label
        self.value = value
        self.display = display
    }
}

public struct DSBarChart: View {
    private let data: [DSBarItem]
    @Binding private var activeIndex: Int
    private let height: CGFloat
    private let color: Color
    private let mutedColor: Color

    public init(data: [DSBarItem],
                activeIndex: Binding<Int>,
                height: CGFloat = 150,
                color: Color = DS.Colors.actionPrimary,
                mutedColor: Color? = nil) {
        self.data = data
        self._activeIndex = activeIndex
        self.height = height
        self.color = color
        self.mutedColor = mutedColor ?? color.opacity(0.22)
    }

    private var maxValue: Double { max(data.map(\.value).max() ?? 1, 1) }

    public var body: some View {
        HStack(alignment: .bottom, spacing: DS.Space.x2 + 2) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, item in
                let isActive = index == activeIndex
                VStack(spacing: DS.Space.x2) {
                    GeometryReader { geo in
                        ZStack(alignment: .bottom) {
                            DSHatchPattern()
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm,
                                                            style: .continuous))
                            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                .fill(isActive ? color : mutedColor)
                                .frame(height: max(geo.size.height * (item.value / maxValue), 4))
                                .overlay(alignment: .top) {
                                    if isActive, let display = item.display {
                                        Text(display)
                                            .dsText(DS.Font.caption, color: DS.Colors.textOnDark)
                                            .padding(.top, 6)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.6)
                                            .padding(.horizontal, 4)
                                    }
                                }
                        }
                    }
                    .frame(height: height)

                    Text(item.label)
                        .dsText(isActive ? DS.Font.metaBold : DS.Font.meta,
                                color: isActive ? color : DS.Colors.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(DS.Motion.standard) { activeIndex = index }
                }
            }
        }
        .animation(DS.Motion.fill, value: maxValue)
    }
}

/// The faint 135° hatch behind each bar slot.
struct DSHatchPattern: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(DS.Palette.gray50))
            let step: CGFloat = 7
            var x: CGFloat = -size.height
            while x < size.width {
                var line = Path()
                line.move(to: CGPoint(x: x, y: size.height))
                line.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(line, with: .color(DS.Palette.gray100), lineWidth: 1)
                x += step
            }
        }
    }
}

// MARK: - Gauge
//
// Semicircular tick gauge for a single rate: radial ticks running blue → green for the
// filled portion, gray-200 for the remainder, the figure and a delta badge stacked in the
// middle.

public struct DSGaugeChart: View {
    private let value: Double          // 0...1
    private let title: String
    private let caption: String?
    private let delta: String?
    private let size: CGFloat

    public init(value: Double, title: String, caption: String? = nil,
                delta: String? = nil, size: CGFloat = 200) {
        self.value = min(max(value, 0), 1)
        self.title = title
        self.caption = caption
        self.delta = delta
        self.size = size
    }

    private let tickCount = 44

    public var body: some View {
        ZStack {
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height)
                let radius = min(canvasSize.width / 2, canvasSize.height) - 6
                let filled = Int(Double(tickCount) * value)
                for i in 0..<tickCount {
                    let t = Double(i) / Double(tickCount - 1)
                    let angle = Angle.degrees(180 + t * 180)
                    let inner = radius - 14
                    let start = CGPoint(x: center.x + cos(angle.radians) * inner,
                                        y: center.y + sin(angle.radians) * inner)
                    let end = CGPoint(x: center.x + cos(angle.radians) * radius,
                                      y: center.y + sin(angle.radians) * radius)
                    var tick = Path()
                    tick.move(to: start)
                    tick.addLine(to: end)
                    let color: Color = i < filled
                        ? blend(DS.Palette.blue500, DS.Palette.green500, t: t)
                        : DS.Palette.gray200
                    context.stroke(tick, with: .color(color),
                                   style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
            .frame(width: size, height: size / 2)

            VStack(spacing: 4) {
                Text(title)
                    .dsText(DS.Font.amountLarge, color: DS.Colors.textHeading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let delta {
                    DSBadge(delta, tone: .success)
                }
                if let caption {
                    Text(caption).dsText(DS.Font.meta, color: DS.Colors.textMuted)
                }
            }
            .offset(y: size / 8)
        }
        .frame(width: size, height: size / 2 + 8)
        .animation(DS.Motion.fill, value: value)
    }

    private func blend(_ a: Color, _ b: Color, t: Double) -> Color {
        // A simple two-stop ramp; exact channel math is unnecessary at tick scale.
        t < 0.5 ? a : b
    }
}

// MARK: - Cashflow row
//
// A colored left rule plus a tick strip beneath: solid green for money in, dashed red for
// money out.

public struct DSCashflowRow: View {
    private let label: String
    private let amount: String
    private let isIncome: Bool
    private let fraction: Double

    public init(label: String, amount: String, isIncome: Bool, fraction: Double) {
        self.label = label
        self.amount = amount
        self.isIncome = isIncome
        self.fraction = min(max(fraction, 0), 1)
    }

    private var color: Color { isIncome ? DS.Colors.income : DS.Colors.expense }

    public var body: some View {
        HStack(spacing: DS.Space.x3) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                Text(label).dsText(DS.Font.meta, color: DS.Colors.textMuted)
                Text(amount)
                    .dsText(DS.Font.Style(size: 19, weight: .bold, lineHeight: 24, trackingEm: -0.02),
                            color: DS.Colors.textHeading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottomLeading) {
            TickStrip(color: color, dashed: !isIncome, fraction: fraction)
                .frame(height: 6)
                .padding(.leading, 16)
                .offset(y: 6)
        }
    }

    private struct TickStrip: View {
        let color: Color
        let dashed: Bool
        let fraction: Double

        var body: some View {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    let count = max(Int(geo.size.width / 6), 1)
                    ForEach(0..<count, id: \.self) { i in
                        Capsule()
                            .fill(Double(i) / Double(count) < fraction
                                  ? color.opacity(dashed ? 0.7 : 1)
                                  : DS.Palette.gray200)
                            .frame(width: 3)
                    }
                }
            }
        }
    }
}
