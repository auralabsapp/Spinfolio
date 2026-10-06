import Foundation
import SwiftUI

/// Générateur d'export CSV pour la collection complète de l'utilisateur (tous dossiers confondus).
@MainActor
enum CollectionCSVExporter {
    static func generateCSV(
        items: [CollectionItem],
        folders: [CollectionFolder],
        fields: [CollectionField],
        tagStore: TagStore
    ) -> String {
        let folderMap = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.name) })

        // Tri propre et structuré : par nom de dossier, puis artiste, puis titre
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

        var headers = [
            String(localized: "Dossier", comment: "En-tête de colonne CSV : nom du dossier de la collection"),
            String(localized: "Artiste", comment: "En-tête de colonne CSV : nom de l'artiste"),
            String(localized: "Titre", comment: "En-tête de colonne CSV : titre de la release"),
            String(localized: "Format", comment: "En-tête de colonne CSV : format du support (vinyle, CD...)"),
            String(localized: "Label", comment: "En-tête de colonne CSV : label / maison de disque"),
            String(localized: "Numéro de catalogue", comment: "En-tête de colonne CSV : numéro de catalogue du label"),
            String(localized: "Année", comment: "En-tête de colonne CSV : année de sortie"),
            String(localized: "Genres", comment: "En-tête de colonne CSV : genres musicaux"),
            String(localized: "Styles", comment: "En-tête de colonne CSV : styles musicaux"),
            String(localized: "Date d'ajout", comment: "En-tête de colonne CSV : date d'ajout à la collection"),
            String(localized: "Note", comment: "En-tête de colonne CSV : note (rating) sur 5 attribuée à l'exemplaire"),
            String(localized: "Tags \(AppInfo.name)", comment: "En-tête de colonne CSV : tags personnalisés créés dans l'app")
        ]

        // Colonnes dynamiques pour les champs personnalisés Discogs (ex: État du disque, Pochette...)
        if fields.isEmpty {
            headers.append(String(localized: "Notes", comment: "En-tête de colonne CSV : notes libres/texte de l'exemplaire (distinct de la note chiffrée)"))
        } else {
            for field in fields {
                headers.append(field.name)
            }
        }

        headers.append(contentsOf: [
            String(localized: "Release ID", comment: "En-tête de colonne CSV : identifiant Discogs de la release"),
            String(localized: "Instance ID", comment: "En-tête de colonne CSV : identifiant Discogs de l'exemplaire dans la collection"),
            String(localized: "URL Discogs", comment: "En-tête de colonne CSV : lien vers la page Discogs de la release")
        ])

        var csvLines: [String] = []
        csvLines.append(headers.map(escapeCSV).joined(separator: ";"))

        for item in sortedItems {
            let folderName = folderMap[item.folderId] ?? (item.folderId == 0 ? "Tous" : "Dossier \(item.folderId)")
            let artist = item.basicInformation.artistNames
            let title = item.basicInformation.title

            let formats = item.basicInformation.formats?.map { f in
                var parts = [f.name]
                if let desc = f.descriptions, !desc.isEmpty {
                    parts.append(desc.joined(separator: ", "))
                }
                if let text = f.text, !text.isEmpty {
                    parts.append(text)
                }
                return parts.joined(separator: " - ")
            }.joined(separator: " | ") ?? ""

            let labels = item.basicInformation.labels?.compactMap(\.name).filter { !$0.isEmpty }.joined(separator: ", ") ?? ""
            let catnos = item.basicInformation.labels?.compactMap(\.catno).filter { !$0.isEmpty }.joined(separator: ", ") ?? ""
            let year = item.basicInformation.year.map(String.init) ?? ""
            let genres = item.basicInformation.genres?.joined(separator: ", ") ?? ""
            let styles = item.basicInformation.styles?.joined(separator: ", ") ?? ""
            let dateAdded = item.dateAddedDate?.formatted(Date.FormatStyle(date: .numeric, time: .omitted)) ?? item.dateAdded
            let rating = item.rating > 0 ? String(item.rating) : ""
            let tags = tagStore.tags(for: item.instanceId, releaseId: item.releaseId).joined(separator: ", ")

            var rowValues = [
                folderName,
                artist,
                title,
                formats,
                labels,
                catnos,
                year,
                genres,
                styles,
                dateAdded,
                rating,
                tags
            ]

            if fields.isEmpty {
                let notesText = item.notes.map(\.value).filter { !$0.isEmpty }.joined(separator: " ; ")
                rowValues.append(notesText)
            } else {
                for field in fields {
                    let val = item.value(forFieldId: field.id)
                    rowValues.append(val)
                }
            }

            rowValues.append(contentsOf: [
                String(item.releaseId),
                String(item.instanceId),
                "https://www.discogs.com/release/\(item.releaseId)"
            ])

            csvLines.append(rowValues.map(escapeCSV).joined(separator: ";"))
        }

        // Préfixe avec BOM UTF-8 (\u{FEFF}) pour garantir l'encodage des accents dans Excel et Numbers
        return "\u{FEFF}" + csvLines.joined(separator: "\r\n")
    }

    nonisolated private static func escapeCSV(_ text: String) -> String {
        if text.contains(",") || text.contains("\"") || text.contains("\n") || text.contains("\r") || text.contains(";") {
            let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return text
    }
}

import UIKit

/// Présente la boîte de dialogue de partage native iOS (`UIActivityViewController`)
/// pour un fichier exporté (AirDrop, Messages, Mail, Enregistrer dans Fichiers, etc.).
@MainActor
enum ShareSheetPresenter {
    static func present(url: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }

        var topController = rootVC
        while let presented = topController.presentedViewController {
            topController = presented
        }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topController.view
            popover.sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        topController.present(activityVC, animated: true)
    }
}
