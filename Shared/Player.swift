//
//  Player.swift
//  FinTune
//
//  Created by Jack Caulfield on 10/12/21.
//

import Foundation
import SwiftUI
import Combine
import AVFoundation
import MediaPlayer
import JellyfinAPI

open class AVPlayerItemId: AVPlayerItem, Identifiable{
    public let id = UUID().uuidString
    public var initialOrder: Int
    public let song: Song
    public let playSessionId: String
    private var cancellables = Set<AnyCancellable>()
    static let networkingManager = NetworkingManager.shared
            
    init(song: Song, localAsset: AVURLAsset, order: Int){
        self.playSessionId = "\(Double.random(in: 0..<1496213367201))".replacingOccurrences(of: ".", with: "")
        self.song = song
        self.initialOrder = order
        super.init(asset: localAsset, automaticallyLoadedAssetKeys: nil)
    }
    
    init(song: Song, order: Int){
        let seshId = "\(Double.random(in: 0..<1496213367201))".replacingOccurrences(of: ".", with: "")

        self.playSessionId = seshId
        self.song = song
        self.initialOrder = order

        let headers: [String: String] = [ "X-Emby-Token": AVPlayerItemId.networkingManager.accessToken ]
        let assetItem = AVURLAsset(url: AVPlayerItemId.getStream(songId: song.jellyfinId!, sessionId: seshId), options: [
            "AVURLAssetHTTPHeaderFieldsKey": headers,
            AVURLAssetPreferPreciseDurationAndTimingKey : true
        ])
                
        super.init(asset: assetItem, automaticallyLoadedAssetKeys: nil)
    }
    
    public static func getStream(songId: String, sessionId: String) -> URL{
        let container = "opus,mp3,aac,m4a,flac,webma,webm,wav,ogg,mpa,wma"
        
        let transcodingContainer = "m4a"

        var streamEndpointComponents = URLComponents()
        
        streamEndpointComponents.scheme = "https"
        streamEndpointComponents.host = AVPlayerItemId.networkingManager.server.replacingOccurrences(of: "https://", with: "")
        streamEndpointComponents.path = "/Audio/\(songId)/universal"
        streamEndpointComponents.queryItems = [
            URLQueryItem(name: "UserId", value: AVPlayerItemId.networkingManager.userId),
            URLQueryItem(name: "DeviceId", value: UIDevice.current.identifierForVendor!.uuidString),
            URLQueryItem(name: "Container", value: container),
            URLQueryItem(name: "TranscodingContainer", value: transcodingContainer),
            URLQueryItem(name: "TranscodingProtocol", value: "hls"),
            URLQueryItem(name: "api_key", value: AVPlayerItemId.networkingManager.accessToken),
            URLQueryItem(name: "StartTimeTicks", value: "0"),
            URLQueryItem(name: "EnableRedirection", value: "true"),
            URLQueryItem(name: "EnableRemoteMedia", value: "true"),
            URLQueryItem(name: "PlaySessionId", value: sessionId)
        ]
        
        print(streamEndpointComponents.url!)
        
        return streamEndpointComponents.url!
    }
}

public struct From{
    let name: String
    let id: String
    let type: parentType
}

public enum parentType{
    case album, playlist, allSongs, topSongs, artist
}

class Player: ObservableObject {

    static let shared = Player()
    let session = AVAudioSession.sharedInstance()
	let imageManager : ImageManager = ImageManager.shared
    
    let queue = DispatchQueue(label: "playerQueue", qos: .userInteractive, attributes: .concurrent)
        
    public enum PlayMode {
        case random, ordered
        
        mutating public func toggle() {
            switch self {
            case .random:
                self = .ordered
            case .ordered:
                self = .random
            }
        }
    }
    
    public enum RepeatMode {
        case none, reapeatAll, repeatOne
        
        mutating public func toggle() {
            switch self {
            case .none:
                self = .reapeatAll
            case .reapeatAll:
                self = .repeatOne
            case .repeatOne:
                self = .none
            }
        }
    }
    
