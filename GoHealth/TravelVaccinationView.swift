import SwiftUI

enum TravelVaccinationRegion: String, CaseIterable, Identifiable {
    case northAmerica, southAmerica, europe, africa, asia, oceania

    struct Topic: Identifiable {
        let icon: String
        let title: String
        let detail: String

        var id: String { title }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .northAmerica: "Nordamerika"
        case .southAmerica: "Sydamerika"
        case .europe: "Europa"
        case .africa: "Afrika"
        case .asia: "Asien"
        case .oceania: "Oceanien"
        }
    }

    var color: Color {
        switch self {
        case .northAmerica: Color(red: 1.00, green: 0.73, blue: 0.41)
        case .southAmerica: Color(red: 1.00, green: 0.53, blue: 0.53)
        case .europe: Color(red: 0.57, green: 0.72, blue: 1.00)
        case .africa: Color(red: 1.00, green: 0.89, blue: 0.48)
        case .asia: Color(red: 0.98, green: 0.57, blue: 0.77)
        case .oceania: Color(red: 0.46, green: 0.89, blue: 0.75)
        }
    }

    var topics: [Topic] {
        switch self {
        case .northAmerica:
            [
                Topic(icon: "shield", title: "Grundskydd", detail: "Se över ditt skydd mot bland annat mässling före resan."),
                Topic(icon: "drop", title: "Hepatit A", detail: "Kontrollera behovet om du ska till Mexiko, Centralamerika eller Karibien. Resmålet avgör."),
                Topic(icon: "ant", title: "Myggskydd", detail: "Kontrollera risken för dengue och malaria för din resrutt i Mexiko, Centralamerika och Karibien.")
            ]
        case .southAmerica:
            [
                Topic(icon: "doc.text", title: "Gula febern och intyg", detail: "Vaccin kan behövas i vissa områden, bland annat i delar av Amazonas. Kontrollera även intygskraven vid inresa och mellanlandningar."),
                Topic(icon: "ant", title: "Myggskydd och malaria", detail: "Skydda dig mot myggstick där dengue eller malaria förekommer. Fråga om förebyggande malarialäkemedel för din rutt."),
                Topic(icon: "drop", title: "Hepatit A", detail: "Se över ditt skydd mot hepatit A inför resan.")
            ]
        case .europe:
            [
                Topic(icon: "shield", title: "Grundskydd", detail: "Se över skyddet mot mässling, stelkramp och difteri."),
                Topic(icon: "leaf", title: "TBE vid vistelse i naturen", detail: "Kontrollera om du ska vistas i ett riskområde, till exempel i delar av Central- och Östeuropa eller runt Östersjön."),
                Topic(icon: "drop", title: "Hepatit A", detail: "Fråga om hepatit A kan vara aktuellt för ditt resmål i södra eller sydöstra Europa.")
            ]
        case .africa:
            [
                Topic(icon: "ant", title: "Malaria och myggskydd", detail: "Kontrollera malariarisken för varje del av resan. En vaccinationsmottagning kan bedöma behovet av förebyggande läkemedel."),
                Topic(icon: "doc.text", title: "Gula febern och intyg", detail: "Vaccin kan behövas i delar av Afrika söder om Sahara. Kontrollera intygskraven för din resrutt, inklusive mellanlandningar."),
                Topic(icon: "drop", title: "Hepatit A", detail: "Se över ditt skydd mot hepatit A och planera för säker mat och dryck.")
            ]
        case .asia:
            [
                Topic(icon: "drop", title: "Hepatit A", detail: "Se över ditt skydd mot hepatit A och planera för säker mat och dryck."),
                Topic(icon: "ant", title: "Dengue och malaria", detail: "Skydda dig mot myggstick i riskområden. Kontrollera om förebyggande malarialäkemedel behövs på din rutt."),
                Topic(icon: "leaf", title: "Japansk encefalit", detail: "Fråga om vaccin vid längre vistelse eller mycket tid på landsbygden i riskområden, exempelvis i delar av Sydostasien.")
            ]
        case .oceania:
            [
                Topic(icon: "shield", title: "Grundskydd", detail: "Se över ditt skydd mot bland annat mässling före resan."),
                Topic(icon: "drop", title: "Hepatit A på Stillahavsöar", detail: "Se över skyddet om du ska till ett område där hepatit A är vanligt, exempelvis Fiji."),
                Topic(icon: "ant", title: "Malaria och myggskydd", detail: "Kontrollera risken för ditt resmål. I Papua Nya Guinea kan du behöva både myggskydd och förebyggande malarialäkemedel.")
            ]
        }
    }
}

