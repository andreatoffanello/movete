import Foundation
import Observation
import SwiftUI

// MARK: - Debug Logger
// Intercetta e logga ogni operazione di rete, parsing, errore.
// Visibile solo in DEBUG builds tramite overlay shake-to-show.

@Observable
@MainActor
final class DebugLogger {
    static let shared = DebugLogger()

    var entries: [LogEntry] = []
    var isVisible = false

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let category: Category
        let message: String
        let detail: String?

        enum Category: String {
            case network = "NET"
            case data = "DATA"
            case realtime = "RT"
            case error = "ERR"
            case info = "INFO"

            var color: Color {
                switch self {
                case .network: return .blue
                case .data: return .green
                case .realtime: return .cyan
                case .error: return .red
                case .info: return .gray
                }
            }
        }
    }

    func log(_ category: LogEntry.Category, _ message: String, detail: String? = nil) {
        #if DEBUG
        let entry = LogEntry(category: category, message: message, detail: detail)
        entries.append(entry)
        // Keep last 200
        if entries.count > 200 {
            entries.removeFirst(entries.count - 200)
        }
        // Also print to console
        let ts = Self.timeFormatter.string(from: entry.timestamp)
        print("[\(ts)] [\(category.rawValue)] \(message)\(detail.map { " — \($0)" } ?? "")")
        #endif
    }

    func toggle() {
        #if DEBUG
        isVisible.toggle()
        #endif
    }

    func clear() {
        entries.removeAll()
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

// MARK: - Debug Overlay View

#if DEBUG
struct DebugOverlay: View {
    @State private var logger = DebugLogger.shared
    @State private var selectedEntry: DebugLogger.LogEntry?

    var body: some View {
        if logger.isVisible {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("DEBUG")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(logger.entries.count) entries")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                    Button("Clear") { logger.clear() }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                    Button("✕") { logger.isVisible = false }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.leading, 8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.9))

                // Log entries
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(logger.entries) { entry in
                                logRow(entry)
                                    .id(entry.id)
                                    .onTapGesture { selectedEntry = entry }
                            }
                        }
                    }
                    .onChange(of: logger.entries.count) { _, _ in
                        if let last = logger.entries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .frame(maxHeight: 250)
                .background(Color.black.opacity(0.85))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .sheet(item: $selectedEntry) { entry in
                detailView(entry)
            }
        }
    }

    private func logRow(_ entry: DebugLogger.LogEntry) -> some View {
        HStack(spacing: 6) {
            Text(entry.category.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(entry.category.color)
                .frame(width: 32, alignment: .leading)

            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)

            Spacer()

            if entry.detail != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func detailView(_ entry: DebugLogger.LogEntry) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(entry.category.rawValue)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(entry.category.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(entry.category.color.opacity(0.15))
                            .clipShape(Capsule())

                        Text(Self.timeFormatter.string(from: entry.timestamp))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Text(entry.message)
                        .font(.system(size: 14, weight: .medium))

                    if let detail = entry.detail {
                        Text(detail)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
            .navigationTitle("Log Detail")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}
#endif
