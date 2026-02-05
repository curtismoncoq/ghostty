import AppKit
import SwiftUI

class QuickTerminalWindow: NSPanel {
    // Both of these must be true for windows without decorations to be able to
    // still become key/main and receive events.
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }

    /// This is set to the frame prior to setting `contentView`. This is purely a hack to workaround
    /// bugs in older macOS versions (Ventura): https://github.com/ghostty-org/ghostty/pull/8026
    var initialFrame: NSRect? = nil

    // MARK: - Tab Key Equivalents / Accessory

    /// The key equivalent label for tab switching.
    var keyEquivalent: String? = nil {
        didSet {
            guard let keyEquivalent else {
                keyEquivalentLabel.attributedStringValue = NSAttributedString()
                return
            }

            keyEquivalentLabel.attributedStringValue = NSAttributedString(
                string: "\(keyEquivalent) ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: isKeyWindow ? NSColor.labelColor : NSColor.secondaryLabelColor,
                ])
        }
    }

    private lazy var keyEquivalentLabel: NSTextField = {
        let label = NSTextField(labelWithAttributedString: NSAttributedString())
        label.setContentCompressionResistancePriority(.windowSizeStayPut, for: .horizontal)
        label.postsFrameChangedNotifications = true
        return label
    }()

    /// Set to true if a surface is currently zoomed to show the reset zoom button.
    var surfaceIsZoomed: Bool = false {
        didSet {
            resetZoomTabButton.isHidden = !surfaceIsZoomed
        }
    }

    private lazy var resetZoomTabButton: NSButton = generateResetZoomButton()

    override func awakeFromNib() {
        super.awakeFromNib()

        // Note: almost all of this stuff can be done in the nib/xib directly
        // but I prefer to do it programmatically because the properties we
        // care about are less hidden.

        // Add a custom identifier so third party apps can use the Accessibility
        // API to apply special rules to the quick terminal.
        self.identifier = .init(rawValue: "com.mitchellh.ghostty.quickTerminal")

        // Set the correct AXSubrole of kAXFloatingWindowSubrole (allows
        // AeroSpace to treat the Quick Terminal as a floating window)
        self.setAccessibilitySubrole(.floatingWindow)

        // We don't want to activate the owning app when quick terminal is triggered.
        self.styleMask.insert(.nonactivatingPanel)
        // Keep the quick terminal visible when the app deactivates (alt-tab).
        self.hidesOnDeactivate = false

        // Enable tabbing by default (hidden titlebar style will disable it).
        self.tabbingMode = .preferred
        DispatchQueue.main.async {
            self.tabbingMode = .automatic
        }

        hideWindowButtonsAndProxyIcon()

        // Setup the accessory view for tabs that shows keyboard shortcuts, etc.
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.setHuggingPriority(.defaultHigh, for: .horizontal)
        stackView.spacing = 4
        stackView.alignment = .centerY
        stackView.addArrangedSubview(keyEquivalentLabel)
        stackView.addArrangedSubview(resetZoomTabButton)
        tab.accessoryView = stackView

        resetZoomTabButton.target = terminalController
    }

    override func becomeKey() {
        super.becomeKey()
        resetZoomTabButton.contentTintColor = .controlAccentColor
    }

    override func resignKey() {
        super.resignKey()
        resetZoomTabButton.contentTintColor = .secondaryLabelColor
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        // Upon first adding this Window to its host view, older SwiftUI
        // seems to have a "hiccup" and corrupts the frameRect,
        // sometimes setting the size to zero, sometimes corrupting it.
        // If we find we have cached the "initial" frame, use that instead
        // the propagated one through the framework
        //
        // https://github.com/ghostty-org/ghostty/pull/8026
        super.setFrame(initialFrame ?? frameRect, display: flag)
    }

    /// Apply the borderless style used when quick-terminal-decoration is disabled.
    func applyBorderlessStyle() {
        // Preserve the current frame so style changes don't resize the window.
        let currentFrame = frame

        styleMask.remove(.titled)
        styleMask.remove(.fullSizeContentView)
        titleVisibility = .visible
        titlebarAppearsTransparent = false
        styleMask.insert(.nonactivatingPanel)

        hideWindowButtonsAndProxyIcon()
        setFrame(currentFrame, display: isVisible)
    }

    /// Called by the controller when the focused surface updates.
    func syncAppearance(_ surfaceConfig: Ghostty.SurfaceView.DerivedConfig) {
        // Default no-op. Subclasses override for titlebar styling.
    }

    override var title: String {
        didSet {
            // Updating the title can reveal the titlebar in newer macOS versions,
            // so we re-hide buttons/proxy icon to keep it consistent.
            hideWindowButtonsAndProxyIcon()
        }
    }

    // MARK: - Helpers

    /// The quick terminal controller owning this window, if any.
    var terminalController: BaseTerminalController? {
        windowController as? BaseTerminalController
    }

    func hideWindowButtonsAndProxyIcon() {
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        standardWindowButton(.documentIconButton)?.isHidden = true

        // Ensure we never show a proxy icon for the quick terminal.
        representedURL = nil
    }

    private func generateResetZoomButton() -> NSButton {
        let button = NSButton()
        button.isHidden = true
        button.target = terminalController
        button.action = #selector(BaseTerminalController.splitZoom(_:))
        button.isBordered = false
        button.allowsExpansionToolTips = true
        button.toolTip = "Reset Zoom"
        button.contentTintColor = isKeyWindow ? .controlAccentColor : .secondaryLabelColor
        button.state = .on
        button.image = NSImage(named: "ResetZoom")
        button.frame = NSRect(x: 0, y: 0, width: 20, height: 20)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 20).isActive = true
        button.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return button
    }

    // Find the NSTextField responsible for displaying the titlebar's title.
    private var titlebarTextField: NSTextField? {
        titlebarContainer?
            .firstDescendant(withClassName: "NSTitlebarView")?
            .firstDescendant(withClassName: "NSTextField") as? NSTextField
    }

    // Used to set the titlebar font.
    var titlebarFont: NSFont? {
        didSet {
            let font = titlebarFont ?? NSFont.titleBarFont(ofSize: NSFont.systemFontSize)
            titlebarTextField?.font = font
        }
    }

    // Return a styled representation of our title property.
    var attributedTitle: NSAttributedString? {
        guard let titlebarFont = titlebarFont else { return nil }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: titlebarFont,
            .foregroundColor: isKeyWindow ? NSColor.labelColor : NSColor.secondaryLabelColor,
        ]
        return NSAttributedString(string: title, attributes: attributes)
    }

    var titlebarContainer: NSView? {
        // If we aren't fullscreen then the titlebar container is part of our window.
        if !styleMask.contains(.fullScreen) {
            return contentView?.firstViewFromRoot(withClassName: "NSTitlebarContainerView")
        }

        // If we are fullscreen, the titlebar container view is part of a separate
        // "fullscreen window", we need to find the window and then get the view.
        for window in NSApplication.shared.windows {
            // This is the private window class that contains the toolbar
            guard window.className == "NSToolbarFullScreenWindow" else { continue }

            // The parent will match our window. This is used to filter the correct
            // fullscreen window if we have multiple.
            guard window.parent == self else { continue }

            return window.contentView?.firstViewFromRoot(withClassName: "NSTitlebarContainerView")
        }

        return nil
    }

    /// The preferred window background color, derived from the focused surface if possible.
    var preferredBackgroundColor: NSColor? {
        if let terminalController, !terminalController.surfaceTree.isEmpty {
            let surface: Ghostty.SurfaceView?

            if let focusedSurface = terminalController.focusedSurface,
               let treeRoot = terminalController.surfaceTree.root,
               let focusedNode = treeRoot.node(view: focusedSurface),
               treeRoot.spatial().doesBorder(side: .up, from: focusedNode) {
                surface = focusedSurface
            } else {
                surface = terminalController.surfaceTree.root?.leftmostLeaf()
            }

            if let surface {
                let backgroundColor = surface.backgroundColor ?? surface.derivedConfig.backgroundColor
                let alpha = surface.derivedConfig.backgroundOpacity.clamped(to: 0.001...1)
                return NSColor(backgroundColor).withAlphaComponent(alpha)
            }
        }

        if let appDelegate = NSApp.delegate as? AppDelegate {
            let config = appDelegate.ghostty.config
            let alpha = config.backgroundOpacity.clamped(to: 0.001...1)
            return NSColor(config.backgroundColor).withAlphaComponent(alpha)
        }

        return nil
    }

    // MARK: - Tab Bar Identification

    /// This identifier is attached to the tab bar view controller when we detect it being added.
    static let tabBarIdentifier: NSUserInterfaceItemIdentifier = .init("_ghosttyTabBar")

    func isTabBar(_ childViewController: NSTitlebarAccessoryViewController) -> Bool {
        if childViewController.identifier == nil {
            if childViewController.view.contains(className: "NSTabBar") {
                return true
            }

            if childViewController.layoutAttribute == .bottom &&
                childViewController.view.className == "NSView" &&
                childViewController.view.subviews.isEmpty {
                return true
            }

            return false
        }

        return childViewController.identifier == Self.tabBarIdentifier
    }
}

