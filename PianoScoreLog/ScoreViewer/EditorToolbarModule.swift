import SwiftUI
import Observation
#if os(iOS)
import UIKit

struct EditorTopBarOverlay: View {
    @Bindable var state: ScoreEditorState
    let onRequestOpenPanel: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbarRepresentable(
                state: state,
                onRequestOpenPanel: onRequestOpenPanel,
                onDone: onDone
            )
            .frame(maxWidth: .infinity)

            if state.activeDrawingTool == .sticker {
                Divider()
                StickerTrayView(state: state)
            }
        }
    }
}

private struct EditorToolbarRepresentable: UIViewControllerRepresentable {
    @Bindable var state: ScoreEditorState
    let onRequestOpenPanel: () -> Void
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> EditorToolbarViewController {
        let controller = EditorToolbarViewController()
        controller.apply(state: state, onRequestOpenPanel: onRequestOpenPanel, onDone: onDone)
        return controller
    }

    func updateUIViewController(_ uiViewController: EditorToolbarViewController, context: Context) {
        uiViewController.apply(state: state, onRequestOpenPanel: onRequestOpenPanel, onDone: onDone)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: EditorToolbarViewController, context: Context) -> CGSize? {
        let fallbackWidth = uiViewController.view.window?.windowScene?.screen.bounds.width
            ?? max(uiViewController.view.bounds.width, 1024)
        let width = proposal.width ?? fallbackWidth
        let height = uiViewController.preferredToolbarHeight(for: width)
        return CGSize(width: width, height: height)
    }

    static func dismantleUIViewController(_ uiViewController: EditorToolbarViewController, coordinator: ()) {
        uiViewController.dismissPresentedIfNeeded()
    }
}

private final class EditorToolbarViewController: UIViewController, UIPopoverPresentationControllerDelegate {
    private var state: ScoreEditorState?
    private var onRequestOpenPanel: (() -> Void)?
    private var onDone: (() -> Void)?

    private let toolbar = UIToolbar()
    private var observationVersion = 0

    private var toolItems: [DrawingTool: UIBarButtonItem] = [:]
    private var featureItems: [PianologFeature: UIBarButtonItem] = [:]
    private let visibleTools: [DrawingTool] = [.pen, .pencil, .highlighter, .eraser, .sticker, .text, .ruler]
    private let unimplementedTools: Set<DrawingTool> = [.postit, .ruler]
    private let visibleFeatures: [PianologFeature] = [.metronome, .recording]

