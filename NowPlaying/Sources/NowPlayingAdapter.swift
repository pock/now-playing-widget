//
//  NowPlayingAdapter.swift
//  NowPlaying
//
//  Starting with macOS 15.4, `MRMediaRemoteGetNowPlayingInfo` & co. return nothing
//  to processes that are not entitled to read MediaRemote data (Pock included).
//  Commands (`MRMediaRemoteSendCommand`) still work, reading does not.
//
//  Apple-signed tools such as `/usr/bin/osascript` are still allowed to read it,
//  so this adapter keeps a small JavaScript for Automation script running inside `osascript`
//  that reads `MRNowPlayingRequest` every time it receives a line on stdin and writes
//  the result back as a JSON line (only when something changed).
//  If MediaRemote returns nothing, the script falls back to asking Spotify / Music
//  directly via Apple Events (this requires the "Automation" permission and the
//  `NSAppleEventsUsageDescription` key in the host app's Info.plist).
//
//  To keep the cost low, the script never polls on its own:
//  - requests are only sent while the widget is on screen and screens/system are awake;
//  - the polling interval is short only while something is playing;
//  - playback changes (MediaRemote Darwin notifications, players' distributed notifications)
//    and user commands trigger an immediate refresh.
//  The script exits as soon as its stdin is closed, so it can't outlive Pock.
//

import Foundation
import AppKit
import notify

internal struct NowPlayingAdapterState: Decodable, Equatable {
	enum Source: String, Decodable {
		case mediaremote, applescript, none
	}
	let source: Source
	let bundleIdentifier: String?
	let parentApplicationBundleIdentifier: String?
	let displayName: String?
	let title: String?
	let artist: String?
	let album: String?
	let isPlaying: Bool
	let artworkURL: String?
}

internal class NowPlayingAdapter {

	/// `true` on systems where MediaRemote does not return now playing info to Pock anymore.
	internal static var isRequired: Bool {
		if #available(macOS 15.4, *) {
			return true
		}
		return false
	}

	/// Polling interval (seconds) while something is playing (track changes are not notified).
	private static let playingPollingInterval: TimeInterval = 2

	/// Polling interval (seconds) while nothing is playing (playback start is notified).
	private static let idlePollingInterval: TimeInterval = 5

	/// Delay (seconds) used to coalesce refresh requests.
	private static let refreshDelay: TimeInterval = 0.25

	/// Max number of consecutive restarts without receiving any output.
	private static let maxRestartAttempts: Int = 5

	/// Players the script can query via Apple Events. Only the running ones are sent to the script,
	/// since sending an Apple Event to an app that is not running launches it.
	private static let appleScriptPlayers: [String] = ["com.spotify.client", "com.apple.Music"]

	/// Darwin notifications posted by MediaRemote when playback starts/stops (delivered to any process).
	private static let darwinNotifications: [String] = [
		"com.apple.MediaRemote.nowPlayingApplicationIsPlayingDidChange",
		"com.apple.MediaRemote.nowPlayingActivePlayersIsPlayingDidChange"
	]

	/// Distributed notifications posted by players when playback state or track change.
	private static let distributedNotifications: [String] = [
		"com.spotify.client.PlaybackStateChanged",
		"com.apple.Music.playerInfo"
	]

	/// Callback, always invoked on main queue
	internal var onUpdate: ((NowPlayingAdapterState) -> Void)?

	/// `true` while the widget is on screen. Now playing info is requested only while active.
	internal var isActive: Bool = false {
		didSet {
			guard oldValue != isActive else {
				return
			}
			updatePollingState()
		}
	}

	/// Core
	private var process: Process?
	private var input: FileHandle?
	private var isStopped: Bool = true
	private var restartAttempts: Int = 0
	private var latestState: NowPlayingAdapterState?

	/// Polling
	private var isPolling: Bool = false
	private var pollTimer: Timer?
	private var isSystemAsleep: Bool = false
	private var areScreensAsleep: Bool = false
	private var sleepObservers: [NSObjectProtocol] = []
	private var refreshObservers: [NSObjectProtocol] = []
	private var notifyTokens: [Int32] = []

	internal init() {
		NSLog("[NOW_PLAYING]: NowPlayingAdapter - init")
	}

	deinit {
		NSLog("[NOW_PLAYING]: NowPlayingAdapter - deinit")
		stop()
	}

	/// Launches `osascript` (idle until the first request) and starts polling, if active.
	internal func start() {
		guard isStopped else {
			return
		}
		isStopped = false
		restartAttempts = 0
		registerForSleepNotifications()
		launchProcess()
		updatePollingState()
	}

	/// Stops polling and terminates `osascript`.
	internal func stop() {
		isStopped = true
		updatePollingState()
		unregisterForSleepNotifications()
		terminateProcess()
	}

	/// Asks for fresh now playing info (e.g. after a command has been sent to the player).
	internal func setNeedsUpdate(after delay: TimeInterval = NowPlayingAdapter.refreshDelay) {
		guard isPolling else {
			return
		}
		if let timer = pollTimer, timer.isValid, timer.fireDate <= Date(timeIntervalSinceNow: delay) {
			return
		}
		schedulePoll(after: delay)
	}

}