// MARK: - Hidden Titlebar

class HiddenTitlebarQuickTerminalWindow: QuickTerminalWindow {
    override func awakeFromNib() {
        super.awakeFromNib()

        reapplyHiddenStyle()

        // Ensure the base class doesn't re-enable tabbing asynchronously.
        DispatchQueue.main.async { [weak self] in
            self?.tabbingMode = .disallowed
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fullscreenDidExit(_:)),
            name: .fullscreenDidExit,
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private static let hiddenStyleMask: NSWindow.StyleMask = [
        .titled,
        .fullSizeContentView,
        .resizable,
        .closable,
        .miniaturizable,
        .nonactivatingPanel,
    ]

    private func reapplyHiddenStyle() {
        if terminalController?.fullscreenStyle?.isFullscreen ?? false {
            return
        }

        if styleMask.contains(.fullScreen) {
            styleMask = Self.hiddenStyleMask.union([.fullScreen])
        } else {
            styleMask = Self.hiddenStyleMask
        }

        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        hideWindowButtonsAndProxyIcon()

        tabbingMode = .disallowed

        if let themeFrame = contentView?.superview,
           let titleBarContainer = themeFrame.firstDescendant(withClassName: "NSTitlebarContainerView") {
            titleBarContainer.isHidden = true
        }
    }

    // We override this so that the titlebar area is not draggable.
    override var contentLayoutRect: CGRect {
        var rect = super.contentLayoutRect
        rect.origin.y = 0
        rect.size.height = self.frame.height
        return rect
    }

    override var title: String {
        didSet {
            reapplyHiddenStyle()
        }
    }

    @objc private func fullscreenDidExit(_ notification: Notification) {
        guard let fullscreen = notification.object as? FullscreenBase else { return }
        guard fullscreen.window == self else { return }
        reapplyHiddenStyle()
    }
}

// MARK: - Transparent Titlebar

class TransparentTitlebarQuickTerminalWindow: QuickTerminalWindow {
    private var lastSurfaceConfig: Ghostty.SurfaceView.DerivedConfig?

