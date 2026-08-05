melliebird16//
//  RankBuddyEntryPoint.swift
//  rankbuddy-macos
//

import Foundation
import MCPKit
import SwiftUI

/// The process entry point (#9).
///
/// Launched with `--mcp`, the app binary serves the RankBuddy MCP tool catalogue over a stdio
/// transport, so an MCP client (Claude Desktop, etc.) can spawn this same binary as a server
/// with keychain-loaded credentials — no separate executable target needed. Otherwise it
/// launches the normal SwiftUI GUI via `RankBuddyApp.main()`. The stdio bootstrap (flag detection,
/// enabled gate, async-to-sync bridge) is buddy-kit's shared `runOverStdioUntilExit` (#647).
@main
enum RankBuddyEntryPoint {
    static func main() {
        if MCPServer.wantsStdioMCP() {
            // Read the MainActor-isolated settings here (main runs on the MainActor) and capture
            // them, since buddy-kit's gate closure is `@Sendable`/nonisolated.
            let enabled = MCPServerSettings.isEnabled()
            let provider = RankBuddyToolProvider(allowWrites: MCPServerSettings.allowsWrites())
            MCPServer.runOverStdioUntilExit(
                name: "RankBuddy",
                isEnabled: { enabled },
                disabledMessage:
                "RankBuddy MCP server is disabled. Enable it in RankBuddy ▸ Settings ▸ MCP, then retry.",
                provider: provider
            )
        } else {
            RankBuddyApp.main()
        }
    }
}
