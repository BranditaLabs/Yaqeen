// «الصلاة القادمة» home- and lock-screen widget (spec §5.28).
//
// Reads the snapshot the app writes on every re-plan (App Group `group.com.yaqinbrand.yaqeen`,
// key `yq.widget.v1`: a week of prayers, already localised and formatted with Western digits) and
// builds one timeline entry per upcoming prayer, so the countdown rolls over on its own. No network;
// nothing here leaves the device. Colours come from YqTokens (generated from tokens.json).
import SwiftUI
import WidgetKit

private let appGroup = "group.com.yaqinbrand.yaqeen"
private let snapshotKey = "yq.widget.v1"

struct WidgetPrayer: Decodable {
    let key: String
    let label: String
    let at: Double // epoch ms (UTC)
    let time: String

    var date: Date { Date(timeIntervalSince1970: at / 1000) }
}

struct WidgetWird: Decodable {
    let label: String
    let pages: Int
    let goal: Int
    let text: String
}

struct WidgetSnapshot: Decodable {
    let rtl: Bool
    let place: String
    let hijri: String?
    let nextLabel: String
    let prayers: [WidgetPrayer]
    let wird: WidgetWird?
    let ramadan: String?
    let staleText: String

    static func load() -> WidgetSnapshot? {
        guard let raw = UserDefaults(suiteName: appGroup)?.string(forKey: snapshotKey),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

struct PrayerEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let next: WidgetPrayer?
}

struct PrayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrayerEntry {
        PrayerEntry(date: Date(), snapshot: nil, next: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) {
        completion(entry(at: Date(), snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let now = Date()
        // Now, then the instant each upcoming prayer passes (the next one takes over).
        var entries = [entry(at: now, snapshot: snapshot)]
        for prayer in (snapshot?.prayers ?? []).filter({ $0.date > now }).prefix(12) {
            entries.append(entry(at: prayer.date.addingTimeInterval(1), snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date, snapshot: WidgetSnapshot?) -> PrayerEntry {
        PrayerEntry(date: date, snapshot: snapshot, next: snapshot?.prayers.first(where: { $0.date > date }))
    }
}

struct PrayerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PrayerEntry

    var body: some View {
        content
            .environment(\.layoutDirection, (entry.snapshot?.rtl ?? true) ? .rightToLeft : .leftToRight)
            .widgetURL(URL(string: "yaqeen://prayer"))
            .modifier(WidgetBackground())
    }

    /// Lock-screen families exist from iOS 16 only.
    private var isAccessory: Bool {
        if #available(iOSApplicationExtension 16.0, *) {
            return family == .accessoryRectangular || family == .accessoryInline || family == .accessoryCircular
        }
        return false
    }

    @ViewBuilder private var content: some View {
        if let next = entry.next, let s = entry.snapshot {
            if isAccessory {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(next.label) · \(next.time)").font(.headline)
                    Text(next.date, style: .timer).monospacedDigit()
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(s.nextLabel).font(.caption).foregroundColor(YqTokens.muted)
                        Spacer()
                        Image("WidgetMark").resizable().scaledToFit().frame(height: 14) // the mark from the artwork, never typeset
                    }
                    Text(next.label).font(.system(size: 26, weight: .bold)).foregroundColor(YqTokens.ink)
                    HStack(alignment: .firstTextBaseline) {
                        Text(next.time).font(.subheadline).foregroundColor(YqTokens.muted)
                        Spacer()
                        Text(next.date, style: .timer)
                            .font(.system(size: 20, weight: .light))
                            .monospacedDigit()
                            .foregroundColor(YqTokens.lapis)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    if let line = s.ramadan ?? s.hijri {
                        Text(family == .systemSmall ? line : "\(line) · \(s.place)")
                            .font(.caption2).foregroundColor(YqTokens.goldText).lineLimit(1)
                    }
                    if family != .systemSmall, let wird = s.wird, wird.goal > 0 {
                        Spacer(minLength: 2)
                        HStack {
                            Text(wird.label).font(.caption2).foregroundColor(YqTokens.ink)
                            Spacer()
                            Text(wird.text).font(.caption2).foregroundColor(YqTokens.muted)
                        }
                        ProgressView(value: Double(wird.pages), total: Double(wird.goal)).tint(YqTokens.gold)
                    }
                }
            }
        } else {
            Text(entry.snapshot?.staleText ?? "Open Yaqeen · افتح يقين")
                .font(.footnote).foregroundColor(YqTokens.muted).multilineTextAlignment(.center)
        }
    }
}

/// Porcelain glass on iOS 17's container background; a plain porcelain fill before.
struct WidgetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(for: .widget) {
                LinearGradient(colors: [YqTokens.white, YqTokens.porcelain], startPoint: .top, endPoint: .bottom)
            }
        } else {
            content.padding().background(LinearGradient(colors: [YqTokens.white, YqTokens.porcelain], startPoint: .top, endPoint: .bottom))
        }
    }
}

@main
struct YaqeenWidget: Widget {
    let kind = "YaqeenWidget"

    private var families: [WidgetFamily] {
        if #available(iOSApplicationExtension 16.0, *) {
            return [.systemSmall, .systemMedium, .accessoryRectangular]
        }
        return [.systemSmall, .systemMedium]
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrayerProvider()) { entry in
            PrayerWidgetView(entry: entry)
        }
        .configurationDisplayName("Yaqeen · يقين")
        .description("الصلاة القادمة مع عدّ تنازلي، وورد اليوم · Next prayer with a live countdown")
        .supportedFamilies(families)
    }
}
