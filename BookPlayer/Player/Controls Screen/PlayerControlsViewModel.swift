//
//  PlayerControlsViewModel.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 11/6/21.
//  Copyright © 2021 Tortuga Power. All rights reserved.
//

import BookPlayerKit
import Combine
import Foundation

class PlayerControlsViewModel: BaseViewModel<PlayerControlsCoordinator> {
  let playerManager: PlayerManager

  init(playerManager: PlayerManager) {
    self.playerManager = playerManager
  }

  func currentSpeedPublisher() -> AnyPublisher<Float, Never> {
    return SpeedManager.shared.currentSpeed.eraseToAnyPublisher()
  }

  func getMinimumSpeedValue() -> Double {
    return SpeedManager.shared.minimumSpeed
  }

  func getMaximumSpeedValue() -> Double {
    return SpeedManager.shared.maximumSpeed
  }

  func getCurrentSpeed() -> Double {
    return Double(SpeedManager.shared.getSpeed())
  }

  func getBoostVolumeFlag() -> Bool {
    return UserDefaults.standard.bool(forKey: Constants.UserDefaults.boostVolumeEnabled.rawValue)
  }

  func handleBoostVolumeToggle(flag: Bool) {
    UserDefaults.standard.set(flag, forKey: Constants.UserDefaults.boostVolumeEnabled.rawValue)

    playerManager.boostVolume = flag
  }

  func handleSpeedChange(newValue: Double) {
    let roundedValue = round(newValue * 100) / 100.0

    SpeedManager.shared.setSpeed(Float(roundedValue), currentBook: self.playerManager.currentBook)
  }

  func dismiss() {
    self.coordinator.didFinish()
  }
}
