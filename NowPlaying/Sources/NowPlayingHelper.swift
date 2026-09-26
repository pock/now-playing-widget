//
//  NowPlayingHelper.swift
//  Pock
//
//  Created by Pierluigi Galdi on 17/02/2019.
//  Copyright © 2019 Pierluigi Galdi. All rights reserved.
//

import Foundation
import AppKit

class NowPlayingHelper {
	
	/// Data
	public private(set) var currentNowPlayingItem: NowPlayingItem?
	
	/// Artwork
	private var latestArtworkTask: URLSessionTask?
	private var latestEmbeddedArtworkData: Data?
	/// Player-provided artwork URL used (or being fetched) for the current track; `nil` if the artwork comes from elsewhere
	private var latestArtworkSourceURL: String?
	
	/// Players' icons, by bundle identifier (`NSWorkspace.icon(forFile:)` returns a new image every time)
	private var iconsCache: [String: NSImage] = [:]
	
	/// Adapter (used where MediaRemote doesn't return now playing info to Pock anymore, macOS 15.4+)
	private var adapter: NowPlayingAdapter?
	private var latestAdapterState: NowPlayingAdapterState?
	
	/// `true` when MediaRemote reports a client whose info must not be shown (ignored or not running app)
	private var isCurrentClientSuppressed: Bool = false
	
	/// Ref
	internal weak var view: NowPlayingView?
	
	/// `true` while the widget is in the Touch Bar. The adapter only polls while on screen.
	internal var isOnScreen: Bool = false {
		didSet {
			adapter?.isActive = isOnScreen
		}
	}
	
