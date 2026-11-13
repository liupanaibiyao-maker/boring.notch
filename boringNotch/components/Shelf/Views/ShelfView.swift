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
    private let itemsPerPage = 4
    @State private var currentPage = 0

    var body: some View {
        HStack(spacing: 12) {
            FileShareView()
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 100)
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
            .overlay(alignment: .bottomTrailing) {
                if !tvm.isEmpty {
                    removeAllButton
                        .padding(.trailing, 10)
                        .padding(.bottom, 2)
                }
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
    }

    private var removeAllButton: some View {
        Button(action: removeAllItems) {
            HStack(spacing: 4) {
                Image(systemName: "trash")
                Text("Remove All")
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.65))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Remove All")
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
                    let arrowWidth: CGFloat = pageCount > 1 ? 18 : 0
                    let arrowGap: CGFloat = pageCount > 1 ? 4 : 0
                    let gridWidth = geo.size.width - (arrowWidth + arrowGap) * 2
                    let cellWidth = (gridWidth - spacing) / 2
                    let cellHeight = (geo.size.height - spacing) / 2

                    HStack(spacing: arrowGap) {
                        if pageCount > 1 {
                            scrollArrow(systemName: "chevron.left") {
                                goToPreviousPage()
                            }
                        }
                        if pageCount > 1 {
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 0) {
                                    ForEach(0..<pageCount, id: \.self) { page in
                                        gridPage(
                                            items: items(at: page),
                                            cellWidth: cellWidth,
                                            cellHeight: cellHeight
                                        )
                                        .frame(width: gridWidth, height: geo.size.height)
                                        .id(page)
                                    }
                                }
                                .scrollTargetLayout()
                            }
                            .scrollTargetBehavior(.viewAligned)
                            .scrollPosition(id: scrollPageBinding)
                            .scrollIndicators(.never)
                            .frame(width: gridWidth, height: geo.size.height)
                        } else {
                            gridPage(items: pageItems, cellWidth: cellWidth, cellHeight: cellHeight)
                                .frame(width: gridWidth, height: geo.size.height)
                        }
                        if pageCount > 1 {
                            scrollArrow(systemName: "chevron.right") {
                                goToNextPage()
                            }
                        }
                    }
                    .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                        handleDrop(providers: providers)
                    }
                }
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
            clampCurrentPage()
        }
        .onChange(of: tvm.items.count) {
            clampCurrentPage()
        }
    }

    // MARK: - Paging

    private var pageCount: Int {
        max(1, Int(ceil(Double(tvm.items.count) / Double(itemsPerPage))))
    }

    private var pageItems: [ShelfItem] {
        let start = currentPage * itemsPerPage
        guard start < tvm.items.count else { return [] }
        return Array(tvm.items[start..<min(start + itemsPerPage, tvm.items.count)])
    }

    private var scrollPageBinding: Binding<Int?> {
        Binding(
            get: { currentPage },
            set: { newValue in
                if let newValue { currentPage = newValue }
            }
        )
    }

    private func items(at page: Int) -> [ShelfItem] {
        let start = page * itemsPerPage
        guard start < tvm.items.count else { return [] }
        return Array(tvm.items[start..<min(start + itemsPerPage, tvm.items.count)])
    }

    private func clampCurrentPage() {
        if currentPage >= pageCount {
            currentPage = pageCount - 1
        }
        if currentPage < 0 { currentPage = 0 }
    }

    private func goToNextPage() {
        guard pageCount > 1 else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            currentPage = (currentPage + 1) % pageCount
        }
    }

    private func goToPreviousPage() {
        guard pageCount > 1 else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            currentPage = (currentPage - 1 + pageCount) % pageCount
        }
    }

    private func removeAllItems() {
        selection.clear()
        currentPage = 0
        withAnimation(.easeInOut(duration: 0.15)) {
            tvm.removeAll()
        }
    }

    // MARK: - Grid

    @ViewBuilder
    private func gridPage(items: [ShelfItem], cellWidth: CGFloat, cellHeight: CGFloat) -> some View {
        switch items.count {
        case 0:
            EmptyView()
        case 1:
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                shelfItem(items[0], cellWidth: cellWidth, cellHeight: cellHeight)
                Spacer(minLength: 0)
            }
        case 2:
            HStack(spacing: spacing) {
                ForEach(items) { item in
                    shelfItem(item, cellWidth: cellWidth, cellHeight: cellHeight)
                }
            }
        case 3:
            VStack(spacing: spacing) {
                shelfItem(items[0], cellWidth: cellWidth, cellHeight: cellHeight)
                HStack(spacing: spacing) {
                    shelfItem(items[1], cellWidth: cellWidth, cellHeight: cellHeight)
                    shelfItem(items[2], cellWidth: cellWidth, cellHeight: cellHeight)
                }
            }
        default:
            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    shelfItem(items[0], cellWidth: cellWidth, cellHeight: cellHeight)
                    shelfItem(items[1], cellWidth: cellWidth, cellHeight: cellHeight)
                }
                HStack(spacing: spacing) {
                    shelfItem(items[2], cellWidth: cellWidth, cellHeight: cellHeight)
                    shelfItem(items[3], cellWidth: cellWidth, cellHeight: cellHeight)
                }
            }
        }
    }

    private func shelfItem(_ item: ShelfItem, cellWidth: CGFloat, cellHeight: CGFloat) -> some View {
        ShelfItemView(item: item, cellWidth: cellWidth, cellHeight: cellHeight)
            .id(item.id)
            .environmentObject(quickLookService)
    }

    @ViewBuilder
    private func scrollArrow(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 18, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.black.opacity(0.6))
                )
        }
        .buttonStyle(.plain)
    }
}
