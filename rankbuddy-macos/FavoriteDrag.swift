//
//  FavoriteDrag.swift
//  rankbuddy-macos
//
//  The drag-and-drop payload behind "drag a list row onto the sidebar to favourite it"
//  (#89/#41). A list row (tests / questions / interviews) carries its `FavoriteRef` as an
//  in-process pasteboard item; the sidebar's Favourites section is a drop target that pins
//  the dropped item to the account carried in the payload. The whole drag never leaves the
//  app, but `UTType(exportedAs:)` still requires the identifier be backed by a
//  UTExportedTypeDeclarations entry in Info.plist or the runtime won't register it.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// In-process type for an internal favourite drag. Exported and backed by a
    /// UTExportedTypeDeclarations entry in Info.plist — `exportedAs:` requires it even
    /// though the drag never leaves the app and only the sidebar drop target reads it.
    /// `nonisolated` so the pasteboard helpers (which build in a nonisolated context) can
    /// reference it.
    nonisolated static let rankBuddyFavorite = UTType(exportedAs: "com.rankbuddy.favorite")
}

/// Encodes/decodes a `FavoriteRef` for the favourite drag pasteboard. Pure and unit-testable:
/// the round-trip is what carries the dragged item from a list row to the sidebar drop target.
enum FavoritePasteboard {
    private nonisolated struct Payload: Codable {
        let ref: FavoriteRef
        let sessionNonce: UUID
    }

    private nonisolated static let sessionNonce = UUID()
    private nonisolated static let maximumPayloadBytes = 16 * 1024

    /// Builds the pasteboard item a draggable list row hands the sidebar, or `nil` when the
    /// ref can't be encoded (which makes the row non-draggable, per FastList's `onRowDrag`).
    nonisolated static func item(for ref: FavoriteRef) -> NSPasteboardItem? {
        guard let data = try? JSONEncoder().encode(Payload(ref: ref, sessionNonce: sessionNonce)) else {
            return nil
        }

        let item = NSPasteboardItem()
        item.setData(data, forType: NSPasteboard.PasteboardType(UTType.rankBuddyFavorite.identifier))
        return item
    }

    /// Decodes the `FavoriteRef` a drop delivered, or `nil` if the data isn't ours.
    nonisolated static func decode(from data: Data) -> FavoriteRef? {
        guard data.count <= maximumPayloadBytes,
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.sessionNonce == sessionNonce,
              !payload.ref.accountID.isEmpty,
              !payload.ref.itemID.isEmpty,
              !payload.ref.title.isEmpty,
              payload.ref.accountID.count <= 64,
              payload.ref.itemID.count <= 512,
              payload.ref.title.count <= 512
        else { return nil }

        return payload.ref
    }
}

/// App-level signal that a favourite-able row is currently being dragged, so the sidebar can
/// reveal its Favourites drop zone *only* while a drop is possible and keep no resting gap
/// otherwise (#89). The NSTableView row drag has clean begin/end callbacks, so `FastList`
/// flips this true when such a drag begins and false when it ends — no timer or observer.
@MainActor
@Observable
final class FavoriteDragMonitor {
    static let shared = FavoriteDragMonitor()
    private init() {}

    /// True while a row carrying a `rankBuddyFavorite` payload is in flight.
    var isDragging = false
}

/// The favourite-drag lifecycle hooks passed into `FastList`'s drag callbacks. Keeping the
/// payload inspection here means the reusable list never references the app's favourite type
/// or `FavoriteDragMonitor`. While a row carrying a favourite payload is dragged, reveal the
/// sidebar's drop zone (#89); a plain row with no payload reveals nothing.
@MainActor
enum FavoriteDragLifecycle {
    /// A row drag began: reveal the drop zone only when the session actually carries a
    /// favourite payload, so a non-favouritable row never reveals a target nothing can drop on.
    static let onBegan: (NSDraggingSession) -> Void = { session in
        let canFavorite = session.draggingPasteboard
            .canReadItem(withDataConformingToTypes: [UTType.rankBuddyFavorite.identifier])
        if canFavorite {
            FavoriteDragMonitor.shared.isDragging = true
        }
    }

    /// The drag dropped or was cancelled: collapse the revealed drop zone again.
    static let onEnded: () -> Void = { FavoriteDragMonitor.shared.isDragging = false }
}
