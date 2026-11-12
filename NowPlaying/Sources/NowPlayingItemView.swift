//
//  NowPlayingItemView.swift
//  Pock
//
//  Created by Pierluigi Galdi on 17/02/2019.
//  Copyright © 2019 Pierluigi Galdi. All rights reserved.
//

import Foundation
import AppKit
import PockKit

extension String {
    func truncate(length: Int, trailing: String = "…") -> String {
        return self.count > length ? String(self.prefix(length)) + trailing : self
    }
}

class NowPlayingItemView: PKDetailView {
    
    /// Overrideable
    public var didTap: (() -> Void)?
    public var didSwipeLeft: (() -> Void)?
    public var didSwipeRight: (() -> Void)?
    public var didLongPress: (() -> Void)?
    
    /// Data
    private var nowPLayingItem: NowPlayingItem?
	
	/// `PKDetailView.updateConstraint()` adds new constraints every time it's called (i.e. on every text change)
	private var didSetUpConstraints: Bool = false
	
    override func didLoad() {
		canScrollTitle = true
		canScrollSubtitle = true
        titleView.numberOfLoop = 3
        subtitleView.numberOfLoop = 1
		updateUIState(for: nil)
        super.didLoad()
    }
	
	internal func updateUIState(for item: NowPlayingItem?) {
		self.nowPLayingItem = item
		defer {
			updateForNowPlayingState()
		}
		guard let item = self.nowPLayingItem, let client = item.client else {
			let appBundleIdentifier: String = Preferences[.defaultPlayer]
			imageView.image = NSWorkspace.shared.applicationIcon(for: appBundleIdentifier, fallbackFileType: "mp3")
			if maxWidth != 160 {
				maxWidth = 160
			}
			updateText(NSWorkspace.shared.applicationName(for: appBundleIdentifier), in: titleView)
			subtitleView.isHidden = true
			return
		}
		// MARK: Artwork
		let image = item.artwork ?? client.icon
		if imageView.image !== image {
			imageView.image = image
		}
		// TODO: Localize hardcoded strings
		// MARK: Title
		var title = item.title ?? (item.artist == nil ? client.displayName : "Missing title") ?? "Missing title"
		if title.isEmpty {
			title = "Missing title"
		}
		updateText(title, in: titleView)
		
		// MARK: Subtitle
		if let subtitle = item.artist ?? (item.title != nil ? client.displayName : nil), subtitle.isEmpty == false {
			subtitleView.isHidden = false
			updateText(subtitle, in: subtitleView)
		} else {
			subtitleView.isHidden = true
		}
	}
	
	/// Setting a text restarts its scrolling animation and re-computes the layout: skip it if unchanged
	private func updateText(_ text: String?, in textView: ScrollingTextView) {
		guard textView.text as String? != (text ?? "") else {
			return
		}
		if textView === titleView {
			set(title: text)
		} else {
			set(subtitle: text)
		}
	}
    
    private func updateForNowPlayingState() {
        if Preferences[.animateIconWhilePlaying], self.nowPLayingItem?.isPlaying ?? false {
			// Restarting it on every update makes the icon jump (key used by `PKDetailView`)
			guard isAnimating == false || imageView.layer?.animation(forKey: "kBounceAnimationKey") == nil else {
				return
			}
			self.startBounceAnimation()
        }else {
            self.stopBounceAnimation()
        }
    }
    
    override open func didTapHandler() {
        self.didTap?()
    }
    
    override open func didSwipeLeftHandler() {
		if Preferences[.invertSwipeGesture] {
			self.didSwipeRight?()
		}else {
			self.didSwipeLeft?()
		}
    }
    
    override open func didSwipeRightHandler() {
		if Preferences[.invertSwipeGesture] {
			self.didSwipeLeft?()
		}else {
			self.didSwipeRight?()
		}
    }
    
    override func didLongPressHandler() {
        self.didLongPress?()
    }
	
	override func updateConstraint() {
		if didSetUpConstraints == false {
			super.updateConstraint()
			didSetUpConstraints = contentContainer != nil
		}
		guard let constraint = contentContainer?.constraints.first(where: { $0.identifier == "contentContainer.width" }) else {
			return
		}
		if Preferences[.fixedWidth], maxWidth > 0 {
			// Fixed width: always occupy `maxWidth`, regardless of the current title/artist length
			constraint.constant = maxWidth
		} else {
			constraint.constant = maxWidth > 0 ? min(maxWidth, contentWidth) : contentWidth
		}
	}
	
	override func removeFromSuperview() {
		super.removeFromSuperview()
		self.stopBounceAnimation()
	}
	
	override func viewDidMoveToSuperview() {
		super.viewDidMoveToSuperview()
		// Also called on removal: don't restart animations on a detached view
		guard superview != nil else {
			return
		}
		self.updateUIState(for: nowPLayingItem)
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		if window == nil {
			// `ScrollingTextView` stops scrolling (after `numberOfLoop` loops) only while drawing:
			// off screen, or once removed, its timer would keep firing forever
			titleView.speed = 0
			subtitleView.speed = 0
		} else {
			// Restart scrolling (if needed) and the bounce animation
			set(title: titleView.text as String?)
			set(subtitle: subtitleView.text as String?)
			updateForNowPlayingState()
		}
	}

}
