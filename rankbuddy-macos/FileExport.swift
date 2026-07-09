//
//  FileExport.swift
//  rankbuddy-macos
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Shared export save flow: window-attached when possible, silent on cancel, explicit on write failure.
enum FileExport {
    @MainActor
    static func save(
        _ content: String,
        suggestedName: String,
        allowedContentTypes: [UTType],
        failureTitle: String
    ) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = allowedContentTypes

        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            guard panel.runModal() == .OK, let url = panel.url else { return }

            write(content, to: url, failureTitle: failureTitle)
            return
        }

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }

            Task { @MainActor in write(content, to: url, failureTitle: failureTitle) }
        }
    }

    @MainActor
    private static func write(_ content: String, to url: URL, failureTitle: String) {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = failureTitle
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }
    }
}