	internal init(forView: NowPlayingView) {
		NSLog("[NOW_PLAYING]: NowPlayingHelper - init")
		if let _: String = Preferences[.defaultPlayer] {
			// nothing to do here
		} else {
			if #available(OSX 10.15, *) {
				Preferences[.defaultPlayer] = "com.apple.Music"
			} else {
				Preferences[.defaultPlayer] = "com.apple.iTunes"
			}
		}
		view = forView
		currentNowPlayingItem = NowPlayingItem()
		if NowPlayingAdapter.isRequired {
			NSLog("[NOW_PLAYING]: NowPlayingHelper - MediaRemote info not available, using adapter")
			currentNowPlayingItem?.client = defaultPlayerClient()
			startAdapter()
		} else {
			registerForNotifications()
			updateCurrentPlayingApp(nil)
			updateMediaContent(nil)
			updateCurrentPlayingState(nil)
		}
	}
	
	private func registerForNotifications() {
		NSLog("[NOW_PLAYING]: NowPlayingHelper - registerForNotifications")
		MRMediaRemoteRegisterForNowPlayingNotifications(.main)
		NotificationCenter.default.addObserver(self,
											   selector: #selector(updateCurrentPlayingApp),
											   name: Notification.Name(kMRMediaRemoteNowPlayingApplicationClientStateDidChange),
											   object: nil)
		NotificationCenter.default.addObserver(self,
											   selector: #selector(updateCurrentPlayingApp),
											   name: .mrMediaRemoteNowPlayingApplicationDidChange,
											   object: nil)
		NotificationCenter.default.addObserver(self,
											   selector: #selector(updateMediaContent),
											   name: .mrNowPlayingPlaybackQueueChanged,
											   object: nil)
		NotificationCenter.default.addObserver(self,
											   selector: #selector(updateMediaContent),
											   name: .mrPlaybackQueueContentItemsChanged,
											   object: nil)
		NotificationCenter.default.addObserver(self,
											   selector: #selector(updateCurrentPlayingState),
											   name: .mrMediaRemoteNowPlayingApplicationIsPlayingDidChange,
											   object: nil)
	}
	
	private func unregisterForNotifications() {
		NSLog("[NOW_PLAYING]: NowPlayingHelper - un-registerForNotifications")
		if adapter == nil {
			MRMediaRemoteUnregisterForNowPlayingNotifications()
		}
		NotificationCenter.default.removeObserver(self, name: NSNotification.Name(kMRMediaRemoteNowPlayingApplicationClientStateDidChange), object: nil)
		NotificationCenter.default.removeObserver(self, name: .mrMediaRemoteNowPlayingApplicationDidChange, object: nil)
		NotificationCenter.default.removeObserver(self, name: .mrNowPlayingPlaybackQueueChanged, object: nil)
		NotificationCenter.default.removeObserver(self, name: .mrPlaybackQueueContentItemsChanged, object: nil)
		NotificationCenter.default.removeObserver(self, name: .mrMediaRemoteNowPlayingApplicationIsPlayingDidChange, object: nil)
	}
	
	@objc private func updateCurrentPlayingApp(_ notification: Notification?) {
		MRMediaRemoteGetNowPlayingClient(.main) { [weak self] client in
			guard let self = self else {
				return
			}
			let bundleIdentifier = client?.bundleIdentifier()
			let parentApplicationBundleIdentifier = client?.parentApplicationBundleIdentifier()
			let resolvedClient = self.resolveClient(
				bundleIdentifier: bundleIdentifier,
				parentApplicationBundleIdentifier: parentApplicationBundleIdentifier,
				displayName: client?.displayName()
			)
			let wasSuppressed = self.isCurrentClientSuppressed
			self.isCurrentClientSuppressed = resolvedClient == nil && (bundleIdentifier != nil || parentApplicationBundleIdentifier != nil)
			self.currentNowPlayingItem?.client = resolvedClient ?? self.defaultPlayerClient()
			if wasSuppressed != self.isCurrentClientSuppressed {
				// Info/state may have been fetched (or discarded) for the previous client
				self.updateMediaContent(nil)
				self.updateCurrentPlayingState(nil)
			}
			self.view?.updateContentViews()
		}
	}
	
	@objc private func updateMediaContent(_ notification: Notification?) {
		MRMediaRemoteGetNowPlayingInfo(.main) { [weak self] info in
			guard let self = self else {
				return
			}
			let info = self.isCurrentClientSuppressed ? nil : info
			self.currentNowPlayingItem?.title  = info?[kMRMediaRemoteNowPlayingInfoTitle]  as? String
			self.currentNowPlayingItem?.album  = info?[kMRMediaRemoteNowPlayingInfoAlbum]  as? String
			self.currentNowPlayingItem?.artist = info?[kMRMediaRemoteNowPlayingInfoArtist] as? String
			defer {
				self.view?.updateContentViews()
			}
			if info == nil {
				self.currentNowPlayingItem?.isPlaying = false
			}
			self.updateArtwork(embeddedData: info?[kMRMediaRemoteNowPlayingInfoArtworkData] as? Data, artworkURL: nil)
		}
	}
	
	@objc private func updateCurrentPlayingState(_ notification: Notification?) {
		MRMediaRemoteGetNowPlayingApplicationIsPlaying(.main) { [weak self] isPlaying in
			guard let self = self else {
				return
			}
			if self.currentNowPlayingItem?.client == nil || self.isCurrentClientSuppressed {
				self.currentNowPlayingItem?.isPlaying = false
			} else {
				self.currentNowPlayingItem?.isPlaying = isPlaying
			}
			self.view?.updateContentViews()
		}
	}
	
	deinit {
		NSLog("[NOW_PLAYING]: NowPlayingHelper - deinit")
		view = nil
		latestArtworkTask?.cancel()
		currentNowPlayingItem = nil
		unregisterForNotifications()
		adapter?.stop()
		adapter = nil
	}
	
}

// MARK: Clients
extension NowPlayingHelper {
	
	/// Client shown when nothing (valid) is playing
	private func defaultPlayerClient() -> NowPlayingItem.Client {
		let customDefaultPlayerIdentifier: String = Preferences[.defaultPlayer]
		return NowPlayingItem.Client(
			bundleIdentifier: customDefaultPlayerIdentifier,
			parentApplicationBundleIdentifier: nil,
			displayName: NSWorkspace.shared.applicationName(for: customDefaultPlayerIdentifier),
			icon: icon(for: customDefaultPlayerIdentifier)
		)
	}
	
