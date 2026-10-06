import SwiftUI
import UIKit
import Kingfisher

/// Générateur de PDF "déclaration de collection" : inventaire imprimable de toute la collection
/// (tous dossiers confondus), pensé comme justificatif à fournir à un assureur (valeur, état,
/// prix d'achat par exemplaire) plutôt que comme export de travail façon CSV.
@MainActor
enum CollectionPDFExporter {
    private static let pageSize = CGSize(width: 595.2, height: 841.8) // A4
    private static let margin: CGFloat = 36
    // Réduit par rapport à une table purement textuelle : chaque ligne inclut désormais une
    // jaquette de 34pt qui augmente sa hauteur minimale.
    private static let rowsPerPage = 15

    /// Télécharge (ou récupère en cache Kingfisher) une jaquette par release représentée dans
    /// l'export, avec un plafond de téléchargements simultanés pour ne pas saturer le réseau sur
    /// une grosse collection. Clé par `releaseId` : plusieurs exemplaires d'une même release
    /// partagent la même image.
    static func fetchCoverImages(for items: [CollectionItem]) async -> [Int: UIImage] {
        var urlByReleaseId: [Int: String] = [:]
        for item in items where urlByReleaseId[item.releaseId] == nil {
            let info = item.basicInformation
            if let thumb = info.thumb, !thumb.isEmpty {
                urlByReleaseId[item.releaseId] = thumb
            } else if let cover = info.coverImage, !cover.isEmpty {
                urlByReleaseId[item.releaseId] = cover
            }
        }

        var images: [Int: UIImage] = [:]
        let maxConcurrent = 6
        var iterator = urlByReleaseId.makeIterator()

        await withTaskGroup(of: (Int, UIImage?).self) { group in
            func addNext() {
                guard let (releaseId, urlString) = iterator.next(), let url = URL(string: urlString) else { return }
                group.addTask {
                    let image: UIImage? = await withCheckedContinuation { continuation in
                        KingfisherManager.shared.retrieveImage(with: url) { result in
                            switch result {
                            case .success(let value):
                                continuation.resume(returning: value.image)
                            case .failure:
                                continuation.resume(returning: nil)
                            }
                        }
                    }
                    return (releaseId, image)
                }
            }

            for _ in 0..<maxConcurrent { addNext() }
            while let (releaseId, image) = await group.next() {
                if let image {
                    images[releaseId] = image
                }
                addNext()
            }
        }

        return images
    }

    static func generatePDF(
        username: String,
        items: [CollectionItem],
        folders: [CollectionFolder],
        purchasePriceFieldId: Int?,
        mediaConditionFieldId: Int?,
        defaultCurrency: String,
        totalInvested: Double?,
        marketValue: CollectionValueResponse?,
        coverImages: [Int: UIImage]
    ) -> Data {
        let folderMap = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.name) })

        let sortedItems = items.sorted { a, b in
            let folderA = folderMap[a.folderId] ?? ""
            let folderB = folderMap[b.folderId] ?? ""
            if folderA != folderB {
                return folderA.localizedCaseInsensitiveCompare(folderB) == .orderedAscending
            }
            let artistA = a.basicInformation.artistNames
            let artistB = b.basicInformation.artistNames
            if artistA != artistB {
                return artistA.localizedCaseInsensitiveCompare(artistB) == .orderedAscending
            }
            return a.basicInformation.title.localizedCaseInsensitiveCompare(b.basicInformation.title) == .orderedAscending
        }

        let chunks: [[CollectionItem]] = stride(from: 0, to: sortedItems.count, by: rowsPerPage).map {
            Array(sortedItems[$0..<min($0 + rowsPerPage, sortedItems.count)])
        }
        let inventoryPages = chunks.isEmpty ? [[]] : chunks
        let totalPages = inventoryPages.count

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: AppInfo.name,
            kCGPDFContextTitle as String: "Déclaration de collection \(AppInfo.name) - \(username)"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)

        return renderer.pdfData { context in
            context.beginPage()
            draw(
                PDFCoverPageView(
                    username: username,
                    exportDate: Date(),
                    itemCount: sortedItems.count,
                    totalInvested: totalInvested,
                    totalInvestedCurrency: defaultCurrency,
                    marketValue: marketValue
                ),
                in: context
            )

            for (index, pageItems) in inventoryPages.enumerated() {
                context.beginPage()
                draw(
                    PDFInventoryPageView(
                        items: pageItems,
                        folderMap: folderMap,
                        coverImages: coverImages,
                        purchasePriceFieldId: purchasePriceFieldId,
                        mediaConditionFieldId: mediaConditionFieldId,
                        defaultCurrency: defaultCurrency,
                        pageNumber: index + 1,
                        totalPages: totalPages
                    ),
                    in: context
                )
            }
        }
    }

    private static func draw<V: View>(_ view: V, in context: UIGraphicsPDFRendererContext) {
        let imageRenderer = ImageRenderer(content: view)
        let cgContext = context.cgContext
        // `UIGraphicsPDFRenderer` retourne un contexte déjà retourné pour se comporter comme
        // UIKit (origine en haut à gauche), mais `ImageRenderer.render` applique son propre
        // retournement en repartant d'un contexte Quartz natif (origine en bas à gauche) : sans
        // cette contre-transformation, les deux s'additionnent et le texte ressort inversé/en miroir.
        cgContext.saveGState()
        cgContext.translateBy(x: 0, y: pageSize.height)
        cgContext.scaleBy(x: 1, y: -1)
        imageRenderer.render { _, renderInContext in
            renderInContext(cgContext)
        }
        cgContext.restoreGState()
    }
}

