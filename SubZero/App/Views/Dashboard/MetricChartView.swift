import SwiftUI
import Charts

struct MetricChartView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject var historyStore: HistoryStore
    
    var body: some View {
        let snapshots = viewModel.getSnapshots(from: historyStore)
        let metric = viewModel.selectedChartMetric
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.rawValue)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let latest = snapshots.last, let val = viewModel.getValue(for: metric, from: latest) {
                        Text(String(format: "%.1f %@", val, metric.unitString))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(metric.color)
                    } else {
                        Text("-- " + metric.unitString)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Metric Selector
                Picker("Metric", selection: $viewModel.selectedChartMetric) {
                    ForEach(ChartMetricType.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
                
                // Time Range Selector
                Picker("Range", selection: $viewModel.selectedTimeRange) {
                    ForEach(ChartTimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            
            if metric == .fanRPM && snapshots.allSatisfy({ viewModel.getValue(for: metric, from: $0) == nil }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.08))
                    VStack(spacing: 8) {
                        Image(systemName: "fanblades.slash")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No Active Fans Detected")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                        Text("This Mac uses passive cooling or fans are currently stationary.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 180)
            } else if snapshots.isEmpty || snapshots.allSatisfy({ viewModel.getValue(for: metric, from: $0) == nil }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.08))
                    VStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("Collecting telemetry data...")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                        Text("Sampling live hardware telemetry every second...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 180)
            } else {
                Chart {
                    ForEach(snapshots) { snap in
                        if let val = viewModel.getValue(for: metric, from: snap) {
                            AreaMark(
                                x: .value("Time", snap.timestamp),
                                y: .value(metric.rawValue, val)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [metric.color.opacity(0.4), metric.color.opacity(0.05)]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(snapshots.count >= 3 ? .catmullRom : .linear)
                            
                            LineMark(
                                x: .value("Time", snap.timestamp),
                                y: .value(metric.rawValue, val)
                            )
                            .foregroundStyle(metric.color)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(snapshots.count >= 3 ? .catmullRom : .linear)
                            
                            if snapshots.count == 1 {
                                PointMark(
                                    x: .value("Time", snap.timestamp),
                                    y: .value(metric.rawValue, val)
                                )
                                .foregroundStyle(metric.color)
                                .symbolSize(50)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(Color.secondary.opacity(0.3))
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(Color.secondary.opacity(0.3))
                        AxisValueLabel()
                    }
                }
                .frame(height: 180)
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 2)
        )
    }
}