    @Published public var songs: [AVPlayerItemId] = [] {
        didSet {
            if player != nil {
                if let current = player?.currentItem{
                    for queuedItem in player?.items() ?? []{
                        if queuedItem != current {
                            player?.remove(queuedItem)
                        }
                    }
					
                    songIndex = songs.firstIndex(where: {(current as! AVPlayerItemId).song.id == $0.song.id}) ?? 0
                    for song in songs[(currentSong != nil ? (songIndex + 1) : songIndex)...]{
                        player!.insert(song, after: nil)
                    }
                }else{
                    player?.removeAllItems()

                    
                    
                    player = AVQueuePlayer(items: Array(songs[songIndex...].map{ self.toPlayerItem($0.song, order: $0.initialOrder) }))
                }
                currentSong = songs[songIndex]
            }else if !songs.isEmpty{
                player = AVQueuePlayer(items: songs)
                player?.preventsDisplaySleepDuringVideoPlayback = false
                currentSong = songs[songIndex]
                setupBackgroundPlay()
            }            
        }
    }
    
    // @Published
    public var history: [AVPlayerItemId] = [] {
        didSet{
            if history.count > 100{
                history.removeFirst(-100 + history.count)
            }
        }
    }
    
    public func removeSong(song: AVPlayerItemId){
        player?.remove(song)
        let index = Player.shared.songs.sorted{ $0.initialOrder < $1.initialOrder }.firstIndex(of: song)!
        songs.remove(at: index)
        if songs.count >= index{
            for nextSong in songs.sorted(by: { $0.initialOrder < $1.initialOrder })[index...]{
                nextSong.initialOrder += -1
            }
        }
    }
    
	@Published
	public var currentArtist: Artist?
	
    @Published
    public var currentSong: AVPlayerItemId?
    {
        didSet {
            var dto = PlaybackProgressInfo()
            
            dto.playSessionId = self.currentSong?.playSessionId
            dto.itemId = self.currentSong?.song.jellyfinId!
            dto.isPaused = !self.isPlaying
            
            PlaystateAPI.reportPlaybackProgress(playbackProgressInfo: dto, apiResponseQueue: AVPlayerItemId.networkingManager.processingQueue)
                .sink(receiveCompletion: { complete in
                    
                }, receiveValue: {
                    
                })
                .store(in: &AVPlayerItemId.networkingManager.cancellables)

            duration =  currentSong?.song.runTime ?? "0:00"
            timeElasped = "0:00"
			
			if let currentSong = currentSong {
				currentArtist = NetworkingManager.shared.retrieveArtistByName(name: currentSong.song.album!.albumArtistName!, context: NetworkingManager.shared.context)
			}
        }
    }
    public var songIndex: Int = 0
    private let placeholderImage = UIImage(named: "placeholder")!
//    @Published public var currentSongImage: UIImage = UIImage(named: "Placeholder")! {
//        didSet{
//            currentSongImage.getColors { colors in
//                if colors != nil && self.currentSongImage != self.placeholderImage {
//                    self.colors = colors!
//                    let temp: [UIColor] = [colors!.background!, colors!.detail!, colors!.primary!, colors!.secondary!]
//                        .sorted{ $0.getColorDifference() < $1.getColorDifference() }
//                    self.color = Color(temp[Int.random(in: 1...2)])
//                }
//              }
//        }
//    }
        
    @Published
    public var isPlaying = false {
        didSet {
            if isPlaying {
                setupBackgroundPlay()

                player?.play()
                
                var dto = PlaybackStartInfo()
                
                dto.playSessionId = self.currentSong?.playSessionId
                dto.itemId = self.currentSong?.song.jellyfinId
                dto.isPaused = false
                
                PlaystateAPI.reportPlaybackStart(playbackStartInfo: dto, apiResponseQueue: AVPlayerItemId.networkingManager.processingQueue)
                    .sink(receiveCompletion: { complete in
                        
                    }, receiveValue: {
                        
                    })
                    .store(in: &AVPlayerItemId.networkingManager.cancellables)
                
            } else {
                player?.pause()
                
                var dto = PlaybackProgressInfo()
                
                dto.playSessionId = self.currentSong?.playSessionId
                dto.itemId = self.currentSong?.song.jellyfinId!
                dto.isPaused = true
                
                PlaystateAPI.reportPlaybackProgress(playbackProgressInfo: dto, apiResponseQueue: AVPlayerItemId.networkingManager.processingQueue)
                    .sink(receiveCompletion: { complete in
                        
                    }, receiveValue: {
                        
                    })
                    .store(in: &AVPlayerItemId.networkingManager.cancellables)
            }
            
            setupPlayTimer()
            MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        }
    }
    
