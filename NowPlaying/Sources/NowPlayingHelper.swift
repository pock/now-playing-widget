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
	public static let kNowPlayingItemDidChange: Notification.Name = Notification.Name(rawValue: "kNowPlayingItemDidChange")
	
	/// Data
	public static private(set) var currentNowPlayingItem: NowPlayingItem?
	
	/// Artwork
	private var latestArtworkTask: URLSessionTask?
	
	internal init() {
		NSLog("[NOW_PLAYING]: NowPlayingHelper - init")
		NowPlayingHelper.currentNowPlayingItem = NowPlayingItem()
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
		MRMediaRemoteGetNowPlayingClient(DispatchQueue.global(qos: .utility), { client in
			NowPlayingHelper.currentNowPlayingItem?.client = client
			NotificationCenter.default.post(name: NowPlayingHelper.kNowPlayingItemDidChange, object: nil)
		})
	}
	
	@objc private func updateMediaContent() {
		MRMediaRemoteGetNowPlayingInfo(DispatchQueue.global(qos: .utility), { [weak self] info in
			NowPlayingHelper.currentNowPlayingItem?.title  = info?[kMRMediaRemoteNowPlayingInfoTitle]  as? String
			NowPlayingHelper.currentNowPlayingItem?.album  = info?[kMRMediaRemoteNowPlayingInfoAlbum]  as? String
			NowPlayingHelper.currentNowPlayingItem?.artist = info?[kMRMediaRemoteNowPlayingInfoArtist] as? String
			if info == nil {
				NowPlayingHelper.currentNowPlayingItem?.isPlaying = false
			} else {
				if Defaults[.showMediaArtwork] {
					self?.fetchArtwork(for: NowPlayingHelper.currentNowPlayingItem) { image in
						NowPlayingHelper.currentNowPlayingItem?.artwork = image
						NotificationCenter.default.post(name: NowPlayingHelper.kNowPlayingItemDidChange, object: nil)
					}
				} else {
					self?.latestArtworkTask?.cancel()
					NowPlayingHelper.currentNowPlayingItem?.artwork = nil
					NotificationCenter.default.post(name: NowPlayingHelper.kNowPlayingItemDidChange, object: nil)
				}
			}
		})
	}
	
	@objc private func updateCurrentPlayingState() {
		MRMediaRemoteGetNowPlayingApplicationIsPlaying(DispatchQueue.global(qos: .utility), { isPlaying in
			if NowPlayingHelper.currentNowPlayingItem?.client == nil {
				NowPlayingHelper.currentNowPlayingItem?.isPlaying = false
			} else {
				NowPlayingHelper.currentNowPlayingItem?.isPlaying = isPlaying
			}
			NotificationCenter.default.post(name: NowPlayingHelper.kNowPlayingItemDidChange, object: nil)
		})
	}
	
	deinit {
		NSLog("[NOW_PLAYING]: NowPlayingHelper - deinit")
		NowPlayingHelper.currentNowPlayingItem = nil
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