private enum PDFLayout {
    static let pageWidth: CGFloat = 595.2
    static let pageHeight: CGFloat = 841.8
    static let margin: CGFloat = 36
    static let titleColumnWidth: CGFloat = 230
    static let formatColumnWidth: CGFloat = 95
    static let conditionColumnWidth: CGFloat = 80
}

private struct PDFCoverPageView: View {
    let username: String
    let exportDate: Date
    let itemCount: Int
    let totalInvested: Double?
    let totalInvestedCurrency: String
    let marketValue: CollectionValueResponse?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer().frame(height: 60)

            Text("Déclaration de collection")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.black)

            Text("Généré par \(AppInfo.name)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.gray)

            Divider().padding(.vertical, 8)

            infoRow("Compte Discogs", username)
            infoRow("Date d'export", exportDate.formatted(date: .long, time: .shortened))
            infoRow("Nombre d'articles", "\(itemCount)")

            if let totalInvested {
                infoRow("Total investi (prix d'achat déclarés)", "\(String(format: "%.2f", totalInvested)) \(totalInvestedCurrency)")
            }

            if let marketValue {
                infoRow("Cote Discogs — minimum", marketValue.minimum)
                infoRow("Cote Discogs — médiane", marketValue.median)
                infoRow("Cote Discogs — maximum", marketValue.maximum)
            }

            Spacer()

            Text("Ce document liste l'ensemble des albums de la collection à la date d'export ci-dessus, à titre de justificatif (par exemple auprès d'un assureur). Les montants indiqués proviennent des informations renseignées manuellement dans l'application et des cotes publiques Discogs : ils ne constituent pas une expertise officielle.")
                .font(.system(size: 10))
                .foregroundStyle(.gray)
        }
        .padding(PDFLayout.margin)
        .frame(width: PDFLayout.pageWidth, height: PDFLayout.pageHeight, alignment: .topLeading)
        .background(Color.white)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black)
        }
    }
}

private struct PDFInventoryPageView: View {
    let items: [CollectionItem]
    let folderMap: [Int: String]
    let coverImages: [Int: UIImage]
    let purchasePriceFieldId: Int?
    let mediaConditionFieldId: Int?
    let defaultCurrency: String
    let pageNumber: Int
    let totalPages: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()

            ForEach(items) { item in
                row(for: item)
                Divider().opacity(0.3)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Text("Page \(pageNumber) / \(totalPages)")
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
            }
        }
        .padding(PDFLayout.margin)
        .frame(width: PDFLayout.pageWidth, height: PDFLayout.pageHeight, alignment: .topLeading)
        .background(Color.white)
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("Album")
                .frame(width: PDFLayout.titleColumnWidth, alignment: .leading)
            Text("Format / Année")
                .frame(width: PDFLayout.formatColumnWidth, alignment: .leading)
            Text("État")
                .frame(width: PDFLayout.conditionColumnWidth, alignment: .leading)
            Text("Prix d'achat")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(.black)
        .padding(.bottom, 6)
    }

    private func row(for item: CollectionItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                coverThumbnail(for: item)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.basicInformation.title)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(2)
                    Text(item.basicInformation.artistNames)
                        .font(.system(size: 8))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                    Text(folderMap[item.folderId] ?? "")
                        .font(.system(size: 7))
                        .foregroundStyle(.gray)
                }
            }
            .frame(width: PDFLayout.titleColumnWidth, alignment: .leading)

            Text(formatAndYear(item))
                .font(.system(size: 8))
                .foregroundStyle(.black)
                .frame(width: PDFLayout.formatColumnWidth, alignment: .leading)

            Text(condition(item))
                .font(.system(size: 8))
                .foregroundStyle(.black)
                .frame(width: PDFLayout.conditionColumnWidth, alignment: .leading)

            Text(purchasePrice(item))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func coverThumbnail(for item: CollectionItem) -> some View {
        let size: CGFloat = 34
        if let image = coverImages[item.releaseId] {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(white: 0.9))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                }
        }
    }

    private func formatAndYear(_ item: CollectionItem) -> String {
        let format = item.basicInformation.formats?.first?.name ?? ""
        let year = item.basicInformation.year.flatMap { $0 > 0 ? String($0) : nil } ?? ""
        return [format, year].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func condition(_ item: CollectionItem) -> String {
        guard let mediaConditionFieldId else { return "—" }
        let value = item.value(forFieldId: mediaConditionFieldId).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "—" : value
    }

    private func purchasePrice(_ item: CollectionItem) -> String {
        guard let purchasePriceFieldId else { return "—" }
        let raw = item.value(forFieldId: purchasePriceFieldId).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let parsed = PurchasePriceParser.parse(raw, defaultCurrency: defaultCurrency) else { return "—" }
        return "\(String(format: "%.2f", parsed.amount)) \(parsed.currency)"
    }
}
