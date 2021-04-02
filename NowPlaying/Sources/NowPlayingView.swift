//
//  NowPlayingView.swift
//  Pock
//
//  Created by Pierluigi Galdi on 14/12/2019.
//  Copyright © 2019 Pierluigi Galdi. All rights reserved.
//

import PockKit
import Defaults

fileprivate let playIconName  = NSImage.touchBarPlayTemplateName
fileprivate let pauseIconName = NSImage.touchBarPauseTemplateName
fileprivate let previousIcon = NSImage(named: NSImage.touchBarRewindTemplateName)!
fileprivate let nextIcon     = NSImage(named: NSImage.touchBarFastForwardTemplateName)!

fileprivate extension NSButton {
	static func build(image: NSImage, target: Any?, action: Selector?) -> NSButton {
		let button = NSButton(image: image, target: target, action: action)
		button.imageScaling = .scaleProportionallyDown
		button.bezelStyle = .circular
		button.bezelColor = .red
		button.isBordered = false
		button.width(18)
		return button
	}
}

class NowPlayingView: PKView {
    
    /// UI
    private let stackView: NSStackView = NSStackView(frame: .zero)
    
    /// Contents UI
    private var itemView:        NowPlayingItemView?
    private var playPauseButton: NSButton?
    private var previousButton:  NSButton {
		return NSButton.build(image: previousIcon, target: self, action: #selector(skipToPreviousItem))
    }
    private var nextButton: NSButton {
		return NSButton.build(image: nextIcon, target: self, action: #selector(skipToNextItem))
    }
    
    /// Core
    private var shouldHideWidget: Bool {
        if Defaults[.hideNowPlayingIfNoMedia] {
            return item?.client == nil
        }
        return false
    }
    
    /// Styles
    public var style: NowPlayingWidgetStyle {
		return Defaults[.nowPlayingWidgetStyle]
    }
    
    /// Data
	private var helper: NowPlayingHelper?
	public var item: NowPlayingItem? {
		return NowPlayingHelper.currentNowPlayingItem
	}
	
	deinit {
		NSLog("[NOW_PLAYING]: NowPlayingView - deinit")
		itemView?.removeFromSuperview()
		itemView = nil
		subviews.forEach({ $0.removeFromSuperview() })
		helper = nil
		NotificationCenter.default.removeObserver(self)
	}
    
	/// Notifications
	private func registerForNotifications() {
		NotificationCenter.default.addObserver(self,
											   selector: #selector(_updateContentViews),
											   name: NowPlayingHelper.kNowPlayingItemDidChange,
											   object: nil
		)
		NotificationCenter.default.addObserver(self,
											   selector: #selector(_configureUIElements),
											   name: .didChangeNowPlayingWidgetStyle,
											   object: nil
		)
	}
	
    /// Overrides
    override init(frame frameRect: NSRect) {
		super.init(frame: NSRect(x: 0, y: 0, width: frameRect.width, height: 30))
		self.configureStackView()
        self.configureUIElements()
		self.registerForNotifications()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.configureStackView()
        self.configureUIElements()
		self.registerForNotifications()
    }
	
	convenience init(frame: NSRect, shouldLoadHelper: Bool) {
		self.init(frame: frame)
		if shouldLoadHelper {
			self.helper = NowPlayingHelper()
		}
	}
    
    /// Configuration
    private func configureStackView() {
		stackView.orientation = .horizontal
		stackView.alignment = .centerY
        stackView.distribution = .fillProportionally
        addSubview(stackView)
		stackView.edgesToSuperview()
    }
    
	@objc private func _configureUIElements() {
		DispatchQueue.main.async { [weak self] in
			self?.configureUIElements()
		}
	}
	private func configureUIElements() {
        removeArrangedSubviews()
		defer {
			addArrangedSubviews()
			reloadNowPlayingData()
		}
        switch style {
        case .default, .onlyInfo:
            guard itemView == nil else {
				break
			}
			itemView = NowPlayingItemView(leftToRight: true)
            setupGestureHandlers()
        case .playPause:
            guard playPauseButton == nil else {
				break
			}
            let icon = NSImage(named: item?.isPlaying ?? false ? pauseIconName : playIconName)!
			playPauseButton = NSButton.build(image: icon, target: self, action: #selector(togglePlayPause))
        }
    }
    
    private func removeArrangedSubviews() {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        playPauseButton = nil
        itemView        = nil
    }
    
    private func addArrangedSubviews() {
        guard !shouldHideWidget else {
            return
        }
        let views: [NSView]
        switch style {
        case .default:
            views = [previousButton, itemView!, nextButton]
			stackView.spacing = 8
        case .onlyInfo:
            views = [itemView!]
			stackView.spacing = 0
        case .playPause:
            views = [previousButton, playPauseButton!, nextButton]
			stackView.spacing = 22
        }
        for view in views {
            stackView.addArrangedSubview(view)
        }
    }
    
    private func setupGestureHandlers() {
        switch self.style {
        case .playPause:
            itemView?.didTap        = nil
            itemView?.didSwipeLeft  = nil
            itemView?.didSwipeRight = nil
        case .default, .onlyInfo:
            itemView?.didTap        = { [unowned self] in self.togglePlayPause()    }
            itemView?.didSwipeLeft  = { [unowned self] in self.skipToPreviousItem() }
            itemView?.didSwipeRight = { [unowned self] in self.skipToNextItem()     }
        }
    }
    
    /// Update
	@objc private func _updateContentViews() {
		DispatchQueue.main.async { [weak self] in
			self?.updateContentViews()
		}
	}
    internal func updateContentViews() {
        guard !shouldHideWidget else {
            removeArrangedSubviews()
            return
        }
        if stackView.arrangedSubviews.isEmpty {
            configureUIElements()
        }
        switch style {
        case .default, .onlyInfo:
			itemView?.updateUIState(for: item)
        case .playPause:
            playPauseButton?.image = NSImage(named: item?.isPlaying ?? false ? pauseIconName : playIconName)!
        }
    }
	internal func reloadNowPlayingData(async: Bool = false) {
		if async {
			DispatchQueue.main.async { [weak self] in
				self?.itemView?.updateUIState(for: self?.item)
			}
		} else {
			itemView?.updateUIState(for: item)
		}
	}
    
    /// Handlers
    @objc private func togglePlayPause() {
		helper?.togglePlayingState()
    }
    
    @objc private func skipToNextItem() {
        helper?.skipToNextTrack()
    }
    
    @objc private func skipToPreviousItem() {
        helper?.skipToPreviousTrack()
    }
    
    override func didLongPressHandler() {
		guard let id = item?.client?.bundleIdentifier() else {
            return
        }
        NSWorkspace.shared.launchApplication(
            withBundleIdentifier: id,
            options: [],
            additionalEventParamDescriptor: nil,
            launchIdentifier: nil
        )
    }
    
}
