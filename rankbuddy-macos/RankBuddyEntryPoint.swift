//
//  RankBuddyEntryPoint.swift
//  rankbuddy-macos
//

import BuddyMCP
import Foundation
import MCP
import SwiftUI

/// The process entry point (#9).
///
/// Launched with `--mcp`, the app binary serves the RankBuddy MCP tool catalogue over a stdio
/// transport, so an MCP client (Claude Desktop, etc.) can spawn this same binary as a server
/// with keychain-loaded credentials — no separate executable target needed. Otherwise it
/// launches the normal SwiftUI GUI via `RankBuddyApp.main()`.
@main
enum RankBuddyEntryPoint {
    static func main() {
        if CommandLine.arguments.dropFirst().contains("--mcp") {
            guard MCPServerSettings.isEnabled() else {
                FileHandle.standardError.write(Data(
                    "RankBuddy MCP server is disabled. Enable it in RankBuddy ▸ Settings ▸ MCP, then retry.\n".utf8
                ))
                exit(EXIT_FAILURE)
            }

            runMCPServer()
        } else {
            RankBuddyApp.main()
        }
    }

    /// Serves the stdio MCP server, blocking the main thread until the client disconnects.
    private static func runMCPServer() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
            do {
                let provider = RankBuddyToolProvider(allowWrites: MCPServerSettings.allowsWrites())
                let server = BuddyMCPServer(name: "RankBuddy", version: version, provider: provider)
                try await server.run(transport: StdioTransport())
            } catch {
                FileHandle.standardError.write(Data("RankBuddy MCP server error: \(error)\n".utf8))
            }
            semaphore.signal()
        }
        semaphore.wait()
    }
}
