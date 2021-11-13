//
//  PlayerControlsViewController.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 11/6/21.
//  Copyright © 2021 Tortuga Power. All rights reserved.
//

import BookPlayerKit
import Combine
import Themeable
import UIKit

class PlayerControlsViewController: BaseViewController<PlayerControlsCoordinator, PlayerControlsViewModel>, Storyboarded {
  @IBOutlet weak var mainContainterStackView: UIStackView!
  @IBOutlet weak var playbackContainerStackView: UIStackView!
  @IBOutlet weak var boostContainerStackView: UIStackView!

  @IBOutlet weak var separatorView: UIView!
  @IBOutlet weak var playbackLabel: UILabel!
  @IBOutlet weak var currentSpeedLabel: UILabel!
  @IBOutlet weak var stepperControl: UIStepper!

  @IBOutlet weak var boostLabel: UILabel!
  @IBOutlet weak var boostWarningLabel: UILabel!
  @IBOutlet weak var boostSwitchControl: UISwitch!

  private var disposeBag = Set<AnyCancellable>()

  override func viewDidLoad() {
    super.viewDidLoad()

    self.setupUI()
    self.setupAccessibility()
    self.bindObservers()

    self.setUpTheming()
  }

  func setupUI() {
    self.navigationItem.title = "settings_controls_title".localized
    self.playbackLabel.text = "player_speed_title".localized
    self.boostLabel.text = "settings_boostvolume_title".localized
    self.boostWarningLabel.text = "settings_boostvolume_description".localized

    self.stepperControl.minimumValue = self.viewModel.getMinimumSpeedValue()
    self.stepperControl.maximumValue = self.viewModel.getMaximumSpeedValue()
    self.stepperControl.value = self.viewModel.getCurrentSpeed()
    self.stepperControl.stepValue = 0.05

    self.mainContainterStackView.setCustomSpacing(5, after: self.boostContainerStackView)

    self.boostSwitchControl.setOn(self.viewModel.getBoostVolumeFlag(), animated: false)
  }

  func setupAccessibility() {
    if let playbackContainerStackView = self.playbackContainerStackView,
        let boostContainerStackView = self.boostContainerStackView {
      self.mainContainterStackView.accessibilityElements = [playbackContainerStackView,
                                                            boostContainerStackView]
    }

    self.boostLabel.accessibilityHint = "settings_boostvolume_description".localized
    self.boostWarningLabel.isAccessibilityElement = false
  }

  func bindObservers() {
    self.boostSwitchControl.publisher(for: .valueChanged)
      .sink { control in
        guard let switchControl = control as? UISwitch else { return }

        self.viewModel.handleBoostVolumeToggle(flag: switchControl.isOn)
      }
      .store(in: &disposeBag)

    self.stepperControl.publisher(for: .valueChanged)
      .sink { control in
        guard let stepper = control as? UIStepper else { return }

        self.viewModel.handleSpeedChange(newValue: stepper.value)
      }
      .store(in: &disposeBag)

    self.viewModel.currentSpeedPublisher().sink { [weak self] speed in
      guard let self = self else { return }

      let formattedSpeed = self.formatSpeed(speed)
      self.currentSpeedLabel.text = formattedSpeed
      self.currentSpeedLabel.accessibilityLabel = String(describing: formattedSpeed + " \("speed_title".localized)")
    }
    .store(in: &disposeBag)
  }

  @IBAction func done(_ sender: UIBarButtonItem?) {
    self.viewModel.dismiss()
  }
}

extension PlayerControlsViewController: Themeable {
  func applyTheme(_ theme: SimpleTheme) {
    self.view.backgroundColor = theme.systemBackgroundColor
    self.separatorView.backgroundColor = theme.secondaryColor

    self.currentSpeedLabel.textColor = theme.primaryColor
    self.boostLabel.textColor = theme.primaryColor
    self.boostSwitchControl.tintColor = theme.linkColor

    self.overrideUserInterfaceStyle = theme.useDarkVariant
      ? UIUserInterfaceStyle.dark
      : UIUserInterfaceStyle.light
  }
}
