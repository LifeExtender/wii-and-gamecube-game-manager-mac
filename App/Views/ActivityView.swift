import SwiftUI
import WiiKit

struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.queue.jobs.isEmpty && model.queue.log.isEmpty {
                ContentUnavailableView("Nothing Yet", systemImage: "clock", description: Text("Conversions, transfers and downloads appear here."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !model.queue.jobs.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel(text: "In Progress")
                                ForEach(model.queue.jobs) { JobRow(job: $0) }
                            }
                        }
                        if !model.queue.log.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel(text: "History")
                                VStack(spacing: 0) {
                                    ForEach(model.queue.log) {
                                        LogRow(entry: $0)
                                            .transition(Motion.slide(from: .top))
                                    }
                                }
                                .animation(Motion.gentle, value: model.queue.log.count)
                            }
                        }
                    }
                    .padding(26)
                    .frame(maxWidth: 780, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Export to CSV…") { model.exportLog() }.disabled(model.queue.log.isEmpty)
                    Button("Clear History") { model.queue.log.removeAll() }.disabled(model.queue.log.isEmpty)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .menuIndicator(.hidden)
            }
        }
    }
}

private struct JobRow: View {
    @Environment(AppModel.self) private var model
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(job.title).lineLimit(1)
                    Text(job.detail.isEmpty ? job.action : "\(job.action) · \(job.detail)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if job.state == .running, let fraction = job.fraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(Motion.snappy, value: fraction)
                } else if job.state == .queued {
                    Text("Waiting").font(.callout).foregroundStyle(.tertiary)
                }
                Button { model.queue.cancel(job) } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Cancel")
            }
            if job.state == .running { UsageBar(fraction: job.fraction ?? 0.02) }
        }
        .padding(12)
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct LogRow: View {
    let entry: JobRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(entry.succeeded ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.red))
                .frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).lineLimit(1)
                Text(entry.succeeded ? entry.action : "\(entry.action): \(entry.result)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer()
            Text(entry.date, format: .dateTime.hour().minute())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7)
    }
}