    @Published
    public var playmode = PlayMode.ordered {
        didSet {
            
            // order or shuffle the songs
            var newOrder = playmode == .random ? self.songs.shuffled() : self.songs.sorted(by: { $0.initialOrder < $1.initialOrder})
            if currentSong != nil{
                if playmode == .random {
                    self.songIndex = 0
                    // place the currently playing song at 0
                    newOrder.move(currentSong!, to: 0)
                } else {
                    self.songIndex = currentSong!.initialOrder
                    print(self.songIndex)
                }
                self.currentSong = player?.currentItem as? AVPlayerItemId
            }
            self.songs = newOrder
        }
    }
    @Published
    public var repeatMode = RepeatMode.none
//    @Published
    public var duration = "0:00"
//    @Published
    public var timeElasped = "0:00"
//    @Published
    public var timeRemaining = "0:00"
//    @Published
    public var playProgress: Float = 0
    @Published
    public var trigger: Bool = false
    @Published
    public var seeking: Bool = false {
        didSet{
            if !seeking{
                refreshPlayingInfo()
            }
        }
    }
    
    public var player: AVQueuePlayer?
    private var timeTimer: Timer?
//    @Published public var animationTimer = Timer.publish(every: 9, on: .main, in: .common).autoconnect()
    init() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                               object: player?.currentItem,
                                               queue: .main) { [weak self] _ in
                                                guard let self = self else { return }
                                                switch self.playmode {
                                                case .random:
                                                    self.currentSong = self.songs.randomElement()
                                                    self.isPlaying = true
                                                case .ordered:
                                                    // scheduleNext check repeat1 mode
                                                    self.scheduleNext()
                                                }
        }
        
        nc.addObserver(self,
                           selector: #selector(handleInterruption),
                           name: AVAudioSession.interruptionNotification,
                           object: player?.currentItem)
        
        nc.addObserver(self,
                       selector: #selector(handleRouteChange),
                       name: AVAudioSession.routeChangeNotification,
                       object: nil)
        
        self.setupRemoteCommands()
    }

    @objc func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
        }
        
        // Switch over the route change reason.
        switch reason {

        case .newDeviceAvailable: // New device found, continue playback
            let session = AVAudioSession.sharedInstance()
            hasHeadphones(in: session.currentRoute)
        
        case .oldDeviceUnavailable: // Old device removed, stop playback
            if let previousRoute =
                userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
                self.isPlaying = false
            }
                    
        default: ()
            self.isPlaying = false
        }
    }

    func hasHeadphones(in routeDescription: AVAudioSessionRouteDescription) -> Bool {
        // Filter the outputs to only those with a port type of headphones.
		return !routeDescription.outputs.filter({$0.portType == .headphones}).isEmpty
    }
    
    @objc func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
        }

        // Switch over the interruption type.
        switch type {

        case .began:
            print("Interuption began")
            isPlaying = false
            
        case .ended:
            print("Interuption ended")
           // An interruption ended. Resume playback, if appropriate.

            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                // Interruption ended. Playback should resume.
                print("Should resume")
                player?.play()
            }else{
                if let time = player?.currentTime(), player?.currentItem != nil{
                    self.player?.removeAllItems()
                    self.currentSong = nil
                    self.songs.append(contentsOf: [])
                    player?.seek(to: time)
                    print("seeked to \(time)")
                }
            }
        default: ()
			isPlaying = false
        }
    }
    
    private func addToHistory() -> Void {
        if currentSong != nil && history.last?.song.id != currentSong!.song.id{
            history.insert(currentSong!, at: history.count)
        }
    }

    public func loadSongs(_ songs: [Song], songId: String? = nil){

        addToHistory()
        
        self.isPlaying = false
        self.currentSong = nil
        
        let queueItems = songs.enumerated().map { (index, element) in
            return toPlayerItem(element, order: index)
        }
        
        // Order of the following operations are important
        player = player ?? AVQueuePlayer()
        player?.preventsDisplaySleepDuringVideoPlayback = false
        player?.removeAllItems()
		
		// If the songs are to be shuffled, then we'll do that and makee sure the song
		// the user intially selected is first
		if playmode == .random {
			
			// order or shuffle the songs
			var newOrder = playmode == .random ? queueItems.shuffled() : queueItems.sorted(by: { $0.initialOrder < $1.initialOrder})

			self.songIndex = 0
			
			let firstSong = newOrder.filter({ $0.song.jellyfinId! == songId }).first!
			
			// place the currently playing song at 0
			newOrder.move(firstSong, to: 0)
			
			self.songs = newOrder
		
		} else {
			songIndex = songs.firstIndex(where: { $0.jellyfinId! == songId}) ?? 0
			self.songs = queueItems
		}
    }
    
    private func toPlayerItem(_ song : Song, order: Int) -> AVPlayerItemId{
        
        // See if the item is marked as downloaded
        if song.downloaded {
            
            do {
                // Read song from file
                let fileManager = FileManager.default
                let documentDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)

                let soundURL = documentDirectory.appendingPathComponent("\(song.jellyfinId!).\(song.container ?? "aac")")
                
                let localAsset = AVURLAsset(url: soundURL)
                
                // Make sure the saved file can actually be played, otherwise we'll stream it
                guard localAsset.isPlayable else {
                    song.downloaded = false
                    song.downloading = false
                    return AVPlayerItemId(song: song, order: order)
                }
                
                return AVPlayerItemId(song: song, localAsset: localAsset, order: order)
            } catch {
                print("There was an error loading the downloaded song \(song.jellyfinId!). \(error)")
                return AVPlayerItemId(song: song, order: order)
            }
        }
        //Fallback to streaming or cache if we reach here
        return AVPlayerItemId(song: song, order: order)
    }
    
    public func appendSongsNext(_ songs: [Song]){
        var index = -1
        if currentSong != nil{
            index = self.songs.sorted{ $0.initialOrder < $1.initialOrder }.firstIndex(of: currentSong!)!
        }
        
        let songItems = songs.enumerated().map { (orderIndex, element) in
            return toPlayerItem(element, order: orderIndex + index + 1)
        }
        for song in self.songs.sorted(by: { $0.initialOrder < $1.initialOrder })[(index + 1)...]{
            song.initialOrder += songs.count
        }
        self.songs.insert(contentsOf: songItems, at: index + 1)
        print(self.songs.map({ $0.song.name! + " - \($0.initialOrder)"}))
    }

    public func appendSongsEnd(_ songs: [Song]){
        self.songs.append(contentsOf: songs.enumerated().map { (index, element) in
            return toPlayerItem(element, order: index + self.songs.count)
        })
    }

    public func scheduleNext() {
        changeSong(newIndex: repeatMode == .repeatOne ? 0 : 1)
    }
    
    public func next() {
        changeSong(newIndex: 1)
    }
    
    public func next(song: AVPlayerItemId) {
        changeSong(newIndex: songs.firstIndex(of: song)! - songIndex)
    }
    
    public func previous() {
        if timeElasped < "0:03" {
            changeSong(newIndex: -1)
            seek(progress: 0.0)
        }else{
            seek(progress: 0.0)
        }
    }
    
    private func changeSong(newIndex: Int, skipping: Bool = false) {
            playProgress = 0
        
            guard let current = currentSong,
                  var index = songs.firstIndex(where: { $0.id == current.id } ) else {
                    return
            }
            if !skipping{
                addToHistory()
            }
                    
        index += newIndex

            if index < songs.count && index >= 0 {
                let newSong = songs[index]
                currentSong = newSong
                songIndex = index
                if newIndex > 0 {
                    // Going foward
                    for _ in 1...newIndex {
                        player?.advanceToNextItem()
                    }
                }else if newIndex < 0 {
                    
                    // Check if we're already at the beginning of the queue
                    if newSong == player?.currentItem {
                        seek(progress: 0.0)
                    } else {
                        player?.insert(newSong, after: player?.currentItem)
                        let currentItem = player?.currentItem
                        seek(progress: 0.0)
                        player?.advanceToNextItem()
                        if currentItem != nil{
                            player?.insert(currentItem!, after: player?.currentItem)
                        }
                    }
                    
                }
                
                // Back up to the beginning of the song if we're repeating one
                else if repeatMode == .repeatOne{
                    seek(progress: 0.0)
                }
            } else if index == -1 {
                seek(progress: 0.0)
            } else {
                songIndex = 0
                isPlaying = false
                if songs.count > 0{
                    self.loadSongs(songs.map{ $0.song })
                    if repeatMode == .reapeatAll{
                        self.isPlaying = true
                    }
                }
            }
        setupBackgroundPlay()
    }
    
    private func setupRemoteCommands() {
        MPRemoteCommandCenter.shared().playCommand.addTarget { [weak self] event in
            if self?.isPlaying == false {
                self?.isPlaying = true
                return .success
            }
            return .commandFailed
        }

        MPRemoteCommandCenter.shared().pauseCommand.addTarget { [weak self] event in
            if self?.isPlaying == true {
                self?.isPlaying = false
                return .success
            }
            return .commandFailed
        }
        
        MPRemoteCommandCenter.shared().nextTrackCommand.addTarget { [weak self] event in
            self?.next()
            return .success
        }
        
        MPRemoteCommandCenter.shared().previousTrackCommand.addTarget { [weak self] event in
            self?.previous()
            return .success
        }
        
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.addTarget { [weak self] (event) -> MPRemoteCommandHandlerStatus in
            guard let self = self else {
                return .commandFailed
            }
            if let player = self.player {
                let playerRate = player.rate
                if let playbackPositionEvent = event as? MPChangePlaybackPositionCommandEvent {
                    player.seek(to: CMTime(seconds: playbackPositionEvent.positionTime, preferredTimescale: CMTimeScale(1000)), completionHandler: { [weak self] success in
                        guard let self = self else {
                            return
                        }
                        if success {
                            self.player?.rate = playerRate
                        }
                    })
                    
                    return .success
                }
                
                return .commandFailed
            }
            
            return .commandFailed
        }
    }
    
    private func setupBackgroundPlay() {
        if let currentItem = currentSong {
            do {
                try session.setCategory(AVAudioSession.Category.playback, options: [])
                try session.setActive(true, options: [])
            } catch {
                print("Failed to set session active")
            }
            UIApplication.shared.beginReceivingRemoteControlEvents()
            
            let info: [String: Any] = [
                MPMediaItemPropertyArtist: Builders.artistName(song: currentItem.song),
                MPMediaItemPropertyAlbumTitle: currentItem.song.album?.name ?? "Unknown Album",
                MPMediaItemPropertyTitle: currentItem.song.name ?? "Unknown Track",
                MPMediaItemPropertyArtwork: MPMediaItemArtwork(boundsSize: CGSize(width: 500, height: 500), requestHandler: { (size: CGSize) -> UIImage in
					
					if let album = self.currentSong?.song.album {
						if let image = self.getAlbumImage(album: album) {
							return UIImage(data: image)!
						}
					}
					
					return self.placeholderImage
                })
            ]
            MPNowPlayingInfoCenter.default().playbackState = self.isPlaying ? MPNowPlayingPlaybackState.playing : .paused
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                
        }
            
        else {
            self.isPlaying = false
    }
    }
    
	private func getAlbumImage(album : Album) -> Data? {
		
		if let image = imageManager.imageFor(itemId: album.jellyfinId!) {
			return image
		} else {
			imageManager.download(itemId: album.jellyfinId!, complete: { image in
				
				return image
			})
		}
		
		return nil
    }
    
    private func setupPlayTimer() {
        if isPlaying {
            if timeTimer != nil {
                timeTimer?.invalidate()
                timeTimer = nil
            }
                        
//            timeTimer = Timer.scheduledTimer(withTimeInterval: Globals.playProgressRefresh,
//                                             repeats: true,
//                                             block:
//                { [weak self] timer in
//
//                    self?.refreshPlayingInfo()
//                })
        } else {
            timeTimer?.invalidate()
            timeTimer = nil
        }
    }
    
    
    public func getRemainingTime() -> Double{
        if let duration = player?.currentItem?.duration.seconds,
           let playTime = player?.currentItem?.currentTime().seconds,
           !duration.isNaN, !playTime.isNaN{
            
            return duration - playTime - 0.1
        }
        return Double(0)
    }
    
    public func seek(progress: Double){
        if let duration = player?.currentItem?.duration.seconds {
            
            let durationSecs = duration
            let playTimeSecs = Double(durationSecs * progress)
            self.player?.seek(to: CMTime(seconds: playTimeSecs, preferredTimescale: 1), completionHandler: { _ in
                self.seeking = false
                self.trigger = true
            })
        }else{
            self.seeking = false
        }
    }
    
    public func refreshPlayingInfo() {
        
            
            if !seeking {
           
                if let duration : Double = player?.currentItem?.duration.seconds {
                                   
                    if !duration.isNaN {
                        
                        let playTime = player!.currentItem!.currentTime().seconds
                            
                        let durationSecs = Int(duration)
                        let durationSeconds = Int(durationSecs % 3600 ) % 60
                        let durationMinutes = Int(durationSecs % 3600) / 60
                        let durationString = "\(durationMinutes):\(String(format: "%02d", durationSeconds))"
                        self.duration = durationString
                        
                        let playTimeSecs = Int(playTime)
                        let playTimeSeconds = Int(playTimeSecs % 3600) % 60
                        let playTimeMinutes = Int(playTimeSecs % 3600) / 60
                        let timeElapsedString = "\(playTimeMinutes):\(String(format: "%02d", playTimeSeconds))"
                        self.timeElasped = timeElapsedString
                        
                        let remainingTimeSecs = Int(duration - playTime)
                        let remainingTimeSeconds = Int(remainingTimeSecs % 3600) % 60
                        let remainingTimeMinutes = Int(remainingTimeSecs % 3600) / 60
                        let remainingTimeString = "-\(remainingTimeMinutes):\(String(format: "%02d", remainingTimeSeconds))"
                        self.timeRemaining = remainingTimeString
                        
                        if(self.player != nil && self.player!.status == AVPlayer.Status.readyToPlay && self.player!.currentItem!.status == AVPlayerItem.Status.readyToPlay) {
                            self.playProgress = Float(playTime) / Float(duration)
                        }else{
                            self.playProgress = 0
                        }
//                        self.trigger = false

                        var infos = MPNowPlayingInfoCenter.default().nowPlayingInfo
                        infos?[MPMediaItemPropertyPlaybackDuration] = duration
                        infos?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playTime
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = infos
                    }
                }
        }
    }
    
    func getRuntime(ticks: Int) -> String{
        let reference = Date();
        let myDate = Date(timeInterval: (Double(ticks)/10000000.0),
                            since: reference);
        
        let difference = Calendar.current.dateComponents([.hour, .minute], from: reference, to: myDate)
        var runtimeString: [String] = []
        if difference.hour ?? 0 > 0{
            runtimeString.append(difference.hour! > 1 ? "\(difference.hour!) hours" : "\(difference.hour!) hour")
        }
        if difference.minute ?? 0 > 0{
            runtimeString.append(difference.minute! > 1 ? "\(difference.minute!) minutes" : "\(difference.minute!) minute")
        }
//        let formattedString = String(format: "%02ld%02ld", difference.hour!, difference.minute!)
        
        return runtimeString.joined(separator: " ")
    }
}
                                                           
                                                           

extension Array where Element: Equatable
{
    mutating func move(_ element: Element, to newIndex: Index) {
        if let oldIndex: Int = self.firstIndex(of: element) { self.move(from: oldIndex, to: newIndex) }
    }
}

extension Array
{
    mutating func move(from oldIndex: Index, to newIndex: Index) {
        // Don't work for free and use swap when indices are next to each other - this
        // won't rebuild array and will be super efficient.
        if oldIndex == newIndex { return }
        if abs(newIndex - oldIndex) == 1 { return self.swapAt(oldIndex, newIndex) }
        self.insert(self.remove(at: oldIndex), at: newIndex)
    }
}
