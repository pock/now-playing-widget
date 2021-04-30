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
			let appBundleIdentifier: String
			if #available(OSX 10.15, *) {
				appBundleIdentifier = "com.apple.Music"
			} else {
				appBundleIdentifier = "com.apple.iTunes"
			}
			if let path = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: appBundleIdentifier) {
				imageView.image = NSWorkspace.shared.icon(forFile: path)
			} else {
				imageView.image = NSWorkspace.shared.icon(forFileType: "mp3")
			}
			maxWidth = 50
			set(title: NSWorkspace.shared.applicationName(for: appBundleIdentifier))
			subtitleView.isHidden = true
			return
		}
		// MARK: Artwork
		if let artwork = item.artwork {
			imageView.image = artwork
		} else {
			if let path = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: (client.parentApplicationBundleIdentifier ?? client.bundleIdentifier) ?? "") {
				imageView.image = NSWorkspace.shared.icon(forFile: path)
			} else {
				imageView.image = NSWorkspace.shared.icon(forFileType: "mp3")
			}
		}
		// TODO: Localize hardcoded strings
		// MARK: Title
		var title = item.title ?? (item.artist == nil ? client.displayName : "Missing title") ?? "Missing title"
		if title.isEmpty {
			title = "Missing title"
		}
		let titleWidth = (title as NSString).size(withAttributes: titleView.textFontAttributes).width
		maxWidth = min(titleWidth, 120)
		set(title: title)
		
		// MARK: Subtitle
		if let subtitle = item.artist ?? (item.title != nil ? client.displayName : nil), subtitle.isEmpty == false {
			let subtitleWidth = (subtitle as NSString).size(withAttributes: subtitleView.textFontAttributes).width
			maxWidth = min(max(titleWidth, subtitleWidth), 120)
			subtitleView.isHidden = false
			set(subtitle: subtitle)
		} else {
			subtitleView.isHidden = true
		}
	}
    
    private func updateForNowPlayingState() {
        if Preferences[.animateIconWhilePlaying], self.nowPLayingItem?.isPlaying ?? false {
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
	
	override func removeFromSuperview() {
		super.removeFromSuperview()
		self.stopBounceAnimation()
	}
	
	override func viewDidMoveToSuperview() {
		super.viewDidMoveToSuperview()
		self.updateUIState(for: nowPLayingItem)
	}
    
}
