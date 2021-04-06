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
		var title: String = ""
		var artist: String = ""
		guard let item = self.nowPLayingItem, let client = item.client else {
			let appBundleIdentifier: String
			if #available(OSX 10.15, *) {
				appBundleIdentifier = "com.apple.Music"
			} else {
				appBundleIdentifier = "com.apple.iTunes"
			}
			title = "Tap here"
			artist = "To play music"
			if let path = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: appBundleIdentifier) {
				imageView.image = NSWorkspace.shared.icon(forFile: path)
			} else {
				imageView.image = NSWorkspace.shared.icon(forFileType: "mp3")
			}
			maxWidth = 50
			set(title: "Tap here")
			set(subtitle: "To play music")
			return
		}
		/// Now Playing item info
		title  = item.title ?? ""
		artist = item.artist ?? ""
		/// Now playing Client data
		if title.isEmpty {
			title = client.displayName ?? ""
			if title.isEmpty {
				title = "Missing title"
			}
		}
		if artist.isEmpty {
			artist = (title.isEmpty ? (client.parentApplicationBundleIdentifier ?? client.bundleIdentifier) : client.displayName) ?? ""
			if artist.isEmpty {
				artist = "Unknown"
			}
		}
		if let artwork = item.artwork {
			imageView.image = artwork
		} else {
			if let path = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: (client.parentApplicationBundleIdentifier ?? client.bundleIdentifier) ?? "") {
				imageView.image = NSWorkspace.shared.icon(forFile: path)
			} else {
				imageView.image = NSWorkspace.shared.icon(forFileType: "mp3")
			}
		}
		/// Set
		let titleWidth = (title  as NSString).size(withAttributes: titleView.textFontAttributes).width
		let subtitleWidth = (artist as NSString).size(withAttributes: subtitleView.textFontAttributes).width
		maxWidth = min(max(titleWidth, subtitleWidth), 120)
		set(title: title)
		set(subtitle: artist)
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