// MARK: Process
extension NowPlayingAdapter {

	private func launchProcess() {
		guard process == nil else {
			return
		}
		let inputPipe = Pipe()
		let outputPipe = Pipe()
		let inputDescriptor = inputPipe.fileHandleForWriting.fileDescriptor
		// Writes must never block the main thread nor raise `SIGPIPE` if `osascript` went away
		_ = fcntl(inputDescriptor, F_SETFL, fcntl(inputDescriptor, F_GETFL) | O_NONBLOCK)
		_ = fcntl(inputDescriptor, F_SETNOSIGPIPE, 1)
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
		process.arguments = ["-l", "JavaScript", "-e", NowPlayingAdapter.script]
		process.standardInput = inputPipe
		process.standardOutput = outputPipe
		process.standardError = FileHandle.nullDevice
		var buffer = Data()
		outputPipe.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
			let data = handle.availableData
			guard data.isEmpty == false else {
				handle.readabilityHandler = nil
				return
			}
			buffer.append(data)
			guard let state = NowPlayingAdapter.latestState(consuming: &buffer) else {
				return
			}
			DispatchQueue.main.async {
				guard let self = self, let process = process, process === self.process else {
					return
				}
				self.didReceive(state)
			}
		}
		process.terminationHandler = { [weak self] terminated in
			DispatchQueue.main.async {
				self?.processDidTerminate(terminated)
			}
		}
		NSLog("[NOW_PLAYING]: NowPlayingAdapter - launching osascript")
		do {
			try process.run()
		} catch {
			NSLog("[NOW_PLAYING]: NowPlayingAdapter - can't launch osascript: \(error)")
			outputPipe.fileHandleForReading.readabilityHandler = nil
			return
		}
		self.process = process
		self.input = inputPipe.fileHandleForWriting
	}

	private func terminateProcess() {
		guard let process = process else {
			return
		}
		self.process = nil
		(process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
		process.terminationHandler = nil
		// Closing stdin is enough for the script to exit, `terminate()` also interrupts a pending Apple Event
		try? input?.close()
		input = nil
		if process.isRunning {
			process.terminate()
		}
	}

	private func processDidTerminate(_ terminated: Process) {
		guard terminated === process else {
			return
		}
		process = nil
		try? input?.close()
		input = nil
		NSLog("[NOW_PLAYING]: NowPlayingAdapter - osascript terminated with status: \(terminated.terminationStatus)")
		guard isStopped == false else {
			return
		}
		restartAttempts += 1
		guard restartAttempts <= NowPlayingAdapter.maxRestartAttempts else {
			NSLog("[NOW_PLAYING]: NowPlayingAdapter - giving up after \(NowPlayingAdapter.maxRestartAttempts) attempts")
			return
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
			guard let self = self, self.isStopped == false, self.process == nil else {
				return
			}
			self.launchProcess()
			self.setNeedsUpdate(after: 0)
		}
	}

	/// Called on the pipe's background queue. Consumes complete lines in `buffer` and returns the latest state, if any.
	private static func latestState(consuming buffer: inout Data) -> NowPlayingAdapterState? {
		var latest: NowPlayingAdapterState?
		while let index = buffer.firstIndex(of: UInt8(ascii: "\n")) {
			let line = buffer.subdata(in: buffer.startIndex..<index)
			buffer.removeSubrange(buffer.startIndex...index)
			guard line.isEmpty == false else {
				continue
			}
			if let state = try? JSONDecoder().decode(NowPlayingAdapterState.self, from: line) {
				latest = state
			} else {
				NSLog("[NOW_PLAYING]: NowPlayingAdapter - can't decode line: \(String(data: line, encoding: .utf8) ?? "<binary>")")
			}
		}
		return latest
	}

	private func didReceive(_ state: NowPlayingAdapterState) {
		guard isStopped == false else {
			return
		}
		restartAttempts = 0
		let wasPlaying = latestState?.isPlaying ?? false
		latestState = state
		onUpdate?(state)
		if state.isPlaying, wasPlaying == false {
			// Switch to the shorter polling interval right away
			setNeedsUpdate(after: NowPlayingAdapter.playingPollingInterval)
		}
	}

}

// MARK: Polling
extension NowPlayingAdapter {

	private var shouldPoll: Bool {
		return isStopped == false && isActive && isSystemAsleep == false && areScreensAsleep == false
	}

