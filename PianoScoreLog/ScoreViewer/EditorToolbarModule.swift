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
            .frame(height: 52)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)

            if state.activeDrawingTool == .sticker {
                Divider()
                StickerTrayView(state: state)
            }
        }
        .background(
            BlurView(style: .systemChromeMaterial, bottomCornerRadius: 16)
        )
        .overlay(alignment: .bottom) {
            Divider()
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

    static func dismantleUIViewController(_ uiViewController: EditorToolbarViewController, coordinator: ()) {
        uiViewController.dismissPresentedIfNeeded()
    }
}

private final class EditorToolbarViewController: UIViewController, UIPopoverPresentationControllerDelegate {
    private var state: ScoreEditorState?
    private var onRequestOpenPanel: (() -> Void)?
    private var onDone: (() -> Void)?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let pageLabel = UILabel()
    private let iconScale: CGFloat = 0.7
    private var observationVersion = 0

    private var buttonToTool: [UIButton: DrawingTool] = [:]
    private var toolButtons: [DrawingTool: UIButton] = [:]
    private var buttonToFeature: [UIButton: PianologFeature] = [:]
    private var featureButtons: [PianologFeature: UIButton] = [:]
    private let visibleTools: [DrawingTool] = [.pen, .pencil, .highlighter, .eraser, .sticker, .postit, .text, .ruler]
    private let unimplementedTools: Set<DrawingTool> = [.postit, .ruler]
    private let visibleFeatures: [PianologFeature] = [.appleScore, .metronome, .recording]

