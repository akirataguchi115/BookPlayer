//
//  PlayerControlsCoordinator.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 11/6/21.
//  Copyright © 2021 Tortuga Power. All rights reserved.
//

import UIKit
import BookPlayerKit

class PlayerControlsCoordinator: Coordinator {
  let playerManager: PlayerManager
  let dataManager: DataManager

  init(navigationController: UINavigationController,
       playerManager: PlayerManager,
       dataManager: DataManager) {
    self.playerManager = playerManager
    self.dataManager = dataManager

    super.init(navigationController: navigationController,
               flowType: .modal)
  }

  override func start() {
    let vc = PlayerControlsViewController.instantiate(from: .Player)
    let viewModel = PlayerControlsViewModel(playerManager: self.playerManager,
                                            dataManager: self.dataManager)
    viewModel.coordinator = self
    vc.viewModel = viewModel

    let nav = AppNavigationController.instantiate(from: .Main)
    nav.navigationBar.prefersLargeTitles = false
    nav.viewControllers = [vc]
    nav.presentationController?.delegate = self

    if #available(iOS 15.0, *),
       let sheet = nav.sheetPresentationController {
      sheet.detents = [.medium()]
    }

    self.presentingViewController?.present(nav, animated: true, completion: nil)
  }
}
