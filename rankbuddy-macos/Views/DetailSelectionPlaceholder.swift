//
//  DetailSelectionPlaceholder.swift
//  rankbuddy-macos
//

import SwiftUI

/// A useful resting state, adapted from PadBuddy without implying that selection is an error.
struct DetailSelectionPlaceholder: View {
    let collectionTitle: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private struct Resource {
        let name: String
        let image: String
        let features: [String]

        init(_ name: String, _ image: String, _ features: [String]) {
            self.name = name
            self.image = image
            self.features = features
        }
    }

    private var resource: Resource {
        switch collectionTitle {
        case "Tests": Resource("test", "checklist", ["Settings", "Questions", "Candidates"])
        case "Questions": Resource("question", "questionmark.bubble", ["Prompt", "Guidelines", "Answers"])
        case "Interviews": Resource("interview", "person.crop.rectangle.stack", ["Schedule", "Notes", "Transcript"])
        case "People", "Members": Resource("person", "person.crop.circle", ["Profile", "Account access"])
        case "Teams": Resource("team", "person.3", ["Team details", "Members"])
        case "Interview Templates": Resource("template", "doc.on.doc", ["Questions", "Properties", "Sharing"])
        case "Invitation Templates": Resource("template", "envelope", ["Subject", "Email body"])
        case "Candidates": Resource("candidate", "person.crop.circle", ["Attempts", "Scores", "Reports"])
        default: Resource("item", "sidebar.right", ["Details"])
        }
    }

    private var selectionTitle: String {
        let article = resource.name == "interview" || resource.name == "item" ? "an" : "a"
        return "Select \(article) \(resource.name)"
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: resource.image)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.tint)
                        .padding(20)
                        .background(.tint.opacity(0.10), in: Circle())
                        .accessibilityHidden(true)
                    Text(selectionTitle)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Choose a row in \(collectionTitle) to review its details.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { featureLabels }
                        VStack(spacing: 8) { featureLabels }
                    }
                    Label("Use the arrow keys to choose from the list", systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(28)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .background(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : .clear)
        .accessibilityIdentifier("detail-selection-placeholder")
    }

    private var featureLabels: some View {
        ForEach(resource.features, id: \.self) { feature in
            Text(feature).font(.callout)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.secondary.opacity(0.08), in: Capsule())
        }
    }
}
