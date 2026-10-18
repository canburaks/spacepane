import Foundation
import PreviewContracts
import PreviewRenderers

/// Search limits the visible rows, never the membership used by a group control.
struct FileTypeSettingsGroup: Identifiable {
    let group: FormatGroup
    let members: [FormatDescriptor]
    let visibleMembers: [FormatDescriptor]
    var id: String { group.rawValue }
    var nameKey: PreviewStrings.Key { Self.nameKey(for: group) }

    /// Counts every member, so a search that hides rows never changes the group's state.
    func enablement(isEnabled: (FormatID) -> Bool) -> FileTypeEnablementSummary {
        FileTypeEnablementSummary(members, isEnabled: isEnabled)
    }

    static func matching(in catalog: FormatCatalog, search: String) -> [Self] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let groups = catalog.descriptors.reduce(into: [FormatGroup]()) { groups, descriptor in
            if !groups.contains(descriptor.group) { groups.append(descriptor.group) }
        }
        return groups.compactMap { group in
            let members = catalog.descriptors.filter { $0.group == group }
            let groupMatches = PreviewStrings.text(nameKey(for: group)).localizedStandardContains(query)
            let visibleMembers = members.filter { descriptor in
                query.isEmpty || groupMatches || matches(descriptor, query: query)
            }
            guard !visibleMembers.isEmpty else { return nil }
            return Self(group: group, members: members, visibleMembers: visibleMembers)
        }
    }

    /// What VoiceOver says once a search settles: how many types it shows, zero included, in the same sentences
    /// the preview's filters use.
    static func resultAnnouncement(for groups: [Self], locale: Locale) -> String {
        let count = groups.reduce(0) { $0 + $1.visibleMembers.count }
        return count > 0
            ? PreviewStrings.format(.interactionFilterMatches, arguments: [Int64(count)], locale: locale)
            : PreviewStrings.text(.interactionFilterNoMatches)
    }

    private static func nameKey(for group: FormatGroup) -> PreviewStrings.Key {
        switch group {
        case .text: .fileTypeGroupText
        case .structured: .fileTypeGroupStructured
        case .database: .fileTypeGroupDatabase
        case .containers: .fileTypeGroupContainers
        case .media: .fileTypeGroupMedia
        }
    }

    private static func matches(_ descriptor: FormatDescriptor, query: String) -> Bool {
        [PreviewStrings.text(catalogKey: descriptor.nameKey),
         PreviewStrings.text(catalogKey: descriptor.descriptionKey)]
            .contains { $0.localizedStandardContains(query) }
            || descriptor.suffixAliases.contains {
                $0.localizedStandardContains(query) || ("." + $0).localizedStandardContains(query)
            }
            || descriptor.filenameAliases.contains { $0.localizedStandardContains(query) }
            || descriptor.filenamePrefixes.contains { $0.localizedStandardContains(query) }
    }
}