	private func updatePollingState() {
		let shouldPoll = self.shouldPoll
		guard shouldPoll != isPolling else {
			return
		}
		isPolling = shouldPoll
		if shouldPoll {
			NSLog("[NOW_PLAYING]: NowPlayingAdapter - resume polling")
			registerForRefreshNotifications()
			if process == nil {
				restartAttempts = 0
				launchProcess()
			}
			setNeedsUpdate(after: 0)
		} else {
			NSLog("[NOW_PLAYING]: NowPlayingAdapter - pause polling")
			pollTimer?.invalidate()
			pollTimer = nil
			unregisterForRefreshNotifications()
		}
	}

	private func schedulePoll(after delay: TimeInterval) {
		pollTimer?.invalidate()
		let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
			self?.poll()
		}
		// Let the system coalesce wake-ups
		timer.tolerance = delay * 0.1
		RunLoop.main.add(timer, forMode: .common)
		pollTimer = timer
	}

	private func poll() {
		pollTimer = nil
		guard isPolling else {
			return
		}
		requestState()
		let isPlaying = latestState?.isPlaying ?? false
		schedulePoll(after: isPlaying ? NowPlayingAdapter.playingPollingInterval : NowPlayingAdapter.idlePollingInterval)
	}

	/// Writes a request line: the comma separated list of running players the script can fall back to.
	private func requestState() {
		guard let input = input else {
			return
		}
		let runningPlayers = NowPlayingAdapter.appleScriptPlayers.filter({
			NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty == false
		})
		let data = Data((runningPlayers.joined(separator: ",") + "\n").utf8)
		_ = data.withUnsafeBytes { bytes in
			Darwin.write(input.fileDescriptor, bytes.baseAddress, bytes.count)
		}
	}

}

// MARK: Notifications
extension NowPlayingAdapter {

	private func registerForSleepNotifications() {
		guard sleepObservers.isEmpty else {
			return
		}
		let center = NSWorkspace.shared.notificationCenter
		let observe: (Notification.Name, @escaping (NowPlayingAdapter) -> Void) -> NSObjectProtocol = { name, update in
			return center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
				guard let self = self else {
					return
				}
				update(self)
				self.updatePollingState()
			}
		}
		sleepObservers = [
			observe(NSWorkspace.willSleepNotification, { $0.isSystemAsleep = true }),
			observe(NSWorkspace.didWakeNotification, { $0.isSystemAsleep = false }),
			observe(NSWorkspace.screensDidSleepNotification, { $0.areScreensAsleep = true }),
			observe(NSWorkspace.screensDidWakeNotification, { $0.areScreensAsleep = false })
		]
	}

	private func unregisterForSleepNotifications() {
		sleepObservers.forEach({ NSWorkspace.shared.notificationCenter.removeObserver($0) })
		sleepObservers.removeAll()
	}

	private func registerForRefreshNotifications() {
		guard notifyTokens.isEmpty, refreshObservers.isEmpty else {
			return
		}
		for name in NowPlayingAdapter.darwinNotifications {
			var token: Int32 = 0
			let status = notify_register_dispatch(name, &token, DispatchQueue.main) { [weak self] _ in
				self?.setNeedsUpdate()
			}
			if status == NOTIFY_STATUS_OK {
				notifyTokens.append(token)
			}
		}
		// AppKit suspends distributed notifications while the app is inactive, which is always the case for Pock
		for name in NowPlayingAdapter.distributedNotifications {
			DistributedNotificationCenter.default().addObserver(self,
																 selector: #selector(refreshNotificationReceived),
																 name: Notification.Name(name),
																 object: nil,
																 suspensionBehavior: .deliverImmediately)
		}
		// A player that quits while paused doesn't change MediaRemote's playing state
		refreshObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
			guard let self = self else {
				return
			}
			// The script only writes changes: if MediaRemote keeps reporting the app that quit, nothing is received.
			// Deliver the latest state again, so that the (now stale) client gets validated again.
			if let state = self.latestState {
				self.onUpdate?(state)
			}
			self.setNeedsUpdate()
		})
	}

	private func unregisterForRefreshNotifications() {
		notifyTokens.forEach({ notify_cancel($0) })
		notifyTokens.removeAll()
		for name in NowPlayingAdapter.distributedNotifications {
			DistributedNotificationCenter.default().removeObserver(self, name: Notification.Name(name), object: nil)
		}
		refreshObservers.forEach({ NSWorkspace.shared.notificationCenter.removeObserver($0) })
		refreshObservers.removeAll()
	}

	@objc private func refreshNotificationReceived(_ notification: Notification) {
		setNeedsUpdate()
	}

}

// MARK: Apple Events commands (used when data comes from the AppleScript fallback)
extension NowPlayingAdapter {