    private var tabGroupWindowsObservation: NSKeyValueObservation?
    private var tabBarVisibleObservation: NSKeyValueObservation?

    deinit {
        tabGroupWindowsObservation?.invalidate()
        tabBarVisibleObservation?.invalidate()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        setupKVO()
    }

    override func becomeMain() {
        super.becomeMain()

        guard let lastSurfaceConfig else { return }
        syncAppearance(lastSurfaceConfig)

        if tabGroup?.windows.count ?? 0 == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
                self?.syncAppearance(self?.lastSurfaceConfig ?? lastSurfaceConfig)
            }
        }
    }

    override func update() {
        super.update()

        if #unavailable(macOS 26) {
            if !effectViewIsHidden {
                hideEffectView()
            }
        }
    }

    override func syncAppearance(_ surfaceConfig: Ghostty.SurfaceView.DerivedConfig) {
        super.syncAppearance(surfaceConfig)

        if let preferredBackgroundColor {
            appearance = (preferredBackgroundColor.isLightColor
                ? NSAppearance(named: .aqua)
                : NSAppearance(named: .darkAqua))
        }

        lastSurfaceConfig = surfaceConfig
        setupKVO()

        if #available(macOS 26.0, *) {
            syncAppearanceTahoe(surfaceConfig)
        } else {
            syncAppearanceVentura(surfaceConfig)
        }
    }

    @available(macOS 26.0, *)
    private func syncAppearanceTahoe(_ surfaceConfig: Ghostty.SurfaceView.DerivedConfig) {
        if let titlebarView = titlebarContainer?.firstDescendant(withClassName: "NSTitlebarView") {
            titlebarView.wantsLayer = true

            let isGlassStyle = surfaceConfig.backgroundBlur.isGlassStyle
            titlebarView.layer?.backgroundColor = isGlassStyle
                ? NSColor.clear.cgColor
                : preferredBackgroundColor?.cgColor
        }

        titlebarBackgroundView?.isHidden = true
    }

    @available(macOS 13.0, *)
    private func syncAppearanceVentura(_ surfaceConfig: Ghostty.SurfaceView.DerivedConfig) {
        guard let titlebarContainer else { return }

        titlebarContainer.wantsLayer = true
        titlebarContainer.layer?.backgroundColor = preferredBackgroundColor?.cgColor

        effectViewIsHidden = false
        titlebarAppearsTransparent = true
    }

    private var titlebarBackgroundView: NSView? {
        titlebarContainer?.firstDescendant(withClassName: "NSTitlebarBackgroundView")
    }

    private func setupKVO() {
        setupTabGroupObservation()
        setupTabBarVisibleObservation()
    }

    private func setupTabGroupObservation() {
        tabGroupWindowsObservation?.invalidate()
        tabGroupWindowsObservation = nil

        guard let tabGroup else { return }

        tabGroupWindowsObservation = tabGroup.observe(
            \.windows,
             options: [.new]
        ) { [weak self] _, _ in
            guard let self else { return }
            guard let lastSurfaceConfig else { return }
            self.syncAppearance(lastSurfaceConfig)
        }
    }

    private func setupTabBarVisibleObservation() {
        tabBarVisibleObservation?.invalidate()
        tabBarVisibleObservation = nil

        tabBarVisibleObservation = tabGroup?.observe(
            \.isTabBarVisible,
             options: [.new]
        ) { [weak self] _, _ in
            guard let self else { return }
            guard let lastSurfaceConfig else { return }
            self.syncAppearance(lastSurfaceConfig)
        }
    }

    private var effectViewIsHidden = false

    private func hideEffectView() {
        guard !effectViewIsHidden else { return }

        if let effectView = titlebarContainer?.descendants(withClassName: "NSVisualEffectView").first {
            effectView.isHidden = true
        }

        effectViewIsHidden = true
    }
}

// MARK: - Titlebar Tabs (Ventura)

class TitlebarTabsVenturaQuickTerminalWindow: QuickTerminalWindow {
    fileprivate var isLightTheme: Bool = false

    lazy var titlebarColor: NSColor = backgroundColor {
        didSet {
            guard let titlebarContainer else { return }
            titlebarContainer.wantsLayer = true
            titlebarContainer.layer?.backgroundColor = titlebarColor.cgColor
        }
    }

