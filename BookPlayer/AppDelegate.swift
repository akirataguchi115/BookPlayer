//
// AppDelegate.swift
// BookPlayer
//
// Created by Gianni Carlo on 7/1/16.
// Copyright © 2016 Tortuga Power. All rights reserved.
//

import AVFoundation
import BookPlayerKit
import CoreData
import DirectoryWatcher
import Intents
import MediaPlayer
import Sentry
import SwiftyStoreKit
import UIKit
import WatchConnectivity

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  let coordinator = LoadingCoordinator(
    navigationController: UINavigationController(),
    loadingViewController: LoadingViewController.instantiate(from: .Main)
  )
  var wasPlayingBeforeInterruption: Bool = false
  var watcher: DirectoryWatcher?
  var keyWindowRootVC: UIViewController? {
    return UIApplication.shared.connectedScenes.filter({ $0.activationState == .foregroundActive })
      .compactMap({ $0 as? UIWindowScene }).first?.windows
      .filter({ $0.isKeyWindow }).first?.rootViewController
  }

  var topController: UIViewController? {
    var topController = AppDelegate.delegateInstance.keyWindowRootVC

    while let newTopController = topController?.presentedViewController {
      topController = newTopController
    }

    return topController
  }

  static var delegateInstance: AppDelegate {
    // swiftlint:disable force_cast
    return (UIApplication.shared.delegate as! AppDelegate)
    // swiftlint:enable force_cast
  }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        let defaults: UserDefaults = UserDefaults.standard

        // Perfrom first launch setup
        if !defaults.bool(forKey: Constants.UserDefaults.completedFirstLaunch.rawValue) {
            // Set default settings
            defaults.set(true, forKey: Constants.UserDefaults.chapterContextEnabled.rawValue)
            defaults.set(true, forKey: Constants.UserDefaults.smartRewindEnabled.rawValue)
            defaults.set(true, forKey: Constants.UserDefaults.completedFirstLaunch.rawValue)
        }

        // Appearance
        UINavigationBar.appearance().titleTextAttributes = [
            NSAttributedString.Key.foregroundColor: UIColor(hex: "#37454E")
        ]

        if #available(iOS 11, *) {
            UINavigationBar.appearance().largeTitleTextAttributes = [
                NSAttributedString.Key.foregroundColor: UIColor(hex: "#37454E")
            ]
        }

        try? AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback, mode: AVAudioSession.Mode(rawValue: convertFromAVAudioSessionMode(AVAudioSession.Mode.spokenAudio)), options: [])

        // register to audio-interruption notifications
        NotificationCenter.default.addObserver(self, selector: #selector(self.handleAudioInterruptions(_:)), name: AVAudioSession.interruptionNotification, object: nil)

        // update last played book on watch app
        NotificationCenter.default.addObserver(self, selector: #selector(self.sendApplicationContext), name: .bookPlayed, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(self.messageReceived), name: .messageReceived, object: nil)

        // register for remote events
        self.setupMPRemoteCommands()
        // register document's folder listener
        self.setupDocumentListener()
        // setup store required listeners
        self.setupStoreListener()

        // Create a Sentry client
        SentrySDK.start { options in
            options.dsn = "https://23b4d02f7b044c10adb55a0cc8de3881@sentry.io/1414296"
            options.debug = false
        }

      self.coordinator.start()

      self.window = UIWindow(frame: UIScreen.main.bounds)
      self.window?.rootViewController = self.coordinator.navigationController
      self.window?.makeKeyAndVisible()

      if let activityDictionary = launchOptions?[.userActivityDictionary] as? [UIApplication.LaunchOptionsKey: Any],
          let activityType = activityDictionary[.userActivityType] as? String,
          activityType == Constants.UserActivityPlayback {
          self.playLastBook()
      }

      return true
    }

    // Handles audio file urls, like when receiving files through AirDrop
    // Also handles custom URL scheme 'bookplayer://'
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
      ActionParserService.process(url)
      return true
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        ActionParserService.process(userActivity)

        return true
    }

    func application(_ application: UIApplication, handle intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void) {
        ActionParserService.process(intent)

        let response = INPlayMediaIntentResponse(code: .success, userActivity: nil)
        completionHandler(response)
    }

  func applicationDidBecomeActive(_ application: UIApplication) {
    // Check if the app is on the PlayerViewController
    guard let navigationVC = self.keyWindowRootVC,
          navigationVC.presentedViewController?.presentedViewController is PlayerViewController else {
            return
          }

    // Notify controller to see if it should ask for review
    NotificationCenter.default.post(name: .requestReview, object: nil)
  }

    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        self.playLastBook()
    }

    @objc func messageReceived(_ notification: Notification) {
        guard
            let message = notification.userInfo as? [String: Any],
            let action = CommandParser.parse(message) else {
            return
        }

        DispatchQueue.main.async {
            ActionParserService.handleAction(action)
        }
    }

    @objc func sendApplicationContext() {
      guard let mainCoordinator = self.coordinator.getMainCoordinator() else { return }
      mainCoordinator.watchConnectivityService.sendApplicationContext()
    }

    // Playback may be interrupted by calls. Handle pause
    @objc func handleAudioInterruptions(_ notification: Notification) {
      guard let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue),
            let mainCoordinator = self.coordinator.getMainCoordinator() else {
            return
        }

        switch type {
        case .began:
          if mainCoordinator.playerManager.isPlaying {
            mainCoordinator.playerManager.pause(fade: false)
          }
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }

            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
              mainCoordinator.playerManager.play()
            }
            @unknown default:
            break
        }
    }

  override func accessibilityPerformMagicTap() -> Bool {
    guard let mainCoordinator = self.coordinator.getMainCoordinator(),
          mainCoordinator.playerManager.currentItem != nil else {
            UIAccessibility.post(notification: .announcement, argument: "voiceover_no_title".localized)
            return false
          }

    mainCoordinator.playerManager.playPause()
    return true
  }

  func setupMPRemoteCommands() {
    self.setupMPPlaybackRemoteCommands()
    self.setupMPSkipRemoteCommands()

    MPRemoteCommandCenter.shared().bookmarkCommand.localizedTitle = "bookmark_create_title".localized
    // Enabling this makes the rewind button disappear in the lock screen
    MPRemoteCommandCenter.shared().bookmarkCommand.isEnabled = false
    MPRemoteCommandCenter.shared().bookmarkCommand.addTarget { _ in
      guard let mainCoordinator = self.coordinator.getMainCoordinator(),
            let currentBook = mainCoordinator.playerManager.currentItem else { return .commandFailed }

      _ = mainCoordinator.libraryService.createBookmark(at: currentBook.currentTime,
                                                        relativePath: currentBook.relativePath,
                                                        type: .user)

      return .success
    }
  }

  func setupMPPlaybackRemoteCommands() {
    // Play / Pause
    MPRemoteCommandCenter.shared().togglePlayPauseCommand.isEnabled = true
    MPRemoteCommandCenter.shared().togglePlayPauseCommand.addTarget { (_) -> MPRemoteCommandHandlerStatus in
      guard let mainCoordinator = self.coordinator.getMainCoordinator() else { return .commandFailed }

      mainCoordinator.playerManager.playPause()
      return .success
    }

    MPRemoteCommandCenter.shared().playCommand.isEnabled = true
    MPRemoteCommandCenter.shared().playCommand.addTarget { (_) -> MPRemoteCommandHandlerStatus in
      guard let mainCoordinator = self.coordinator.getMainCoordinator() else { return .commandFailed }

      mainCoordinator.playerManager.play()
      return .success
    }

    MPRemoteCommandCenter.shared().pauseCommand.isEnabled = true
    MPRemoteCommandCenter.shared().pauseCommand.addTarget { (_) -> MPRemoteCommandHandlerStatus in
      guard let mainCoordinator = self.coordinator.getMainCoordinator() else { return .commandFailed }

      mainCoordinator.playerManager.pause(fade: false)
      return .success
    }

    MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = true
    MPRemoteCommandCenter.shared().changePlaybackPositionCommand.addTarget { [weak self] remoteEvent in
      guard let self = self,
            let mainCoordinator = self.coordinator.getMainCoordinator(),
            let currentItem = mainCoordinator.playerManager.currentItem,
            let event = remoteEvent as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }

      var newTime = event.positionTime

      if UserDefaults.standard.bool(forKey: Constants.UserDefaults.chapterContextEnabled.rawValue),
         let currentChapter = currentItem.currentChapter {
        newTime += currentChapter.start
      }

      mainCoordinator.playerManager.jumpTo(newTime)

      return .success
    }
  }

  // For now, seek forward/backward and next/previous track perform the same function
  func setupMPSkipRemoteCommands() {
    // Forward
    MPRemoteCommandCenter.shared().skipForwardCommand.preferredIntervals = [NSNumber(value: PlayerManager.forwardInterval)]
    MPRemoteCommandCenter.shared().skipForwardCommand.addTarget { (_) -> MPRemoteCommandHandlerStatus in
      guard let mainCoordinator = self.coordinator.getMainCoordinator() else { return .commandFailed }

      mainCoordinator.playerManager.forward()
      return .success
    }

    MPRemoteCommandCenter.shared().nextTrackCommand.addTarget { (_) -> MPRemoteCommandHandlerStatus in
      guard let mainCoordinator = self.coordinator.getMainCoordinator() else { return .commandFailed }

      mainCoordinator.playerManager.forward()
      return .success
    }

    MPRemoteCommandCenter.shared().seekForwardCommand.addTarget { (commandEvent) -> MPRemoteCommandHandlerStatus in
      guard let cmd = commandEvent as? MPSeekCommandEvent, cmd.type == .endSeeking else {
        return .success
      }

      guard let mainCoordinator = self.coordinator.getMainCoordinator() else { return .success }

      // End seeking
      mainCoordinator.playerManager.forward()
      return .success
    }

    // Rewind
    MPRemoteCommandCenter.shared().skipBackwardCommand.preferredIntervals = [NSNumber(value: PlayerManager.rewindInterval)]
    MPRemoteCommandCenter.shared().skipBackwardCommand.addTarget { (_) -> MPRemoteCommandHandlerStatus in
      guard let mainCoordinator = self.coordinator.getMainCoordinator() else { return .commandFailed }

      mainCoordinator.playerManager.rewind()
      return .success
    }

    MPRemoteCommandCenter.shared().previousTrackCommand.addTarget { (_) -> MPRemoteCommandHandlerStatus in
      guard let mainCoordinator = self.coordinator.getMainCoordinator() else { return .commandFailed }

      mainCoordinator.playerManager.rewind()
      return .success
    }

    MPRemoteCommandCenter.shared().seekBackwardCommand.addTarget { (commandEvent) -> MPRemoteCommandHandlerStatus in
      guard let cmd = commandEvent as? MPSeekCommandEvent, cmd.type == .endSeeking else {
        return .success
      }

      guard let mainCoordinator = self.coordinator.getMainCoordinator() else { return .success }

      // End seeking
      mainCoordinator.playerManager.rewind()
      return .success
    }
  }

  func setupDocumentListener() {
    let documentsUrl = DataManager.getDocumentsFolderURL()

    self.watcher = DirectoryWatcher.watch(documentsUrl)
    self.watcher?.ignoreDirectories = false

    self.watcher?.onNewFiles = { newFiles in
      guard let mainCoordinator = self.coordinator.getMainCoordinator(),
            let libraryCoordinator = mainCoordinator.getLibraryCoordinator() else {
        return
      }

      libraryCoordinator.processFiles(urls: newFiles)
    }
  }

    func setupStoreListener() {
        SwiftyStoreKit.completeTransactions(atomically: true) { purchases in
            for purchase in purchases {
                guard purchase.transaction.transactionState == .purchased
                    || purchase.transaction.transactionState == .restored
                else { continue }

                UserDefaults.standard.set(true, forKey: Constants.UserDefaults.donationMade.rawValue)
                NotificationCenter.default.post(name: .donationMade, object: nil)

                if purchase.needsFinishTransaction {
                    SwiftyStoreKit.finishTransaction(purchase.transaction)
                }
            }
        }

        SwiftyStoreKit.shouldAddStorePaymentHandler = { _, _ in
            true
        }
    }
}

// MARK: - Actions (custom scheme)

extension AppDelegate {
  func playLastBook() {
    guard let mainCoordinator = self.coordinator.getMainCoordinator(),
          mainCoordinator.playerManager.hasLoadedBook() else {
      UserDefaults.standard.set(true, forKey: Constants.UserActivityPlayback)
      return
    }

    mainCoordinator.playerManager.play()
  }

  func showPlayer() {
    guard let mainCoordinator = self.coordinator.getMainCoordinator(),
          mainCoordinator.playerManager.hasLoadedBook() else {
      UserDefaults.standard.set(true, forKey: Constants.UserDefaults.showPlayer.rawValue)
      return
    }

    if !mainCoordinator.hasPlayerShown() {
      mainCoordinator.showPlayer()
    }
  }
}

// Helper function inserted by Swift 4.2 migrator.
private func convertFromAVAudioSessionMode(_ input: AVAudioSession.Mode) -> String {
    return input.rawValue
}