    private var homeButton = UIButton(type: .system)
    private var prevButton = UIButton(type: .system)
    private var nextButton = UIButton(type: .system)
    private var layerButton = UIButton(type: .system)
    private var undoButton = UIButton(type: .system)
    private var redoButton = UIButton(type: .system)
    private var doneButton = UIButton(type: .system)
    private var photoImportButton = UIButton(type: .system)
    private var pageContainerWidthConstraint: NSLayoutConstraint?

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

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.bounces = true
        view.addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 2
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
    }

    private func setupControls() {
        configureIconButton(homeButton, symbol: PianologFeature.home.symbol, size: 18 * iconScale, action: #selector(handleHome))
        stack.addArrangedSubview(homeButton)

        configureIconButton(prevButton, symbol: "chevron.left", size: 24 * iconScale, action: #selector(handlePrev))
        stack.addArrangedSubview(prevButton)

        pageLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        pageLabel.textColor = .label
        pageLabel.textAlignment = .center
        pageLabel.lineBreakMode = .byClipping
        pageLabel.adjustsFontSizeToFitWidth = true
        pageLabel.minimumScaleFactor = 0.7
        let pageContainer = UIView()
        pageContainer.translatesAutoresizingMaskIntoConstraints = false
        pageContainerWidthConstraint = pageContainer.widthAnchor.constraint(equalToConstant: 50)
        pageContainerWidthConstraint?.isActive = true
        pageContainer.heightAnchor.constraint(equalToConstant: 24).isActive = true
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.addSubview(pageLabel)
        NSLayoutConstraint.activate([
            pageLabel.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
            pageLabel.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
            pageLabel.topAnchor.constraint(equalTo: pageContainer.topAnchor),
            pageLabel.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor)
        ])
        stack.addArrangedSubview(pageContainer)

        configureIconButton(nextButton, symbol: "chevron.right", size: 24 * iconScale, action: #selector(handleNext))
        stack.addArrangedSubview(nextButton)
        stack.setCustomSpacing(0, after: prevButton)
        stack.setCustomSpacing(0, after: pageContainer)

        configureIconButton(layerButton, symbol: "square.stack.3d.up", size: 18 * iconScale, action: #selector(handleLayer))
        stack.addArrangedSubview(layerButton)

        for tool in visibleTools {
            let button = UIButton(type: .system)
            configureIconButton(button, symbol: tool.symbol, size: 19 * iconScale, action: #selector(handleTool(_:)))
            buttonToTool[button] = tool
            toolButtons[tool] = button
            stack.addArrangedSubview(button)

            if tool == .text {
                configureIconButton(photoImportButton, symbol: PianologFeature.photoImport.symbol, size: 19 * iconScale, action: #selector(handleFeature(_:)))
                buttonToFeature[photoImportButton] = .photoImport
                featureButtons[.photoImport] = photoImportButton
                stack.addArrangedSubview(photoImportButton)
            }
        }

        configureIconButton(undoButton, symbol: "arrow.uturn.backward", size: 18 * iconScale, action: #selector(handleUndo))
        configureIconButton(redoButton, symbol: "arrow.uturn.forward", size: 18 * iconScale, action: #selector(handleRedo))
        stack.addArrangedSubview(undoButton)
        stack.addArrangedSubview(redoButton)

        for feature in visibleFeatures {
            let button = UIButton(type: .system)
            configureIconButton(button, symbol: feature.symbol, size: 19 * iconScale, action: #selector(handleFeature(_:)))
            buttonToFeature[button] = feature
            featureButtons[feature] = button
            stack.addArrangedSubview(button)
        }

        configureIconButton(doneButton, symbol: "arrow.up.left.and.arrow.down.right", size: 18 * iconScale, action: #selector(handleDone))
        stack.addArrangedSubview(doneButton)
    }

    private func configureIconButton(_ button: UIButton, symbol: String, size: CGFloat, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.tintColor = .label
        button.setImage(
            UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .regular)),
            for: .normal
        )
        button.addTarget(self, action: action, for: .touchUpInside)
        button.addInteraction(UIPointerInteraction(delegate: nil))
    }

    private func refreshUI() {
        guard isViewLoaded, let state else { return }
        let current = min(state.currentPageIndex + 1, max(state.pageCount, 1))
        let pageText = "\(current)/\(max(state.pageCount, 1))"
        pageLabel.text = pageText
        let measured = (pageText as NSString).size(withAttributes: [.font: pageLabel.font as Any]).width
        pageContainerWidthConstraint?.constant = min(82, max(44, ceil(measured + 8)))
        prevButton.isEnabled = state.currentPageIndex > 0
        nextButton.isEnabled = state.currentPageIndex < max(0, state.pageCount - 1)

        for (tool, button) in toolButtons {
            let isActive = state.activeDrawingTool == tool
            let isUnimplemented = unimplementedTools.contains(tool)
            button.isEnabled = !isUnimplemented
            button.alpha = isUnimplemented ? 0.4 : 1.0
            let weight: UIImage.SymbolWeight = isActive ? .bold : .regular
            let baseImage = UIImage(
                systemName: tool.symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 19 * iconScale, weight: weight)
            )
            let symbolColor: UIColor
            if isActive, [.pen, .pencil, .highlighter].contains(tool) {
                symbolColor = UIColor(state.selectedDrawingColor)
            } else if isActive {
                symbolColor = .systemBlue
            } else {
                symbolColor = .label
            }
            button.setImage(baseImage?.withTintColor(symbolColor, renderingMode: .alwaysOriginal), for: .normal)
            button.tintColor = .label
        }

        for (_, button) in featureButtons {
            button.tintColor = .label
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

    @objc private func handleTool(_ sender: UIButton) {
        guard let state, let tool = buttonToTool[sender] else { return }
        guard !unimplementedTools.contains(tool) else { return }
        if state.activeDrawingTool == tool {
            if toolSupportsOptions(tool) {
                presentToolOptions(tool: tool, sourceView: sender)
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
            presentToolOptions(tool: tool, sourceView: sender)
        }
    }

    @objc private func handleLayer() {
        guard let state else { return }
        state.isLayerPanelPresented = true
        let host = UIHostingController(rootView: LayerManagerPopover(state: state))
        host.modalPresentationStyle = .popover
        host.preferredContentSize = CGSize(width: 340, height: 360)
        if let popover = host.popoverPresentationController {
            popover.sourceView = layerButton
            popover.sourceRect = layerButton.bounds
            popover.permittedArrowDirections = .up
            popover.delegate = self
        }
        present(host, animated: true)
    }

    @objc private func handleUndo() {
        state?.undoTrigger += 1
    }

    @objc private func handleRedo() {
        state?.redoTrigger += 1
    }

    @objc private func handleFeature(_ sender: UIButton) {
        guard buttonToFeature[sender] != nil else { return }
        refreshUI()
    }

    @objc private func handleDone() {
        onDone?()
    }

    private func toolSupportsOptions(_ tool: DrawingTool) -> Bool {
        [.pen, .pencil, .highlighter, .eraser].contains(tool)
    }

    private func presentToolOptions(tool: DrawingTool, sourceView: UIView) {
        guard let state else { return }
        let options = DrawingToolOptionsPopoverView(state: state, tool: tool)
        let host = UIHostingController(rootView: options.padding())
        host.modalPresentationStyle = .popover
        host.preferredContentSize = tool == .eraser ? CGSize(width: 250, height: 150) : CGSize(width: 300, height: 190)
        if let popover = host.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
            popover.permittedArrowDirections = .up
            popover.delegate = self
        }
        present(host, animated: true)
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