    private var hasWindowButtons: Bool {
        let closeIsHidden = standardWindowButton(.closeButton)?.isHiddenOrHasHiddenAncestor ?? true
        let miniaturizeIsHidden = standardWindowButton(.miniaturizeButton)?.isHiddenOrHasHiddenAncestor ?? true
        let zoomIsHidden = standardWindowButton(.zoomButton)?.isHiddenOrHasHiddenAncestor ?? true
        return !(closeIsHidden && miniaturizeIsHidden && zoomIsHidden)
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        titlebarTabs = true

        let surfaceConfig = resolveSurfaceConfig()
        backgroundColor = NSColor(surfaceConfig.backgroundColor)
        titlebarColor = NSColor(surfaceConfig.backgroundColor)
            .withAlphaComponent(surfaceConfig.backgroundOpacity)
    }

    private var effectViewIsHidden = false

    override func becomeKey() {
        if let tabGroup = self.tabGroup, tabGroup.windows.count < 2 {
            resetCustomTabBarViews()
        }

        super.becomeKey()

        updateNewTabButtonOpacity()
        resetZoomToolbarButton.contentTintColor = .controlAccentColor
        tab.attributedTitle = attributedTitle
    }

    override func resignKey() {
        super.resignKey()

        updateNewTabButtonOpacity()
        resetZoomToolbarButton.contentTintColor = .tertiaryLabelColor
        tab.attributedTitle = attributedTitle
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()

        guard titlebarTabs else { return }
        updateTabsForVeryDarkBackgrounds()
    }

    override func update() {
        super.update()

        if titlebarTabs {
            updateTabsForVeryDarkBackgrounds()
            if let index = windowController?.window?.tabbedWindows?.firstIndex(of: self) {
                windowButtonsBackdrop?.isHighlighted = index == 0
            }
        }

        titlebarSeparatorStyle = tabbedWindows != nil && !titlebarTabs ? .line : .none
        if titlebarTabs {
            hideToolbarOverflowButton()
            hideTitleBarSeparators()
        }

        if !effectViewIsHidden {
            if let effectView = titlebarContainer?.descendants(withClassName: "NSVisualEffectView").first {
                effectView.isHidden = titlebarTabs || !titlebarTabs && !hasVeryDarkBackground
            }

            effectViewIsHidden = true
        }

        updateNewTabButtonOpacity()
        updateNewTabButtonImage()
    }

    override func updateConstraintsIfNeeded() {
        super.updateConstraintsIfNeeded()

        if titlebarTabs {
            hideToolbarOverflowButton()
            hideTitleBarSeparators()
        }
    }

    override func mergeAllWindows(_ sender: Any?) {
        super.mergeAllWindows(sender)

        if let controller = self.windowController as? QuickTerminalController {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { controller.relabelTabs() }
        }
    }

    override func syncAppearance(_ surfaceConfig: Ghostty.SurfaceView.DerivedConfig) {
        super.syncAppearance(surfaceConfig)

        if let preferredBackgroundColor {
            appearance = (preferredBackgroundColor.isLightColor
                ? NSAppearance(named: .aqua)
                : NSAppearance(named: .darkAqua))
        }

        let themeChanged = isLightTheme != OSColor(surfaceConfig.backgroundColor).isLightColor
        isLightTheme = OSColor(surfaceConfig.backgroundColor).isLightColor

        if let preferredBackgroundColor {
            titlebarColor = preferredBackgroundColor
        } else {
            titlebarColor = NSColor(surfaceConfig.backgroundColor)
                .withAlphaComponent(surfaceConfig.backgroundOpacity)
        }

        if (isOpaque || themeChanged) {
            updateTabBar()
        }
    }

    var hasVeryDarkBackground: Bool {
        backgroundColor.luminance < 0.05
    }

    private var newTabButtonImageLayer: VibrantLayer? = nil

    func updateTabBar() {
        newTabButtonImageLayer = nil
        effectViewIsHidden = false

        if titlebarTabs && styleMask.contains(.titled) {
            guard let tabBarAccessoryViewController = titlebarAccessoryViewControllers.first(where: { $0.identifier == Self.tabBarIdentifier}) else { return }
            tabBarAccessoryViewController.layoutAttribute = .right
            pushTabsToTitlebar(tabBarAccessoryViewController)
        }
    }

    private func updateNewTabButtonOpacity() {
        guard let newTabButton: NSButton = titlebarContainer?.firstDescendant(withClassName: "NSTabBarNewTabButton") as? NSButton else { return }
        guard let newTabButtonImageView = newTabButton.firstDescendant(withClassName: "NSImageView") as? NSImageView else { return }

        newTabButtonImageView.alphaValue = isKeyWindow ? 1 : 0.5
    }

    private func updateNewTabButtonImage() {
        guard let newTabButton: NSButton = titlebarContainer?.firstDescendant(withClassName: "NSTabBarNewTabButton") as? NSButton else { return }
        guard let newTabButtonImageView = newTabButton.firstDescendant(withClassName: "NSImageView") as? NSImageView else { return }
        guard let newTabButtonImage = newTabButtonImageView.image else { return }

        let imageLayer = newTabButtonImageLayer ?? VibrantLayer(forAppearance: isLightTheme ? .light : .dark)!
        imageLayer.frame = NSRect(origin: NSPoint(x: newTabButton.bounds.midX - newTabButtonImage.size.width / 2,
                                                  y: newTabButton.bounds.midY - newTabButtonImage.size.height / 2),
                                  size: newTabButtonImage.size)
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.opacity = 0.5

        newTabButtonImageLayer = imageLayer

        newTabButton.layer?.sublayers?.first(where: { $0.className == "VibrantLayer" })?.removeFromSuperlayer()
        newTabButton.layer?.addSublayer(newTabButtonImageLayer!)
    }

