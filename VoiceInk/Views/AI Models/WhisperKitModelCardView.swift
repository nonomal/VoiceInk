import SwiftUI

struct WhisperKitModelCardView: View {
    let model: WhisperKitModel
    let isDownloaded: Bool
    let isCurrent: Bool
    let downloadProgress: [String: Double]
    
    // Actions
    var deleteAction: () -> Void
    var setDefaultAction: () -> Void
    var downloadAction: () -> Void
    var showInFinderAction: () -> Void
    
    private var isDownloading: Bool {
        downloadProgress[model.name] != nil && downloadProgress[model.name]! < 1.0
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    headerSection
                    metadataSection
                    descriptionSection
                    progressSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                actionSection
            }
            .padding(16)
            .background(CardBackground(isSelected: isCurrent, useAccentGradientWhenSelected: isCurrent))
            
            Text("Experimental")
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.2))
                .foregroundColor(.orange)
                .cornerRadius(6)
                .offset(x: 10, y: -10) // Adjust position as needed
        }
    }
    
    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(.labelColor))
            
            statusBadge
            
            Spacer()
        }
    }
    
    private var statusBadge: some View {
        Group {
            if isCurrent {
                Text("Default")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundColor(.white)
            } else if isDownloaded {
                Text("Downloaded")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(.quaternaryLabelColor)))
                    .foregroundColor(Color(.labelColor))
            }
        }
    }
    
    private var metadataSection: some View {
        HStack(spacing: 12) {
            Label(model.language, systemImage: "globe")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)
            
            Label(model.size, systemImage: "internaldrive")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)

            HStack(spacing: 3) {
                Text("Speed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(.secondaryLabelColor))
                progressDotsWithNumber(value: model.speed * 10)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            
            HStack(spacing: 3) {
                Text("Accuracy")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(.secondaryLabelColor))
                progressDotsWithNumber(value: model.accuracy * 10)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .lineLimit(1)
    }
    
    private var descriptionSection: some View {
        Text(model.description)
            .font(.system(size: 11))
            .foregroundColor(Color(.secondaryLabelColor))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
    
    private var progressSection: some View {
        Group {
            if isDownloading {
                if let progress = downloadProgress[model.name] {
                    HStack {
                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle())
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
    
    private var actionSection: some View {
        HStack(spacing: 8) {
            if isCurrent {
                Text("Default Model")
                    .font(.system(size: 12))
                    .foregroundColor(Color(.secondaryLabelColor))
            } else if isDownloaded {
                Button(action: setDefaultAction) {
                    Text("Set as Default")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(action: downloadAction) {
                    HStack(spacing: 4) {
                        Text(isDownloading ? "Downloading..." : "Download")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(.controlAccentColor))
                            .shadow(color: Color(.controlAccentColor).opacity(0.2), radius: 2, x: 0, y: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isDownloading)
            }
            
            if isDownloaded {
                Menu {
                    Button(action: deleteAction) {
                        Label("Delete Model", systemImage: "trash")
                    }
                    Button(action: showInFinderAction) {
                        Label("Show in Finder", systemImage: "folder")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20, height: 20)
            }
        }
    }
} 