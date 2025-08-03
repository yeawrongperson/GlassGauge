//
//  NetworkDualTile.swift
//  GlassGauge
//
//  Created by Matt Zeigler on 8/3/25.
//


import SwiftUI
import Charts

struct NetworkDualTile: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var networkIn: MetricModel
    @ObservedObject var networkOut: MetricModel

    var body: some View {
        GlassCard(emphasized: !state.reduceMotion) {
            VStack(alignment: .leading, spacing: 8) {
                // Header with network icon and title
                HStack {
                    Image(systemName: "wifi")
                        .font(.title3)
                        .frame(width: 28)
                        .foregroundStyle(.primary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Network")
                            .font(.callout)
                            .opacity(0.85)
                        
                        HStack(spacing: 4) {
                            Text("Total:")
                                .font(.caption)
                                .opacity(0.7)
                            Text(state.network.primaryString)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                    
                    Spacer()
                }
                
                // Dual charts
                HStack(spacing: 8) {
                    // Incoming traffic (Green)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text("In")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.green)
                        }
                        
                        Text(networkIn.primaryString)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.green)
                            .lineLimit(1)
                        
                        NetworkMiniChart(samples: networkIn.samples, color: .green, reduceMotion: state.reduceMotion)
                            .frame(height: 24)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Divider
                    Rectangle()
                        .fill(.separator)
                        .frame(width: 1)
                        .opacity(0.5)
                    
                    // Outgoing traffic (Red)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Text("Out")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.red)
                        }
                        
                        Text(networkOut.primaryString)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.red)
                            .lineLimit(1)
                        
                        NetworkMiniChart(samples: networkOut.samples, color: .red, reduceMotion: state.reduceMotion)
                            .frame(height: 24)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct NetworkMiniChart: View {
    let samples: [SamplePoint]
    let color: Color
    var reduceMotion: Bool
    
    var body: some View {
        Chart(samples) {
            LineMark(x: .value("t", $0.t), y: .value("v", $0.v))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(color)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { $0.frame(maxWidth: .infinity) }
        .animation(reduceMotion ? nil : .default, value: samples)
    }
}