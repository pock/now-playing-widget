//
//  NowPlayingItem.swift
//  Pock
//
//  Created by Pierluigi Galdi on 17/02/2019.
//  Copyright © 2019 Pierluigi Galdi. All rights reserved.
//

import Foundation
import AppKit

class NowPlayingItem {
	/// Info
	struct Client {
		let bundleIdentifier: String?
		let parentApplicationBundleIdentifier: String?
		let displayName: String?
	}
    /// Data
    public var client: Client!
	public var title: String?
    public var album: String?
	public var artist: String?
	public var artwork:	NSImage?
    public var isPlaying: Bool = false
	/// Compound
	public var searchTerm: String? {
		if let title = title {
			if let artist = artist {
				return "\(title) \(artist)".replacingOccurrences(of: " ", with: "+").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
			}
			return title.replacingOccurrences(of: " ", with: "+").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
		}
		return nil
	}
}