    private func updateTabsForVeryDarkBackgrounds() {
        guard hasVeryDarkBackground else { return }
        guard let titlebarContainer else { return }

        if let tabGroup = tabGroup, tabGroup.isTabBarVisible {
            guard let activeTabBackgroundView = titlebarContainer.firstDescendant(withClassName: "NSTabButton")?.superview?.subviews.last?.firstDescendant(withID: "_backgroundView")
            else { return }

            activeTabBackgroundView.layer?.backgroundColor = titlebarColor.cgColor
            titlebarContainer.layer?.backgroundColor = titlebarColor.highlight(withLevel: 0.14)?.cgColor
        } else {
            titlebarContainer.layer?.backgroundColor = titlebarColor.cgColor
        }
    }

    private lazy var resetZoomToolbarButton: NSButton = generateResetZoomButton()

    private func generateResetZoomButton() -> NSButton {
        let button = NSButton()
        button.target = nil
        button.action = #selector(BaseTerminalController.splitZoom(_:))
        button.isBordered = false
        button.allowsExpansionToolTips = true
        button.toolTip = "Reset Zoom"
        button.contentTintColor = .controlAccentColor
        button.state = .on
        button.image = NSImage(named: "ResetZoom")
        button.frame = NSRect(x: 0, y: 0, width: 20, height: 20)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 20).isActive = true
        button.heightAnchor.constraint(equalToConstant: 20).isActive = true