	/// Returns `nil` if there is no client, if the client is in the ignored list
	/// or if it's an installed app that is not running anymore (stale client).
	private func resolveClient(bundleIdentifier: String?, parentApplicationBundleIdentifier: String?, displayName: String?) -> NowPlayingItem.Client? {
		guard let identifier = parentApplicationBundleIdentifier ?? bundleIdentifier else {
			return nil
		}
		let ignoredPlayers: [String] = Preferences[.ignoredPlayers]
		if ignoredPlayers.contains(identifier) || ignoredPlayers.contains(bundleIdentifier ?? identifier) {
			return nil
		}
		if NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) != nil,
		   NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty {
			return nil
		}
		return NowPlayingItem.Client(
			bundleIdentifier: bundleIdentifier ?? identifier,
			parentApplicationBundleIdentifier: parentApplicationBundleIdentifier,
			displayName: displayName ?? NSWorkspace.shared.applicationName(for: identifier),
			icon: icon(for: identifier)
		)
	}
	
	/// Cached, so that unchanged clients keep the same image (and the UI doesn't redraw it)
	private func icon(for bundleIdentifier: String) -> NSImage? {
		if let icon = iconsCache[bundleIdentifier] {
			return icon
		}
		let icon = NSWorkspace.shared.applicationIcon(for: bundleIdentifier, fallbackFileType: "mp3")
		iconsCache[bundleIdentifier] = icon
		return icon
	}
	
}

// MARK: Adapter
extension NowPlayingHelper {
	
	private func startAdapter() {
		let adapter = NowPlayingAdapter()
		adapter.onUpdate = { [weak self] state in
			self?.apply(adapterState: state)
		}
		adapter.isActive = isOnScreen
		self.adapter = adapter
		// Preferences pane posts these to ask for a refresh
		NotificationCenter.default.addObserver(self,
											   selector: #selector(reapplyAdapterState),
											   name: .mrMediaRemoteNowPlayingApplicationDidChange,
											   object: nil)
		NotificationCenter.default.addObserver(self,
											   selector: #selector(reapplyAdapterState),
											   name: .mrPlaybackQueueContentItemsChanged,
											   object: nil)
		adapter.start()
	}
	
	@objc private func reapplyAdapterState(_ notification: Notification?) {
		guard let state = latestAdapterState else {
			currentNowPlayingItem?.client = defaultPlayerClient()
			view?.updateContentViews()
			return
		}
		apply(adapterState: state)
	}
	
	private func apply(adapterState state: NowPlayingAdapterState) {
		latestAdapterState = state
		guard let item = currentNowPlayingItem else {
			return
		}
		defer {
			view?.updateContentViews()
		}
		let hasMedia = state.source != .none && (state.title != nil || state.artist != nil || state.album != nil || state.isPlaying)
		if hasMedia, let client = resolveClient(bundleIdentifier: state.bundleIdentifier,
												parentApplicationBundleIdentifier: state.parentApplicationBundleIdentifier,
												displayName: state.displayName) {
			item.client    = client
			item.title     = state.title
			item.album     = state.album
			item.artist    = state.artist
			item.isPlaying = state.isPlaying
			updateArtwork(embeddedData: nil, artworkURL: state.artworkURL)
		} else {
			item.client    = defaultPlayerClient()
			item.title     = nil
			item.album     = nil
			item.artist    = nil
			item.isPlaying = false
			updateArtwork(embeddedData: nil, artworkURL: nil)
		}
	}
	
	/// Bundle identifier to send Apple Events to, if data comes from the AppleScript fallback
	private var appleScriptControlledBundleIdentifier: String? {
		guard let state = latestAdapterState, state.source == .applescript, let bundleIdentifier = state.bundleIdentifier,
			  NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false else {
			return nil
		}
		return bundleIdentifier
	}
	
}

extension NowPlayingHelper {
	
	public func togglePlayingState() {
		if let bundleIdentifier = appleScriptControlledBundleIdentifier {
			NowPlayingAdapter.send(.playPause, to: bundleIdentifier)
		} else {
			MRMediaRemoteSendCommand(kMRTogglePlayPause, nil)
		}
		adapter?.setNeedsUpdate()
	}
	
