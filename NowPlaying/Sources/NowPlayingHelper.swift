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
	
	/// Ref
	internal weak var view: NowPlayingView?
	
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
		registerForNotifications()
		updateCurrentPlayingApp(nil)
		updateMediaContent(nil)
		updateCurrentPlayingState(nil)
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
		MRMediaRemoteUnregisterForNowPlayingNotifications()
		NotificationCenter.default.removeObserver(self, name: NSNotification.Name(kMRMediaRemoteNowPlayingApplicationClientStateDidChange), object: nil)
		NotificationCenter.default.removeObserver(self, name: .mrMediaRemoteNowPlayingApplicationDidChange, object: nil)
		NotificationCenter.default.removeObserver(self, name: .mrNowPlayingPlaybackQueueChanged, object: nil)
		NotificationCenter.default.removeObserver(self, name: .mrPlaybackQueueContentItemsChanged, object: nil)
		NotificationCenter.default.removeObserver(self, name: .mrMediaRemoteNowPlayingApplicationIsPlayingDidChange, object: nil)
	}
	
	@objc private func updateCurrentPlayingApp(_ notification: Notification?) {
		MRMediaRemoteGetNowPlayingClient(.main) { [unowned self] client in
			if client?.bundleIdentifier() == nil && client?.parentApplicationBundleIdentifier() == nil {
				// Check custom default player
				let customDefaultPlayerIdentifier: String = Preferences[.defaultPlayer]
				let displayName = NSWorkspace.shared.applicationName(for: customDefaultPlayerIdentifier)
				let icon = NSWorkspace.shared.applicationIcon(for: customDefaultPlayerIdentifier, fallbackFileType: "mp3")
				self.currentNowPlayingItem?.client = NowPlayingItem.Client(
					bundleIdentifier: customDefaultPlayerIdentifier,
					parentApplicationBundleIdentifier: nil,
					displayName: displayName,
					icon: icon
				)
			} else {
				self.currentNowPlayingItem?.client = NowPlayingItem.Client(
					bundleIdentifier: 					client?.bundleIdentifier(),
					parentApplicationBundleIdentifier:  client?.parentApplicationBundleIdentifier(),
					displayName: 						client?.displayName(),
					icon: NSWorkspace.shared.applicationIcon(for: client?.parentApplicationBundleIdentifier() ?? client?.bundleIdentifier(), fallbackFileType: "mp3")
				)
			}
			self.view?.updateContentViews()
		}
	}
	
	@objc private func updateMediaContent(_ notification: Notification?) {
		MRMediaRemoteGetNowPlayingInfo(.main) { [unowned self] info in
			self.currentNowPlayingItem?.title  = info?[kMRMediaRemoteNowPlayingInfoTitle]  as? String
			self.currentNowPlayingItem?.album  = info?[kMRMediaRemoteNowPlayingInfoAlbum]  as? String
			self.currentNowPlayingItem?.artist = info?[kMRMediaRemoteNowPlayingInfoArtist] as? String
			defer {
				self.view?.updateContentViews()
			}
			if info == nil {
				self.currentNowPlayingItem?.isPlaying = false
			} else {
				if Preferences[.showMediaArtwork] {
					self.fetchArtwork(for: self.currentNowPlayingItem) { image in
						self.currentNowPlayingItem?.artwork = image
					}
				} else {
					self.latestArtworkTask?.cancel()
					self.currentNowPlayingItem?.artwork = nil
				}
			}
		}
	}
	
	@objc private func updateCurrentPlayingState(_ notification: Notification?) {
		MRMediaRemoteGetNowPlayingApplicationIsPlaying(.main) { [unowned self] isPlaying in
			if self.currentNowPlayingItem?.client == nil {
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
		currentNowPlayingItem = nil
		unregisterForNotifications()
	}
	
}

extension NowPlayingHelper {
	
	public func togglePlayingState() {
		MRMediaRemoteSendCommand(kMRTogglePlayPause, nil)
	}
	
	public func skipToNextTrack() {
		MRMediaRemoteSendCommand(kMRNextTrack, nil)
	}
	
	public func skipToPreviousTrack() {
		MRMediaRemoteSendCommand(kMRPreviousTrack, nil)
	}
	
}

/// Credit: https://github.com/musa11971/Music-Bar
extension NowPlayingHelper {
	/// Retrieves the artwork of the current track from Apple
	fileprivate func fetchArtwork(for item: NowPlayingItem?, _ completion: @escaping (NSImage?) -> Void) {
		/// Destroy tasks, if any was already busy
		latestArtworkTask?.cancel()
		/// Check for now playing item
		guard let item = item, let searchTerm = item.searchTerm else {
			completion(nil)
			return
		}
		/// Start fetching artwork
		let apiURL: String = "https://itunes.apple.com/search?term=\(searchTerm)&entity=song&limit=1"
		latestArtworkTask = URLSession.fetchJSON(fromURL: URL(string: apiURL)!) { [weak self] (data, json, error) in
			if error != nil {
				print("Could not get artwork")
				completion(nil)
				return
			}
			if let json = json as? [String: Any] {
				if let results = json["results"] as? [[String: Any]] {
					if results.count >= 1, let imgURL = results[0]["artworkUrl100"] as? String {
						// Create the URL
						guard let url = URL(string: imgURL.replacingOccurrences(of: "100x100", with: "300x300")) else {
							completion(nil)
							return
						}
						// Download the artwork
						self?.latestArtworkTask = URLSession.shared.dataTask(with: url, completionHandler: { (data, response, error) in
							if error != nil {
								completion(nil)
								return
							}
							guard let data = data else {
								completion(nil)
								return
							}
							completion(NSImage(data: data))
						})
						self?.latestArtworkTask?.resume()
					} else {
						completion(nil)
					}
				}
			}
		}
		latestArtworkTask?.resume()
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