	internal enum Command: String {
		case playPause = "playpause"
		case nextTrack = "next track"
		case previousTrack = "previous track"
	}

	internal static func send(_ command: Command, to bundleIdentifier: String) {
		guard bundleIdentifier.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else {
			return
		}
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
		// `tell application` launches the player if it has been quit in the meantime
		process.arguments = ["-e", "if application id \"\(bundleIdentifier)\" is running then tell application id \"\(bundleIdentifier)\" to \(command.rawValue)"]
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		try? process.run()
	}

}

// MARK: JXA script
extension NowPlayingAdapter {

	/// Input: one line per request, with the comma separated list of running players to fall back to.
	/// Output: one JSON object per line, only when something changes.
	/// The script exits when stdin is closed (adapter stopped, Pock quit or crashed).
	private static let script: String = #"""
	ObjC.import("Foundation");
	function run(argv) {
		const input = $.NSFileHandle.fileHandleWithStandardInput;
		const out = $.NSFileHandle.fileHandleWithStandardOutput;
		const exists = function (value) {
			return value !== undefined && value !== null && !(typeof value.isNil === "function" && value.isNil());
		};
		const str = function (value) {
			if (!exists(value)) { return null; }
			const unwrapped = ObjC.unwrap(value);
			return (typeof unwrapped === "string" && unwrapped.length > 0) ? unwrapped : null;
		};
		const url = function (value) {
			return exists(value) ? str(value.absoluteString) : null;
		};
		const bundle = $.NSBundle.bundleWithPath("/System/Library/PrivateFrameworks/MediaRemote.framework/");
		const request = (exists(bundle) && bundle.load) ? $.NSClassFromString("MRNowPlayingRequest") : undefined;
		const players = ["com.spotify.client", "com.apple.Music"];
		const fromMediaRemote = function () {
			if (!exists(request)) { return null; }
			const item = request.localNowPlayingItem;
			if (!exists(item)) { return null; }
			const info = item.nowPlayingInfo;
			if (!exists(info)) { return null; }
			const path = request.localNowPlayingPlayerPath;
			const client = exists(path) ? path.client : undefined;
			const hasClient = exists(client);
			const metadata = item.metadata;
			let artworkURL = null;
			if (exists(metadata)) {
				artworkURL = url(metadata.artworkURL) || url(metadata.artworkFileURL);
			}
			return {
				source: "mediaremote",
				bundleIdentifier: hasClient ? str(client.bundleIdentifier) : null,
				parentApplicationBundleIdentifier: hasClient ? str(client.parentApplicationBundleIdentifier) : null,
				displayName: hasClient ? str(client.displayName) : null,
				title: str(info.objectForKey("kMRMediaRemoteNowPlayingInfoTitle")),
				artist: str(info.objectForKey("kMRMediaRemoteNowPlayingInfoArtist")),
				album: str(info.objectForKey("kMRMediaRemoteNowPlayingInfoAlbum")),
				isPlaying: request.localIsPlaying ? true : false,
				artworkURL: artworkURL
			};
		};
		const fromApplication = function (bundleIdentifier) {
			try {
				const app = Application(bundleIdentifier);
				// Sending an Apple Event to an app that is not running launches it
				if (!app.running()) { return null; }
				const state = app.playerState();
				if (state === "stopped") { return null; }
				const track = app.currentTrack;
				let artworkURL = null;
				if (bundleIdentifier === "com.spotify.client") {
					try { artworkURL = track.artworkUrl() || null; } catch (e) {}
				}
				return {
					source: "applescript",
					bundleIdentifier: bundleIdentifier,
					parentApplicationBundleIdentifier: null,
					displayName: null,
					title: track.name() || null,
					artist: track.artist() || null,
					album: track.album() || null,
					isPlaying: state === "playing",
					artworkURL: artworkURL
				};
			} catch (e) {
				return null;
			}
		};
		let pending = "";
		let last = null;
		while (true) {
			// Blocks, without using CPU, until Pock asks for an update. Empty data means stdin was closed.
			const data = input.availableData;
			if (Number(data.length) === 0) { return; }
			pending += ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding)) || "";
			const lines = pending.split("\n");
			pending = lines.pop();
			if (lines.length === 0) { continue; }
			const running = lines[lines.length - 1].split(",").filter(function (value) {
				return players.indexOf(value) >= 0;
			});
			let state = null;
			try { state = fromMediaRemote(); } catch (e) { state = null; }
			for (let i = 0; state === null && i < running.length; i++) {
				state = fromApplication(running[i]);
			}
			if (state === null) {
				state = { source: "none", isPlaying: false };
			}
			const line = JSON.stringify(state);
			if (line !== last) {
				last = line;
				out.writeData($(line + "\n").dataUsingEncoding($.NSUTF8StringEncoding));
			}
		}
	}
	"""#

}