	public func skipToNextTrack() {
		if let bundleIdentifier = appleScriptControlledBundleIdentifier {
			NowPlayingAdapter.send(.nextTrack, to: bundleIdentifier)
		} else {
			MRMediaRemoteSendCommand(kMRNextTrack, nil)
		}
		adapter?.setNeedsUpdate()
	}
	
	public func skipToPreviousTrack() {
		if let bundleIdentifier = appleScriptControlledBundleIdentifier {
			NowPlayingAdapter.send(.previousTrack, to: bundleIdentifier)
		} else {
			MRMediaRemoteSendCommand(kMRPreviousTrack, nil)
		}
		adapter?.setNeedsUpdate()
	}
	
}

// MARK: Artwork
extension NowPlayingHelper {
	
	/// Updates `currentNowPlayingItem.artwork` for the current track.
	///
	/// - parameter embeddedData: artwork data provided by MediaRemote, if any (preferred)
	/// - parameter artworkURL: artwork URL provided by the player, if any
	///
	/// Falls back to the iTunes Search API. Results are applied only if the track didn't change in the meantime.
	private func updateArtwork(embeddedData: Data?, artworkURL: String?) {
		guard let item = currentNowPlayingItem else {
			return
		}
		guard Preferences[.showMediaArtwork], let trackIdentifier = item.trackIdentifier else {
			latestArtworkTask?.cancel()
			latestArtworkTask = nil
			latestEmbeddedArtworkData = nil
			latestArtworkSourceURL = nil
			item.artwork = nil
			item.artworkTrackIdentifier = nil
			return
		}
		if let data = embeddedData {
			// MediaRemote sends the same artwork data with every info update: decode it only once
			if data == latestEmbeddedArtworkData, item.artworkTrackIdentifier == trackIdentifier, item.artwork != nil {
				return
			}
			if let image = NSImage.thumbnail(from: data) {
				latestArtworkTask?.cancel()
				latestArtworkTask = nil
				latestEmbeddedArtworkData = data
				latestArtworkSourceURL = nil
				item.artwork = image
				item.artworkTrackIdentifier = trackIdentifier
				return
			}
		}
		latestEmbeddedArtworkData = nil
		let playerArtworkURL = artworkURL.flatMap({ $0.isEmpty ? nil : $0 })
		if item.artworkTrackIdentifier == trackIdentifier {
			// Artwork for this track is already set (or being fetched). A player-provided URL arriving later
			// (e.g. Spotify's `artworkURL`) takes precedence over the iTunes Search result: fetch it once.
			guard let playerArtworkURL = playerArtworkURL, playerArtworkURL != latestArtworkSourceURL else {
				return
			}
			// Keep showing the current artwork (if any) until the player's one is downloaded
		} else {
			// Don't keep showing previous track's artwork
			item.artwork = nil
			item.artworkTrackIdentifier = trackIdentifier
		}
		latestArtworkSourceURL = playerArtworkURL
		let isStillValid: () -> Bool = { [weak self] in
			guard let self = self else {
				return false
			}
			return self.currentNowPlayingItem?.artworkTrackIdentifier == trackIdentifier && self.latestArtworkSourceURL == playerArtworkURL
		}
		fetchArtwork(searchTerm: item.searchTerm, artworkURL: playerArtworkURL, isStillValid: isStillValid, { [weak self] image in
			guard let self = self, isStillValid(), let item = self.currentNowPlayingItem else {
				return
			}
			// A failed download of the player's artwork doesn't discard what is already shown
			guard image != nil || playerArtworkURL == nil else {
				return
			}
			item.artwork = image
			self.view?.updateContentViews()
		})
	}
	
}

