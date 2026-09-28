import SwiftUI

/// Grid for choosing which carousel items to download.
struct CarouselPickerView: View {
    @EnvironmentObject private var viewModel: DownloadViewModel
    let post: InstagramPost

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Carrousel").font(.headline)
                    if let owner = post.owner {
                        Text("@\(owner)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                let allSelected = viewModel.selection.count == post.items.count
                Button(allSelected ? "Niets selecteren" : "Alles selecteren") {
                    allSelected ? viewModel.deselectAll() : viewModel.selectAll()
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(post.items.enumerated()), id: \.element.id) { index, item in
                    MediaTile(item: item, index: index + 1, isSelected: viewModel.selection.contains(item.id))
                        .onTapGesture { viewModel.toggle(item) }
                }
            }

            Button {
                viewModel.downloadSelected()
            } label: {
                Label("Download \(viewModel.selection.count) van \(post.items.count)",
                      systemImage: "square.and.arrow.down.on.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.selection.isEmpty)
        }
    }
}

private struct MediaTile: View {
    let item: MediaItem
    let index: Int
    let isSelected: Bool

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AsyncImage(url: item.thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: item.kind == .video ? "video" : "photo")
                            .foregroundStyle(.secondary)
                    default:
                        ProgressView()
                    }
                }
            }
            .clipped()
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .white)
                    .background(Circle().fill(.black.opacity(0.25)))
                    .padding(6)
            }
            .overlay(alignment: .topLeading) {
                Text("\(index)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.45)))
                    .padding(6)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    if item.kind == .video {
                        Image(systemName: "play.fill")
                    }
                    if item.bestWidth > 0 {
                        Text("\(item.bestWidth)×\(item.bestHeight)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.45)))
                .padding(6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(isSelected ? 1 : 0.6)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.kind == .video ? "Video" : "Foto") \(index)")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
