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
		let icon: NSImage?
		/// App to control/launch (web players report a helper process, with the browser as parent)
		var applicationBundleIdentifier: String? {
			return parentApplicationBundleIdentifier ?? bundleIdentifier
		}
	}
    /// Data
    public var client: Client!
	public var title: String?
    public var album: String?
	public var artist: String?
	public var artwork:	NSImage?
	/// Identifier of the track `artwork` belongs to (see `trackIdentifier`)
	public var artworkTrackIdentifier: String?
    public var isPlaying: Bool = false
	/// Compound
	public var trackIdentifier: String? {
		guard title != nil || artist != nil || album != nil else {
			return nil
		}
		return [title, artist, album].map({ $0 ?? "" }).joined(separator: "\u{1F}")
	}
	public var searchTerm: String? {
		guard let title = title else {
			return nil
		}
		let term = artist.map({ "\(title) \($0)" }) ?? title
		// `&`, `+`, `=`, `#` (e.g. "Simon & Garfunkel") must be escaped, or they break the query
		return term.addingPercentEncoding(withAllowedCharacters: NowPlayingItem.searchTermAllowedCharacters)?.replacingOccurrences(of: "%20", with: "+")
	}
	private static let searchTermAllowedCharacters: CharacterSet = {
		var characters = CharacterSet.urlQueryAllowed
		characters.remove(charactersIn: "&+=#?")
		return characters
	}()
}