/// Credit: https://github.com/musa11971/Music-Bar
extension NowPlayingHelper {
	/// Retrieves the artwork of the current track (from the given URL or from Apple).
	///
	/// `isStillValid` and `completion` are called on main queue.
	fileprivate func fetchArtwork(searchTerm: String?, artworkURL: String?, isStillValid: @escaping () -> Bool, _ completion: @escaping (NSImage?) -> Void) {
		/// Destroy tasks, if any was already busy
		latestArtworkTask?.cancel()
		latestArtworkTask = nil
		/// Download the given artwork, if any
		if let artworkURL = artworkURL, let url = URL(string: artworkURL) {
			latestArtworkTask = downloadArtwork(from: url, isStillValid: isStillValid, completion)
			latestArtworkTask?.resume()
			return
		}
		/// Check for search term
		guard let searchTerm = searchTerm, let apiURL = URL(string: "https://itunes.apple.com/search?term=\(searchTerm)&entity=song&limit=1") else {
			completion(nil)
			return
		}
		/// Start fetching artwork
		latestArtworkTask = URLSession.fetchJSON(fromURL: apiURL) { [weak self] (data, json, error) in
			var artworkURL: URL?
			if error == nil,
			   let results = (json as? [String: Any])?["results"] as? [[String: Any]],
			   let imgURL = results.first?["artworkUrl100"] as? String {
				artworkURL = URL(string: imgURL.replacingOccurrences(of: "100x100", with: "300x300"))
			}
			DispatchQueue.main.async {
				guard let self = self, isStillValid() else {
					return
				}
				guard let url = artworkURL else {
					if error == nil {
						NSLog("[NOW_PLAYING]: Could not get artwork")
					}
					completion(nil)
					return
				}
				/// Download the artwork
				self.latestArtworkTask = self.downloadArtwork(from: url, isStillValid: isStillValid, completion)
				self.latestArtworkTask?.resume()
			}
		}
		latestArtworkTask?.resume()
	}
	
	private func downloadArtwork(from url: URL, isStillValid: @escaping () -> Bool, _ completion: @escaping (NSImage?) -> Void) -> URLSessionTask {
		return URLSession.shared.dataTask(with: url, completionHandler: { (data, response, error) in
			// Decoded (and downscaled) here, not on main thread while drawing
			let image = error == nil ? data.flatMap({ NSImage.thumbnail(from: $0) }) : nil
			DispatchQueue.main.async {
				guard isStillValid() else {
					return
				}
				completion(image)
			}
		})
	}
}

extension URLSession {
	static func fetchJSON(fromURL url: URL, completionHandler: @escaping (Data?, Any?, Error?) -> Void) -> URLSessionTask {
		let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
			if error != nil {
				completionHandler(nil, nil, error)
				return
			}
			if data == nil {
				completionHandler(nil, nil, NSError(domain:"", code:401, userInfo:[ NSLocalizedDescriptionKey: "Invalid data"]))
				return
			}
			guard let json = try? JSONSerialization.jsonObject(with: data!, options: .allowFragments) else {
				completionHandler(nil, nil, NSError(domain:"", code:401, userInfo:[ NSLocalizedDescriptionKey: "Invalid json"]))
				return
			}
			completionHandler(data, json, nil)
		}
		return task
	}
}

extension NSImage {
	/// Decoded image, downscaled to what the Touch Bar needs (24pt icon @2x)
	static func thumbnail(from data: Data, maxPixelSize: Int = 64) -> NSImage? {
		let options: [CFString: Any] = [
			kCGImageSourceCreateThumbnailFromImageAlways: true,
			kCGImageSourceCreateThumbnailWithTransform: true,
			kCGImageSourceShouldCacheImmediately: true,
			kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
		]
		guard let source = CGImageSourceCreateWithData(data as CFData, nil),
			  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
			return NSImage(data: data)
		}
		return NSImage(cgImage: image, size: .zero)
	}
}

extension NSWorkspace {
	public func applicationName(for bundleIdentifier: String) -> String? {
		self.urlForApplication(withBundleIdentifier: bundleIdentifier)?.lastPathComponent.replacingOccurrences(of: ".app", with: "")
	}
	public func applicationIcon(for bundleIdentifier: String?, fallbackFileType: String? = nil) -> NSImage? {
		if let bundleIdentifier = bundleIdentifier,
		   let path = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: bundleIdentifier) {
			return NSWorkspace.shared.icon(forFile: path)
		} else {
			return NSWorkspace.shared.icon(forFileType: fallbackFileType ?? "pock")
		}
	}
}
