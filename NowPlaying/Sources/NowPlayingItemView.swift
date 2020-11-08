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
import Defaults

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
    public var nowPLayingItem: NowPlayingItem? {
        didSet {
            self.updateContent()
        }
    }
    
    override func didLoad() {
        titleView.numberOfLoop    = 3
        subtitleView.numberOfLoop = 1
        super.didLoad()
    }
    
    private func updateContent() {
        
        var appBundleIdentifier: String = self.nowPLayingItem?.appBundleIdentifier ?? ""
        
        switch (appBundleIdentifier) {
        case "com.apple.WebKit.WebContent":
            appBundleIdentifier = "com.apple.Safari"
        default:
            break
        }
        
        DispatchQueue.main.async { [weak self] in
			
			var title  = self?.nowPLayingItem?.title  ?? ""
			var artist = self?.nowPLayingItem?.artist ?? ""
			
			if appBundleIdentifier.isEmpty {
				if #available(OSX 10.15, *) {
					appBundleIdentifier = "com.apple.Music"
				}else {
					appBundleIdentifier = "com.apple.iTunes"
				}
				title  = "Tap here"
				artist = "To play music"
			}else {
				if title.isEmpty && artist.isEmpty {
					let path = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: appBundleIdentifier)
					title  = path?.split(separator: "/").last?.replacingOccurrences(of: ".app", with: "") ?? "Missing title"
					artist = "Unknown artist"
				}
			}
			
			if title.isEmpty {
				title = "Missing title"
			}
			if artist.isEmpty {
				artist = "Unknown artist"
			}
			
			if let artwork = self?.nowPLayingItem?.artwork {
				self?.imageView.image = artwork
			}else {
				if let path = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: appBundleIdentifier) {
					self?.imageView.image = NSWorkspace.shared.icon(forFile: path)
				}else {
					self?.imageView.image = NSWorkspace.shared.icon(forFileType: "mp3")
				}
			}
            
            let titleWidth    = (title  as NSString).size(withAttributes: self?.titleView.textFontAttributes    ?? [:]).width
            let subtitleWidth = (artist as NSString).size(withAttributes: self?.subtitleView.textFontAttributes ?? [:]).width
            self?.maxWidth = min(max(titleWidth, subtitleWidth), 80)
            
            self?.set(title: title)
            self?.set(subtitle: artist)
            
            self?.updateForNowPlayingState()
        }
    }
    
    private func updateForNowPlayingState() {
        if Defaults[.animateIconWhilePlaying], self.nowPLayingItem?.isPlaying ?? false {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: { [weak self] in
                self?.startBounceAnimation()
            })
        }else {
            self.stopBounceAnimation()
        }
    }
    
    override open func didTapHandler() {
        self.didTap?()
    }
    
    override open func didSwipeLeftHandler() {
		if Defaults[.invertSwipeGesture] {
			self.didSwipeRight?()
		}else {
			self.didSwipeLeft?()
		}
    }
    
    override open func didSwipeRightHandler() {
		if Defaults[.invertSwipeGesture] {
			self.didSwipeLeft?()
		}else {
			self.didSwipeRight?()
		}
    }
    
    override func didLongPressHandler() {
        self.didLongPress?()
    }
    
}
