import SwiftUI
import Observation
#if os(iOS)
import UIKit
import CoreText

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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)

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

    private let navigationBar = UINavigationBar()
    private let toolbarNavigationItem = UINavigationItem(title: "")
    private let pageLabel = UILabel()
    private let pagePrevButton = UIButton(type: .system)
    private let pageNextButton = UIButton(type: .system)
    private let iconScale: CGFloat = 0.8
    private let toolbarIconBaseSize: CGFloat = 16
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
    private let overflowItem = UIBarButtonItem()
    private let doneItem = UIBarButtonItem()
    private var pageControlItem: UIBarButtonItem!

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
        return navigationBar.sizeThatFits(target).height
    }

    private func setupLayout() {
        navigationBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigationBar)

        NSLayoutConstraint.activate([
            navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBar.topAnchor.constraint(equalTo: view.topAnchor),
            navigationBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupControls() {
        homeItem.image = symbolImage(PianologFeature.home.symbol, size: toolbarIconBaseSize * iconScale)
        homeItem.style = .plain
        homeItem.target = self
        homeItem.action = #selector(handleHome)

        pageLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        pageLabel.textAlignment = .center
        pageLabel.lineBreakMode = .byClipping
        pageLabel.adjustsFontSizeToFitWidth = false
        let pageContainer = UIStackView()
        pageContainer.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.axis = .horizontal
        pageContainer.alignment = .center
        pageContainer.distribution = .fill
        pageContainer.spacing = 0

        pagePrevButton.translatesAutoresizingMaskIntoConstraints = false
        pagePrevButton.setImage(symbolImage("chevron.left", size: toolbarIconBaseSize * iconScale), for: .normal)
        pagePrevButton.addTarget(self, action: #selector(handlePrev), for: .touchUpInside)

        pageNextButton.translatesAutoresizingMaskIntoConstraints = false
        pageNextButton.setImage(symbolImage("chevron.right", size: toolbarIconBaseSize * iconScale), for: .normal)
        pageNextButton.addTarget(self, action: #selector(handleNext), for: .touchUpInside)

        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.addArrangedSubview(pagePrevButton)
        pageContainer.addArrangedSubview(pageLabel)
        pageContainer.addArrangedSubview(pageNextButton)
        pageControlItem = UIBarButtonItem(customView: pageContainer)

        layerItem.image = symbolImage("square.stack.3d.up", size: toolbarIconBaseSize * iconScale)
        layerItem.style = .plain
        layerItem.target = self
        layerItem.action = #selector(handleLayer)

        for tool in visibleTools {
            let item = UIBarButtonItem(
                image: symbolImage(tool.symbol, size: toolbarIconBaseSize * iconScale),
                style: .plain,
                target: self,
                action: #selector(handleToolItem(_:))
            )
            item.isEnabled = !unimplementedTools.contains(tool)
            toolItems[tool] = item

        }

        photoImportItem.image = symbolImage(PianologFeature.photoImport.symbol, size: toolbarIconBaseSize * iconScale)
        photoImportItem.style = .plain
        photoImportItem.target = self
        photoImportItem.action = #selector(handleFeatureItem(_:))
        featureItems[.photoImport] = photoImportItem

        undoItem.image = symbolImage("arrow.uturn.backward", size: toolbarIconBaseSize * iconScale)
        undoItem.style = .plain
        undoItem.target = self
        undoItem.action = #selector(handleUndo)

        redoItem.image = symbolImage("arrow.uturn.forward", size: toolbarIconBaseSize * iconScale)
        redoItem.style = .plain
        redoItem.target = self
        redoItem.action = #selector(handleRedo)

        for feature in visibleFeatures {
            let item = UIBarButtonItem(
                image: symbolImage(feature.symbol, size: toolbarIconBaseSize * iconScale),
                style: .plain,
                target: self,
                action: #selector(handleFeatureItem(_:))
            )
            featureItems[feature] = item
        }

        gestureItem.image = symbolImage("hand.tap", size: toolbarIconBaseSize * iconScale)
        gestureItem.style = .plain
        gestureItem.target = self
        gestureItem.action = #selector(handleGesture)

        overflowItem.image = symbolImage("ellipsis", size: toolbarIconBaseSize * iconScale)
        overflowItem.style = .plain
        overflowItem.target = self
        overflowItem.action = #selector(handleOverflow)

        doneItem.image = symbolImage("arrow.up.left.and.arrow.down.right", size: toolbarIconBaseSize * iconScale)
        doneItem.style = .plain
        doneItem.target = self
        doneItem.action = #selector(handleDone)

        applyNavigationItems()
    }

    private func applyNavigationItems() {
        var items: [UIBarButtonItem] = [
            homeItem,
            pageControlItem,
            layerItem
        ]
        items += visibleTools.compactMap { toolItems[$0] }
        if let photo = featureItems[.photoImport] {
            items.append(photo)
        }
        items += [undoItem, redoItem]
        items += visibleFeatures.compactMap { featureItems[$0] }
        items.append(gestureItem)
        items.append(overflowItem)

        items.append(doneItem)
        let oneGroup = UIBarButtonItemGroup(barButtonItems: items, representativeItem: nil)
        toolbarNavigationItem.leadingItemGroups = [oneGroup]
        toolbarNavigationItem.trailingItemGroups = []
        navigationBar.setItems([toolbarNavigationItem], animated: false)
    }

    private func refreshUI() {
        guard isViewLoaded, let state else { return }
        let current = min(state.currentPageIndex + 1, max(state.pageCount, 1))
        let pageText = "\(current)/\(max(state.pageCount, 1))"
        pageLabel.text = pageText
        pagePrevButton.isEnabled = state.currentPageIndex > 0
        pageNextButton.isEnabled = state.currentPageIndex < max(0, state.pageCount - 1)
        pagePrevButton.alpha = pagePrevButton.isEnabled ? 1.0 : 0.35
        pageNextButton.alpha = pageNextButton.isEnabled ? 1.0 : 0.35

        for (tool, item) in toolItems {
            let isUnimplemented = unimplementedTools.contains(tool)
            item.isEnabled = !isUnimplemented
            let weight: UIImage.SymbolWeight = .regular
            item.image = UIImage(
                systemName: tool.symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: toolbarIconBaseSize * iconScale, weight: weight)
            )
        }
    }

    private func symbolImage(_ symbol: String, size: CGFloat, weight: UIImage.SymbolWeight = .regular) -> UIImage? {
        UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: weight)
        )
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

    @objc private func handleOverflow() {}

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