        return button
    }

    @objc private func selectTabAndZoom(_ sender: NSButton) {
        guard let tabGroup else { return }

        guard let associatedWindow = tabGroup.windows.first(where: {
            guard let accessoryView = $0.tab.accessoryView else { return false }
            return accessoryView.subviews.contains(sender)
        }),
              let windowController = associatedWindow.windowController as? BaseTerminalController
        else { return }

        tabGroup.selectedWindow = associatedWindow
        windowController.splitZoom(self)
    }

    override var titlebarFont: NSFont? {
        didSet {
            guard let toolbar = toolbar as? TerminalToolbar else { return }
            toolbar.titleFont = titlebarFont ?? .titleBarFont(ofSize: NSFont.systemFontSize)
        }
    }

    private var windowButtonsBackdrop: WindowButtonsBackdropView? = nil
    private var windowDragHandle: WindowDragView? = nil

    var titlebarTabs = false {
        didSet {
            self.titleVisibility = titlebarTabs ? .hidden : .visible
            if titlebarTabs {
                generateToolbar()
            } else {
                toolbar = nil
            }
        }
    }

    override var title: String {
        didSet {
            titleVisibility = .hidden
            if let toolbar = toolbar as? TerminalToolbar {
                toolbar.titleText = title
            }
            hideWindowButtonsAndProxyIcon()
        }
    }

    func generateToolbar() {
        let terminalToolbar = TerminalToolbar(identifier: "Toolbar")

        toolbar = terminalToolbar
        toolbarStyle = .unifiedCompact
        if let resetZoomItem = terminalToolbar.items.first(where: { $0.itemIdentifier == .resetZoom }) {
            resetZoomItem.view = resetZoomToolbarButton
            resetZoomItem.view!.removeConstraints(resetZoomItem.view!.constraints)
            resetZoomItem.view!.widthAnchor.constraint(equalToConstant: 22).isActive = true
            resetZoomItem.view!.heightAnchor.constraint(equalToConstant: 20).isActive = true
        }
    }

    private func hideTitleBarSeparators() {
        guard let titlebarContainer else { return }
        for v in titlebarContainer.descendants(withClassName: "NSTitlebarSeparatorView") {
            v.isHidden = true
        }
    }

    private func hideToolbarOverflowButton() {
        guard let windowButtonsBackdrop = windowButtonsBackdrop else { return }
        guard let titlebarView = windowButtonsBackdrop.superview else { return }
        guard titlebarView.className == "NSTitlebarView" else { return }
        guard let toolbarView = titlebarView.subviews.first(where: {
            $0.className == "NSToolbarView"
        }) else { return }

        toolbarView.subviews.first(where: { $0.className == "NSToolbarClippedItemsIndicatorViewer" })?.isHidden = true
    }

    override func addTitlebarAccessoryViewController(_ childViewController: NSTitlebarAccessoryViewController) {
        let isTabBar = self.titlebarTabs && isTabBar(childViewController)

        if (isTabBar) {
            childViewController.layoutAttribute = .right
            titleVisibility = .hidden
            childViewController.identifier = Self.tabBarIdentifier
        }

        super.addTitlebarAccessoryViewController(childViewController)

        if (isTabBar) {
            pushTabsToTitlebar(childViewController)
        }
    }

    override func removeTitlebarAccessoryViewController(at index: Int) {
        let isTabBar = titlebarAccessoryViewControllers[index].identifier == Self.tabBarIdentifier
        super.removeTitlebarAccessoryViewController(at: index)
        if (isTabBar) {
            resetCustomTabBarViews()
        }
    }

    private func resetCustomTabBarViews() {
        windowButtonsBackdrop?.isHidden = true
        windowDragHandle?.isHidden = true

        if let toolbar = toolbar as? TerminalToolbar {
            toolbar.titleIsHidden = false
        }
    }

    private func pushTabsToTitlebar(_ tabBarController: NSTitlebarAccessoryViewController) {
        if (toolbar == nil) {
            generateToolbar()
        }

        if let toolbar = toolbar as? TerminalToolbar {
            toolbar.titleIsHidden = true
        }

        DispatchQueue.main.async { [weak self] in
            let accessoryView = tabBarController.view
            guard let accessoryClipView = accessoryView.superview else { return }
            guard let titlebarView = accessoryClipView.superview else { return }
            guard titlebarView.className == "NSTitlebarView" else { return }
            guard let toolbarView = titlebarView.subviews.first(where: {
                $0.className == "NSToolbarView"
            }) else { return }

            self?.addWindowButtonsBackdrop(titlebarView: titlebarView, toolbarView: toolbarView)
            guard let windowButtonsBackdrop = self?.windowButtonsBackdrop else { return }

            self?.addWindowDragHandle(titlebarView: titlebarView, toolbarView: toolbarView)

            accessoryClipView.translatesAutoresizingMaskIntoConstraints = false
            accessoryClipView.leftAnchor.constraint(equalTo: windowButtonsBackdrop.rightAnchor).isActive = true
            accessoryClipView.rightAnchor.constraint(equalTo: toolbarView.rightAnchor).isActive = true
            accessoryClipView.topAnchor.constraint(equalTo: toolbarView.topAnchor).isActive = true
            accessoryClipView.heightAnchor.constraint(equalTo: toolbarView.heightAnchor).isActive = true
            accessoryClipView.needsLayout = true

            accessoryView.translatesAutoresizingMaskIntoConstraints = false
            accessoryView.leftAnchor.constraint(equalTo: accessoryClipView.leftAnchor).isActive = true
            accessoryView.rightAnchor.constraint(equalTo: accessoryClipView.rightAnchor).isActive = true
            accessoryView.topAnchor.constraint(equalTo: accessoryClipView.topAnchor).isActive = true
            accessoryView.heightAnchor.constraint(equalTo: accessoryClipView.heightAnchor).isActive = true
            accessoryView.needsLayout = true

            self?.hideToolbarOverflowButton()
            self?.hideTitleBarSeparators()
        }
    }

    private func addWindowButtonsBackdrop(titlebarView: NSView, toolbarView: NSView) {
        guard windowButtonsBackdrop?.superview != titlebarView else {
            return
        }
        windowButtonsBackdrop?.removeFromSuperview()
        windowButtonsBackdrop = nil

        let view = WindowButtonsBackdropView(window: self)
        view.identifier = NSUserInterfaceItemIdentifier("_windowButtonsBackdrop")
        titlebarView.addSubview(view)

        view.translatesAutoresizingMaskIntoConstraints = false
        view.leftAnchor.constraint(equalTo: toolbarView.leftAnchor).isActive = true
        view.rightAnchor.constraint(equalTo: toolbarView.leftAnchor, constant: hasWindowButtons ? 78 : 0).isActive = true
        view.topAnchor.constraint(equalTo: toolbarView.topAnchor).isActive = true
        view.heightAnchor.constraint(equalTo: toolbarView.heightAnchor).isActive = true

        windowButtonsBackdrop = view
    }

    private func addWindowDragHandle(titlebarView: NSView, toolbarView: NSView) {
        guard windowDragHandle?.superview != titlebarView.superview else {
            return
        }
        windowDragHandle?.removeFromSuperview()

        let view = WindowDragView()
        view.identifier = NSUserInterfaceItemIdentifier("_windowDragHandle")
        titlebarView.superview?.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.leftAnchor.constraint(equalTo: toolbarView.leftAnchor).isActive = true
        view.rightAnchor.constraint(equalTo: toolbarView.rightAnchor).isActive = true
        view.topAnchor.constraint(equalTo: toolbarView.topAnchor).isActive = true
        view.bottomAnchor.constraint(equalTo: toolbarView.topAnchor, constant: 12).isActive = true

        windowDragHandle = view
    }

    private func resolveSurfaceConfig() -> Ghostty.SurfaceView.DerivedConfig {
        if let terminalController {
            if let focusedSurface = terminalController.focusedSurface {
                return focusedSurface.derivedConfig
            }
            if let surface = terminalController.surfaceTree.root?.leftmostLeaf() {
                return surface.derivedConfig
            }
        }

        if let appDelegate = NSApp.delegate as? AppDelegate {
            return Ghostty.SurfaceView.DerivedConfig(appDelegate.ghostty.config)
        }

        return Ghostty.SurfaceView.DerivedConfig()
    }
}

