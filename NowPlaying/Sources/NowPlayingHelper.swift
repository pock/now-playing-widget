//
//  NowPlayingHelper.swift
//  Pock
//
//  Created by Pierluigi Galdi on 17/02/2019.
//  Copyright © 2019 Pierluigi Galdi. All rights reserved.
//

import Foundation
import AppKit
import Defaults

class NowPlayingHelper {
	
	/// Core
	public static let shared: NowPlayingHelper = NowPlayingHelper()
	public static let kNowPlayingItemDidChange: Notification.Name = Notification.Name(rawValue: "kNowPlayingItemDidChange")
	
	/// Data
	public let nowPlayingItem: NowPlayingItem = NowPlayingItem()
	
	/// Artwork
	private var latestArtworkTask: URLSessionTask?
	
	private init() {
		MRMediaRemoteRegisterForNowPlayingNotifications(DispatchQueue.global(qos: .utility))
		registerForNotifications()
		updateCurrentPlayingApp()
		updateMediaContent()
		updateCurrentPlayingState()
	}
	
	private func registerForNotifications() {
		NotificationCenter.default.addObserver(self,
											   selector: #selector(updateCurrentPlayingApp),
											   name: NSNotification.Name.mrMediaRemoteNowPlayingApplicationDidChange,
											   object: nil
		)
		NotificationCenter.default.addObserver(self,
											   selector: #selector(updateMediaContent),
											   name: NSNotification.Name(rawValue: kMRMediaRemoteNowPlayingApplicationClientStateDidChange),
											   object: nil
		)
		NotificationCenter.default.addObserver(self,
											   selector: #selector(updateMediaContent),
											   name: NSNotification.Name.mrNowPlayingPlaybackQueueChanged,
											   object: nil
		)
		NotificationCenter.default.addObserver(self,
											   selector: #selector(updateMediaContent),
											   name: NSNotification.Name.mrPlaybackQueueContentItemsChanged,
											   object: nil
		)
		NotificationCenter.default.addObserver(self,
											   selector: #selector(updateCurrentPlayingState),
											   name: NSNotification.Name.mrMediaRemoteNowPlayingApplicationIsPlayingDidChange,
											   object: nil
		)
	}
	
	@objc private func updateCurrentPlayingApp() {
		MRMediaRemoteGetNowPlayingClients(DispatchQueue.global(qos: .utility), { [weak self] clients in
			if let info = (clients as? [Any])?.last {
				if let appBundleIdentifier = MRNowPlayingClientGetBundleIdentifier(info) {
					self?.nowPlayingItem.appBundleIdentifier = appBundleIdentifier
				}else if let appBundleIdentifier = MRNowPlayingClientGetParentAppBundleIdentifier(info) {
					self?.nowPlayingItem.appBundleIdentifier = appBundleIdentifier
				}else {
					self?.nowPlayingItem.appBundleIdentifier = nil
				}
			}else {
				self?.nowPlayingItem.appBundleIdentifier = nil
				self?.nowPlayingItem.isPlaying = false
				self?.nowPlayingItem.album  = nil
				self?.nowPlayingItem.artist = nil
				self?.nowPlayingItem.title  = nil
			}
			NotificationCenter.default.post(name: NowPlayingHelper.kNowPlayingItemDidChange, object: nil)
		})
	}
	
	@objc private func updateMediaContent() {
		MRMediaRemoteGetNowPlayingInfo(DispatchQueue.global(qos: .utility), { [weak self] info in
			self?.nowPlayingItem.title  = info?[kMRMediaRemoteNowPlayingInfoTitle]  as? String
			self?.nowPlayingItem.album  = info?[kMRMediaRemoteNowPlayingInfoAlbum]  as? String
			self?.nowPlayingItem.artist = info?[kMRMediaRemoteNowPlayingInfoArtist] as? String
			if info == nil {
				self?.nowPlayingItem.isPlaying = false
			}else {
				if Defaults[.showMediaArtwork] {
					self?.fetchArtwork(for: self?.nowPlayingItem) { [weak self] image in
						self?.nowPlayingItem.artwork = image
						NotificationCenter.default.post(name: NowPlayingHelper.kNowPlayingItemDidChange, object: nil)
					}
				}else {
					self?.latestArtworkTask?.cancel()
					self?.nowPlayingItem.artwork = nil
					NotificationCenter.default.post(name: NowPlayingHelper.kNowPlayingItemDidChange, object: nil)
				}
			}
		})
	}
	
	@objc private func updateCurrentPlayingState() {
		MRMediaRemoteGetNowPlayingApplicationIsPlaying(DispatchQueue.global(qos: .utility), {[weak self] isPlaying in
			if self?.nowPlayingItem.appBundleIdentifier == nil {
				self?.nowPlayingItem.isPlaying = false
			}else {
				self?.nowPlayingItem.isPlaying = isPlaying
			}
			NotificationCenter.default.post(name: NowPlayingHelper.kNowPlayingItemDidChange, object: nil)
		})
	}
	
	deinit {
		NotificationCenter.default.removeObserver(self)
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
					}else {
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
