//
//  ShelfItemView.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import SwiftUI
import AppKit

struct ShelfView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    private let spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: 12) {
            FileShareView()
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 130)
                .environmentObject(vm)
            panel
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
        }
        // Bind Quick Look to shelf selection
        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
        }
        .quickLookPresenter(using: quickLookService)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
    }
    
    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }
        
        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }
        
        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    var panel: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                vm.dragDetectorTargeting
                    ? Color.accentColor.opacity(0.9)
                    : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                content
                    .padding()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
            .onTapGesture { selection.clear() }
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)
                    
                    Text("Drop files here")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
            } else {
                GeometryReader { geo in
                    ScrollViewReader { proxy in
                        ZStack {
                            ScrollView(.horizontal) {
                                HStack(spacing: spacing) {
                                    ForEach(Array(tvm.items.enumerated()), id: \.element.id) { index, item in
                                        ShelfItemView(item: item)
                                            .environmentObject(quickLookService)
                                            .id(index)
                                    }
                                }
                                .padding(.horizontal, 2)
                            }
                            .scrollIndicators(.never)
                            .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                                handleDrop(providers: providers)
                            }

                            if isOverflowing(availableWidth: geo.size.width) {
                                HStack {
                                    scrollArrow(systemName: "chevron.left") {
                                        scroll(proxy: proxy, to: 0)
                                    }
                                    Spacer()
                                    scrollArrow(systemName: "chevron.right") {
                                        scroll(proxy: proxy, to: tvm.items.count - 1)
                                    }
                                }
                                .padding(.horizontal, -4)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }

    /// Width taken by each shelf item (105 content + 5pt horizontal padding on each side).
    private let itemWidth: CGFloat = 115

    private func isOverflowing(availableWidth: CGFloat) -> Bool {
        guard tvm.items.count > 1 else { return false }
        let contentWidth = CGFloat(tvm.items.count) * itemWidth
            + CGFloat(tvm.items.count - 1) * spacing
        return contentWidth > availableWidth
    }

    private func scroll(proxy: ScrollViewProxy, to index: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(index, anchor: .center)
        }
    }

    @ViewBuilder
    private func scrollArrow(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 20, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                )
        }
        .buttonStyle(.plain)
    }
}