fileprivate class WindowDragView: NSView {
    override public func mouseDown(with event: NSEvent) {
        if (event.type == .leftMouseDown && event.clickCount == 1) {
            window?.performDrag(with: event)
            NSCursor.closedHand.set()
        } else {
            super.mouseDown(with: event)
        }
    }

    override public func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        window?.disableCursorRects()
        NSCursor.openHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        window?.enableCursorRects()
        NSCursor.arrow.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

fileprivate class WindowButtonsBackdropView: NSView {
    private weak var terminalWindow: TitlebarTabsVenturaQuickTerminalWindow?
    private var isLightTheme: Bool {
        terminalWindow?.isLightTheme ?? false
    }
    private let overlayLayer = VibrantLayer()

    var isHighlighted: Bool = true {
        didSet {
            guard let terminalWindow else { return }

            if isLightTheme {
                overlayLayer.isHidden = isHighlighted
                layer?.backgroundColor = .clear
            } else {
                let systemOverlayColor = NSColor(cgColor: CGColor(genericGrayGamma2_2Gray: 0.0, alpha: 0.45))!
                let titlebarBackgroundColor = terminalWindow.titlebarColor.blended(withFraction: 1, of: systemOverlayColor)

                let highlightedColor = terminalWindow.hasVeryDarkBackground ? terminalWindow.backgroundColor : .clear
                let backgroundColor = terminalWindow.hasVeryDarkBackground ? titlebarBackgroundColor : systemOverlayColor

                overlayLayer.isHidden = true
                layer?.backgroundColor = isHighlighted ? highlightedColor?.cgColor : backgroundColor?.cgColor
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(window: TitlebarTabsVenturaQuickTerminalWindow) {
        self.terminalWindow = window
        super.init(frame: .zero)

        wantsLayer = true

        overlayLayer.frame = layer!.bounds
        overlayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        overlayLayer.backgroundColor = CGColor(genericGrayGamma2_2Gray: 0.95, alpha: 1)

        layer?.addSublayer(overlayLayer)
    }
}

fileprivate class TerminalToolbar: NSToolbar, NSToolbarDelegate {
    private let titleTextField = CenteredDynamicLabel(labelWithString: "👻 Ghostty")

    var titleText: String {
        get {
            titleTextField.stringValue
        }

        set {
            titleTextField.stringValue = newValue
        }
    }

    var titleFont: NSFont? {
        get {
            titleTextField.font
        }

        set {
            titleTextField.font = newValue
        }
    }

    var titleIsHidden: Bool {
        get {
            titleTextField.isHidden
        }

        set {
            titleTextField.isHidden = newValue
        }
    }

    override init(identifier: NSToolbar.Identifier) {
        super.init(identifier: identifier)

        delegate = self
        centeredItemIdentifiers.insert(.titleText)
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        var item: NSToolbarItem

        switch itemIdentifier {
        case .titleText:
            item = NSToolbarItem(itemIdentifier: .titleText)
            item.view = self.titleTextField
            item.visibilityPriority = .user

            self.titleTextField.translatesAutoresizingMaskIntoConstraints = false
            self.titleTextField.setContentHuggingPriority(.defaultLow, for: .horizontal)
            self.titleTextField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

            NSLayoutConstraint.activate([
                self.titleTextField.heightAnchor.constraint(equalToConstant: 22),
            ])

            item.isEnabled = true
        case .resetZoom:
            item = NSToolbarItem(itemIdentifier: .resetZoom)
        default:
            item = NSToolbarItem(itemIdentifier: itemIdentifier)
        }

        return item
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.titleText, .flexibleSpace, .space, .resetZoom]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.flexibleSpace, .titleText, .flexibleSpace]
    }
}

fileprivate class CenteredDynamicLabel: NSTextField {
    override func viewDidMoveToSuperview() {
        isEditable = false
        isBordered = false
        drawsBackground = false
        alignment = .center
        lineBreakMode = .byTruncatingTail
        cell?.truncatesLastVisibleLine = true

        translatesAutoresizingMaskIntoConstraints = false

        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let attributedString = self.attributedStringValue.mutableCopy() as? NSMutableAttributedString else {
            super.draw(dirtyRect)
            return
        }

        let textSize = attributedString.size()

        let yOffset = (self.bounds.height - textSize.height) / 2 - 1

        let centeredRect = NSRect(x: self.bounds.origin.x, y: self.bounds.origin.y + yOffset,
                                  width: self.bounds.width, height: textSize.height)

        attributedString.draw(in: centeredRect)
    }
}

// MARK: - Titlebar Tabs (Tahoe)

class TitlebarTabsTahoeQuickTerminalWindow: TransparentTitlebarQuickTerminalWindow, NSToolbarDelegate {
    private var viewModel = ViewModel()

    deinit {
        tabBarObserver = nil
    }

    override var titlebarFont: NSFont? {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.viewModel.titleFont = self.titlebarFont
            }
        }
    }

    override var title: String {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.viewModel.title = self.title
            }
            hideWindowButtonsAndProxyIcon()
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        titleVisibility = .hidden

        let toolbar = NSToolbar(identifier: "TerminalToolbar")
        toolbar.delegate = self
        toolbar.centeredItemIdentifiers.insert(.title)
        self.toolbar = toolbar
        toolbarStyle = .unifiedCompact
    }

    override func becomeMain() {
        super.becomeMain()

        setupTabBar()
        viewModel.isMainWindow = true
    }

    override func becomeKey() {
        super.becomeKey()
        setupTabBar()
    }

    override func resignMain() {
        super.resignMain()
        viewModel.isMainWindow = false
    }

    override func sendEvent(_ event: NSEvent) {
        guard viewModel.hasTabBar else {
            super.sendEvent(event)
            return
        }

        let isRightClick =
            event.type == .rightMouseDown ||
            (event.type == .otherMouseDown && event.buttonNumber == 2) ||
            (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        guard isRightClick else {
            super.sendEvent(event)
            return
        }

        guard let tabBarView else {
            super.sendEvent(event)
            return
        }

        let locationInTabBar = tabBarView.convert(event.locationInWindow, from: nil)
        guard tabBarView.bounds.contains(locationInTabBar) else {
            super.sendEvent(event)
            return
        }

        tabBarView.rightMouseDown(with: event)
    }

    override func addTitlebarAccessoryViewController(_ childViewController: NSTitlebarAccessoryViewController) {
        guard isTabBar(childViewController) else {
            viewModel.hasTabBar = false

            super.addTitlebarAccessoryViewController(childViewController)
            return
        }

        tabBarObserver = nil

        childViewController.layoutAttribute = .right

        super.addTitlebarAccessoryViewController(childViewController)

        DispatchQueue.main.async {
            self.setupTabBar()
        }
    }

    override func removeTitlebarAccessoryViewController(at index: Int) {
        guard let childViewController = titlebarAccessoryViewControllers[safe: index],
                isTabBar(childViewController) else {
            super.removeTitlebarAccessoryViewController(at: index)
            return
        }

        super.removeTitlebarAccessoryViewController(at: index)

        removeTabBar()
    }

    private var tabBarObserver: NSObjectProtocol? {
        didSet {
            guard let oldValue else { return }
            NotificationCenter.default.removeObserver(oldValue)
        }
    }

    func setupTabBar() {
        guard tabBarObserver == nil else { return }

        guard
            let titlebarView,
            let tabBarView = self.tabBarView
        else { return }

        DispatchQueue.main.async { [weak self] in
            self?.viewModel.hasTabBar = true
        }

        guard let clipView = tabBarView.firstSuperview(withClassName: "NSTitlebarAccessoryClipView") else { return }
        guard let accessoryView = clipView.subviews[safe: 0] else { return }
        guard let toolbarView = titlebarView.firstDescendant(withClassName: "NSToolbarView") else { return }

        guard let newTabButton = titlebarView.firstDescendant(withClassName: "NSTabBarNewTabButton") else { return }
        tabBarView.frame.size.height = newTabButton.frame.width

        let container = toolbarView

        let leftPadding: CGFloat = 0

        clipView.translatesAutoresizingMaskIntoConstraints = false
        accessoryView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            clipView.leftAnchor.constraint(equalTo: container.leftAnchor, constant: leftPadding),
            clipView.rightAnchor.constraint(equalTo: container.rightAnchor),
            clipView.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            clipView.heightAnchor.constraint(equalTo: container.heightAnchor),
            accessoryView.leftAnchor.constraint(equalTo: clipView.leftAnchor),
            accessoryView.rightAnchor.constraint(equalTo: clipView.rightAnchor),
            accessoryView.topAnchor.constraint(equalTo: clipView.topAnchor),
            accessoryView.heightAnchor.constraint(equalTo: clipView.heightAnchor),
        ])

        clipView.needsLayout = true
        accessoryView.needsLayout = true

        tabBarView.postsFrameChangedNotifications = true
        tabBarObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: tabBarView,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.tabBarObserver = nil

            DispatchQueue.main.async {
                self.setupTabBar()
            }
        }
    }

    func removeTabBar() {
        DispatchQueue.main.async {
            self.viewModel.hasTabBar = false
        }

        tabBarObserver = nil
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.title, .flexibleSpace, .space]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.flexibleSpace, .title, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .title:
            let item = NSToolbarItem(itemIdentifier: .title)
            item.view = NSHostingView(rootView: TitleItem(viewModel: viewModel))
            item.view?.setContentCompressionResistancePriority(.required, for: .horizontal)
            item.visibilityPriority = .user
            item.isEnabled = true
            item.isBordered = false

            return item
        default:
            return NSToolbarItem(itemIdentifier: itemIdentifier)
        }
    }

    class ViewModel: ObservableObject {
        @Published var titleFont: NSFont?
        @Published var title: String = "👻 Ghostty"
        @Published var hasTabBar: Bool = false
        @Published var isMainWindow: Bool = true
    }
}

extension TitlebarTabsTahoeQuickTerminalWindow {
    struct TitleItem: View {
        @ObservedObject var viewModel: ViewModel

        var title: String {
            return viewModel.title.isEmpty ? " " : viewModel.title
        }

        var body: some View {
            if !viewModel.hasTabBar {
                titleText
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }

        @ViewBuilder
        var titleText: some View {
            Text(title)
                .font(viewModel.titleFont.flatMap(Font.init(_:)))
                .foregroundStyle(viewModel.isMainWindow ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .greatestFiniteMagnitude, alignment: .center)
                .opacity(viewModel.hasTabBar ? 0 : 1)
        }
    }
}