    private let homeItem = UIBarButtonItem()
    private let layerItem = UIBarButtonItem()
    private let undoItem = UIBarButtonItem()
    private let redoItem = UIBarButtonItem()
    private let photoImportItem = UIBarButtonItem()
    private let gestureItem = UIBarButtonItem()
    private let doneItem = UIBarButtonItem()
    // Page navigation
    private let pagePrevItem = UIBarButtonItem()
    private let pageCountItem = UIBarButtonItem()
    private var pageCountButton: UIButton?
    private let pageNextItem = UIBarButtonItem()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupLayout()
        setupControls()
        if let state {
            refreshUI()
            startObservingState(state)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            dismissPresentedIfNeeded()
        }
    }

    func apply(state: ScoreEditorState, onRequestOpenPanel: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.state = state
        self.onRequestOpenPanel = onRequestOpenPanel
        self.onDone = onDone
        guard isViewLoaded else { return }
        refreshUI()
        startObservingState(state)
    }

    func dismissPresentedIfNeeded() {
        guard presentedViewController != nil else { return }
        dismiss(animated: false)
    }

    func preferredToolbarHeight(for width: CGFloat) -> CGFloat {
        let target = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        return toolbar.sizeThatFits(target).height
    }

    private func setupLayout() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private let smallScale = UIImage.SymbolConfiguration(textStyle: .caption2)

    private func setupControls() {
        homeItem.image = UIImage(systemName: PianologFeature.home.symbol, withConfiguration: smallScale)
        homeItem.style = .plain
        homeItem.target = self
        homeItem.action = #selector(handleHome)

        pagePrevItem.image = UIImage(systemName: "chevron.left", withConfiguration: smallScale)
        pagePrevItem.style = .plain
        pagePrevItem.target = self
        pagePrevItem.action = #selector(handlePrev)

        let btn = UIButton(type: .custom)
        btn.titleLabel?.font = UIFont.preferredFont(forTextStyle: .caption2)
        btn.setTitleColor(.label, for: .normal)
        btn.setTitleColor(.tertiaryLabel, for: .highlighted)
        btn.addTarget(self, action: #selector(handlePageCount), for: .touchUpInside)
        pageCountButton = btn
        pageCountItem.customView = btn

        pageNextItem.image = UIImage(systemName: "chevron.right", withConfiguration: smallScale)
        pageNextItem.style = .plain
        pageNextItem.target = self
        pageNextItem.action = #selector(handleNext)

        layerItem.image = UIImage(systemName: "square.stack.3d.up", withConfiguration: smallScale)
        layerItem.style = .plain
        layerItem.target = self
        layerItem.action = #selector(handleLayer)

        for tool in visibleTools {
            let item = UIBarButtonItem(
                image: UIImage(systemName: tool.symbol, withConfiguration: smallScale),
                style: .plain,
                target: self,
                action: #selector(handleToolItem(_:))
            )
            item.isEnabled = !unimplementedTools.contains(tool)
            toolItems[tool] = item
        }

        photoImportItem.image = UIImage(systemName: PianologFeature.photoImport.symbol, withConfiguration: smallScale)
        photoImportItem.style = .plain
        photoImportItem.target = self
        photoImportItem.action = #selector(handleFeatureItem(_:))
        featureItems[.photoImport] = photoImportItem

        undoItem.image = UIImage(systemName: "arrow.uturn.backward", withConfiguration: smallScale)
        undoItem.style = .plain
        undoItem.target = self
        undoItem.action = #selector(handleUndo)

        redoItem.image = UIImage(systemName: "arrow.uturn.forward", withConfiguration: smallScale)
        redoItem.style = .plain
        redoItem.target = self
        redoItem.action = #selector(handleRedo)

        for feature in visibleFeatures {
            let item = UIBarButtonItem(
                image: UIImage(systemName: feature.symbol, withConfiguration: smallScale),
                style: .plain,
                target: self,
                action: #selector(handleFeatureItem(_:))
            )
            featureItems[feature] = item
        }

        gestureItem.image = UIImage(systemName: "hand.tap", withConfiguration: smallScale)
        gestureItem.style = .plain
        gestureItem.target = self
        gestureItem.action = #selector(handleGesture)

        doneItem.image = UIImage(systemName: "arrow.up.left.and.arrow.down.right", withConfiguration: smallScale)
        doneItem.style = .plain
        doneItem.target = self
        doneItem.action = #selector(handleDone)

        applyNavigationItems()
    }

    private func applyNavigationItems() {
        var items: [UIBarButtonItem] = [.flexibleSpace()]
        items += [homeItem, pagePrevItem, pageCountItem, pageNextItem, layerItem]
        items += visibleTools.compactMap { toolItems[$0] }
        if let photo = featureItems[.photoImport] {
            items.append(photo)
        }
        items += [undoItem, redoItem]
        items += visibleFeatures.compactMap { featureItems[$0] }
        items += [gestureItem, doneItem]
        items.append(.flexibleSpace())
        toolbar.setItems(items, animated: false)
    }

    private func refreshUI() {
        guard isViewLoaded, let state else { return }
        pagePrevItem.isEnabled = state.currentPageIndex > 0
        pageNextItem.isEnabled = state.currentPageIndex < max(0, state.pageCount - 1)
        pageCountButton?.setTitle("\(state.currentPageIndex + 1)/\(max(state.pageCount, 1))", for: .normal)
        for (tool, item) in toolItems {
            item.isEnabled = !unimplementedTools.contains(tool)
        }
    }

    @objc private func handleHome() {
        onRequestOpenPanel?()
    }

    @objc private func handlePrev() {
        guard let state else { return }
        guard state.currentPageIndex > 0 else { return }
        state.prevPageTrigger += 1
    }

    @objc private func handleNext() {
        guard let state else { return }
        guard state.currentPageIndex < max(0, state.pageCount - 1) else { return }
        state.nextPageTrigger += 1
    }

    @objc private func handlePageCount() {
        guard let state, let sourceView = pageCountButton else { return }
        let jumpView = PageJumpPopoverView(
            currentPage: state.currentPageIndex + 1,
            totalPages: max(state.pageCount, 1)
        ) { [weak state] page in
            guard let state else { return }
            state.jumpToPageTarget = max(0, min(page - 1, state.pageCount - 1))
            state.jumpToPageTrigger += 1
        }
        let host = UIHostingController(rootView: jumpView)
        host.modalPresentationStyle = .popover
        host.preferredContentSize = CGSize(width: 180, height: 80)
        if let popover = host.popoverPresentationController {
            popover.permittedArrowDirections = [.up, .down]
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
            popover.delegate = self
        }
        if let presented = presentedViewController { presented.dismiss(animated: false) }
        present(host, animated: true)
    }

    @objc private func handleToolItem(_ sender: UIBarButtonItem) {
        guard let state else { return }
        guard let tool = toolItems.first(where: { $0.value === sender })?.key else { return }
        guard !unimplementedTools.contains(tool) else { return }
        if state.activeDrawingTool == tool {
            if toolSupportsOptions(tool) {
                presentToolOptions(tool: tool, sourceItem: sender)
            } else {
                state.activeDrawingTool = nil
            }
            refreshUI()
            return
        }
        state.activeDrawingTool = tool
        if tool == .sticker {
            // Always require explicit symbol pick when entering sticker mode.
            state.selectedStickerSymbolID = nil
        }
        refreshUI()
        if toolSupportsOptions(tool) {
            presentToolOptions(tool: tool, sourceItem: sender)
        }
    }

    @objc private func handleLayer() {
        guard let state else { return }
        state.isLayerPanelPresented = true
        let host = UIHostingController(rootView: LayerManagerPopover(state: state))
        host.modalPresentationStyle = .popover
        host.preferredContentSize = CGSize(width: 340, height: 360)
        if let popover = host.popoverPresentationController {
            popover.permittedArrowDirections = [.up]
            popover.canOverlapSourceViewRect = false
            popover.sourceView = view
            popover.sourceRect = popupAnchorRect(for: layerItem)
            popover.delegate = self
        }
        if let presented = presentedViewController {
            presented.dismiss(animated: false)
        }
        present(host, animated: true)
    }

    @objc private func handleUndo() {
        state?.undoTrigger += 1
    }

    @objc private func handleRedo() {
        state?.redoTrigger += 1
    }

    @objc private func handleFeatureItem(_ sender: UIBarButtonItem) {
        guard featureItems.first(where: { $0.value === sender }) != nil else { return }
        refreshUI()
    }

    @objc private func handleGesture() {}

    @objc private func handleDone() {
        onDone?()
    }

    private func toolSupportsOptions(_ tool: DrawingTool) -> Bool {
        [.pen, .pencil, .highlighter, .eraser].contains(tool)
    }

    private func presentToolOptions(tool: DrawingTool, sourceItem: UIBarButtonItem) {
        guard let state else { return }
        let options = DrawingToolOptionsPopoverView(state: state, tool: tool)
        let host = UIHostingController(rootView: options.padding())
        host.modalPresentationStyle = .popover
        host.preferredContentSize = tool == .eraser ? CGSize(width: 250, height: 150) : CGSize(width: 300, height: 190)
        if let popover = host.popoverPresentationController {
            popover.permittedArrowDirections = [.up]
            popover.canOverlapSourceViewRect = false
            popover.sourceView = view
            popover.sourceRect = popupAnchorRect(for: sourceItem)
            popover.delegate = self
        }
        if let presented = presentedViewController {
            presented.dismiss(animated: false)
        }
        present(host, animated: true)
    }

    private func popupAnchorRect(for item: UIBarButtonItem) -> CGRect {
        guard let itemView = item.value(forKey: "view") as? UIView else {
            return CGRect(x: view.bounds.midX, y: 44, width: 1, height: 1)
        }
        let rect = itemView.convert(itemView.bounds, to: view)
        return CGRect(x: rect.midX, y: rect.maxY + 2, width: 1, height: 1)
    }

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }

    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        state?.isLayerPanelPresented = false
    }

    private func startObservingState(_ state: ScoreEditorState) {
        observationVersion += 1
        let token = observationVersion
        observeStateChanges(state, token: token)
    }

    private func observeStateChanges(_ state: ScoreEditorState, token: Int) {
        withObservationTracking {
            _ = state.currentPageIndex
            _ = state.pageCount
            _ = state.activeDrawingTool
            _ = state.selectedDrawingColor
        } onChange: { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard token == self.observationVersion else { return }
                self.refreshUI()
                self.observeStateChanges(state, token: token)
            }
        }
    }
}
#endif