struct TravelVaccinationView: View {
    @Binding var region: TravelVaccinationRegion?
    let pageBackground: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var panelHeadingFocused: Bool

    static let mapSky = Color(red: 0.09, green: 0.075, blue: 0.18)
    private let mapHorizon = Color(red: 0.22, green: 0.17, blue: 0.36)
    private let panelInset: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let panelWidth = min(480, max(0, width - panelInset * 2),
                                 width * (dynamicTypeSize.isAccessibilitySize ? 0.86 : 0.76))
            let exposedMapWidth = max(0, width - panelWidth - panelInset)

            ZStack(alignment: .topTrailing) {
                mapAndSources(width: width, exposedMapWidth: exposedMapWidth)
                    .allowsHitTesting(region == nil)
                    .accessibilityHidden(region != nil)

                if let region {
                    Button { select(nil) } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)

                    regionPanel(for: region)
                        .frame(width: panelWidth)
                        .frame(maxHeight: max(0, geometry.size.height - panelInset * 2), alignment: .top)
                        .padding([.top, .trailing], panelInset)
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .clipped()
        }
    }

    private func mapAndSources(width: CGFloat, exposedMapWidth: CGFloat) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 14) {
                    if let map = TravelVaccinationMap.shared {
                        mapSection(map, width: width, exposedMapWidth: exposedMapWidth)
                            .id("world-map")
                    }

                    sourceCard
                        .frame(maxWidth: 500)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)
                }
                .frame(maxWidth: .infinity)
            }
            .onChange(of: region) { _, selected in
                if selected != nil { scroll.scrollTo("world-map", anchor: .top) }
            }
        }
    }

    private func mapSection(_ map: TravelVaccinationMap, width: CGFloat, exposedMapWidth: CGFloat) -> some View {
        let mapWidth = min(760, width)
        let drawingWidth = max(0, mapWidth - 8)
        let originX = (width - drawingWidth) / 2
        let offset = region.map { option in
            let selectedCenter = originX + map.horizontalCenter(of: option) * drawingWidth
            return min(0, exposedMapWidth / 2 - selectedCenter)
        } ?? 0

        return mapGraphic(map)
            .padding(.horizontal, 4)
            .frame(maxWidth: 760)
            .offset(x: offset)
            .padding(.top, 22)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
            .background { mapBackdrop }
    }

    private var mapBackdrop: some View {
        LinearGradient(colors: [Self.mapSky, mapHorizon], startPoint: .top, endPoint: .bottom)
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.97), location: 0.12),
                        .init(color: .black.opacity(0.85), location: 0.28),
                        .init(color: .black.opacity(0.62), location: 0.42),
                        .init(color: .black.opacity(0.36), location: 0.57),
                        .init(color: .black.opacity(0.15), location: 0.72),
                        .init(color: .black.opacity(0.03), location: 0.90),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: 34)
                }
            }
            .background(pageBackground)
    }

    private func mapGraphic(_ map: TravelVaccinationMap) -> some View {
        let aspect = horizontalSizeClass == .compact ? 1.38 : map.width / map.height
        return GeometryReader { geometry in
            mapCanvas(map)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let rect = CGRect(origin: .zero, size: geometry.size)
                    if let option = TravelVaccinationRegion.allCases.first(where: {
                        map.path(for: $0, in: rect).contains(location, eoFill: true)
                    }) {
                        select(option)
                    }
                }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .accessibilityLabel("Världskarta")
        .accessibilityChildren {
            ForEach(TravelVaccinationRegion.allCases) { option in
                Button(option.title) { select(option) }
                    .accessibilityAddTraits(option == region ? [.isSelected] : [])
            }
        }
    }

    private func mapCanvas(_ map: TravelVaccinationMap) -> some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            var grid = Path()
            for column in 1..<12 {
                let x = rect.width * CGFloat(column) / 12
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: rect.height))
            }
            for row in 1..<6 {
                let y = rect.height * CGFloat(row) / 6
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: rect.width, y: y))
            }
            context.stroke(grid, with: .radialGradient(
                Gradient(colors: [.white.opacity(0.17), .clear]),
                center: CGPoint(x: rect.midX, y: rect.midY),
                startRadius: 0,
                endRadius: size.width * 0.60
            ), style: StrokeStyle(lineWidth: 0.6, dash: [2, 3]))

            let paths = TravelVaccinationRegion.allCases.map { ($0, map.path(for: $0, in: rect)) }
            for (option, path) in paths where option != region {
                let upper = option.color.opacity(region == nil ? 1 : 0.52)
                let lower = option.color.opacity(region == nil ? 0.72 : 0.33)
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [upper, lower]),
                    startPoint: CGPoint(x: 0, y: path.boundingRect.minY),
                    endPoint: CGPoint(x: 0, y: path.boundingRect.maxY)
                ), style: FillStyle(eoFill: true))
            }

            if let region, let path = paths.first(where: { $0.0 == region })?.1 {
                var glow = context
                glow.addFilter(.shadow(color: region.color.opacity(0.72), radius: 7))
                glow.fill(path, with: .color(region.color), style: FillStyle(eoFill: true))
                context.stroke(path, with: .color(.white.opacity(0.86)), lineWidth: 0.8)
            }
        }
    }

    private func select(_ option: TravelVaccinationRegion?) {
        guard option != region else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.32)) {
            region = option
        }
    }

    private func regionPanel(for option: TravelVaccinationRegion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(option.color).frame(width: 10, height: 10).accessibilityHidden(true)
                Text(option.title)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($panelHeadingFocused)
                Spacer(minLength: 0)
                Button { select(nil) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(.primary.opacity(0.055), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stäng reseråd för \(option.title)")
            }

            ViewThatFits(in: .vertical) {
                regionTopics(for: option)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView { regionTopics(for: option) }
            }
            .id(option)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.background)
                .onTapGesture {} // Keep taps on the panel from closing it via the backdrop.
                .accessibilityHidden(true)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, x: -3, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityAction(.escape) { select(nil) }
        .onAppear { panelHeadingFocused = true }
    }

    private func regionTopics(for option: TravelVaccinationRegion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(option.topics) { topic in
                Divider()
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: topic.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 21)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(topic.title).font(.subheadline.weight(.semibold))
                        Text(topic.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Råd för din resa")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Behovet av skydd beror på ditt resmål, hur länge du är borta, vad du ska göra och vilka doser du redan har fått. Kontakta en vaccinationsmottagning i god tid före avresa.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            sourceLink("Vaccinationer inför resan · 1177", url: "https://www.1177.se/liv--halsa/reserad-och-vaccinationer/vaccinationer/")
            sourceLink("Sök råd per land · CDC", url: "https://wwwnc.cdc.gov/travel/destinations/list")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private func sourceLink(_ title: String, url: String) -> some View {
        // Both destinations are fixed HTTPS URLs.
        Link(destination: URL(string: url)!) {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").accessibilityHidden(true)
            }
            .font(.footnote.weight(.semibold))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }
}

private struct TravelVaccinationMap: Decodable {
    let width: CGFloat
    let height: CGFloat
    private let regions: [String: Path]

    private enum CodingKeys: String, CodingKey { case width, height, regions }

    init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        width = try data.decode(CGFloat.self, forKey: .width)
        height = try data.decode(CGFloat.self, forKey: .height)
        let rings = try data.decode([String: [[[Int]]]].self, forKey: .regions)
        regions = rings.mapValues { rings in
            Path { path in
                for ring in rings {
                    let points = ring.compactMap { pair -> CGPoint? in
                        guard pair.count == 2 else { return nil }
                        return CGPoint(x: pair[0], y: pair[1])
                    }
                    if let first = points.first {
                        path.move(to: first)
                        path.addLines(Array(points.dropFirst()))
                        path.closeSubpath()
                    }
                }
            }
        }
    }

    static let shared: Self? = {
        guard let asset = NSDataAsset(name: "travel-vaccination-map") else { return nil }
        return try? JSONDecoder().decode(Self.self, from: asset.data)
    }()

    func path(for region: TravelVaccinationRegion, in rect: CGRect) -> Path {
        regions[region.rawValue, default: Path()]
            .applying(CGAffineTransform(scaleX: rect.width / width, y: rect.height / height))
    }

    func horizontalCenter(of region: TravelVaccinationRegion) -> CGFloat {
        (regions[region.rawValue]?.boundingRect.midX ?? width / 2) / width
    }
}

