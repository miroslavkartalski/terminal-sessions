import SwiftUI

// MARK: - AI Tool

enum AITool: Equatable {
    case claude, codex, gemini

    var label: String {
        switch self { case .claude: return "Claude"; case .codex: return "Codex"; case .gemini: return "Gemini" }
    }
}

// MARK: - AI Tool Icon

/// Brand icon for Claude Code, OpenAI Codex, or Gemini.
struct AIToolIcon: View {
    let tool: AITool
    var size: CGFloat = 15

    var body: some View {
        switch tool {

        case .claude:
            // Claude Code pixel-art robot icon (orange/black SVG)
            Image("ClaudeCodeIcon")
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .aspectRatio(66/52, contentMode: .fit)
                .frame(width: size, height: size * (52/66))

        case .codex:
            // Official OpenAI blossom mark — white SVG, visible on dark popover
            Image("OpenAIIcon")
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .frame(width: size * 1.3, height: size * 1.3)

        case .gemini:
            // Gemini icon PNG
            Image("GeminiIcon")
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
    }
}
