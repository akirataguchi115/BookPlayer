//
//  PlayerControlsButton.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 6/11/21.
//  Copyright © 2021 Tortuga Power. All rights reserved.
//

import BookPlayerKit
import Themeable
import UIKit

class PlayerControlsButton: UIButton {

  override func layoutSubviews() {
    super.layoutSubviews()

    titleEdgeInsets = UIEdgeInsets(top: 0,
                                   left: -10,
                                   bottom: 0,
                                   right: 0)
    imageEdgeInsets = UIEdgeInsets(top: 0,
                                   left: -30,
                                   bottom: 0,
                                   right: 0)
    if let titleLabel = titleLabel {
      var frame = titleLabel.frame
      frame.origin.y = 3
      frame.size.height = frame.height + 4
      frame.size.width = frame.width + 20
      titleLabel.frame = frame
    }
  }

  init(title: String) {
    super.init(frame: CGRect(x: 0, y: 0, width: 92, height: 25))

    self.setup()

    self.setCustomTitle(title: title)
  }

  required init(coder aDecoder: NSCoder) {
    fatalError("Use init(title:)")
  }

  required override init(frame: CGRect) {
    fatalError("Use init(title:)")
  }

  private func setup() {
    self.setImage(
      UIImage(systemName: "slider.horizontal.3",
              withConfiguration: UIImage.SymbolConfiguration(pointSize: 25,
                                                             weight: .light)),
      for: .normal
    )

    self.titleLabel?.textAlignment = .center
    self.titleLabel?.layer.masksToBounds = true
    self.titleLabel?.layer.cornerRadius = 9.5

    setUpTheming()
  }

  func setCustomTitle(title: String) {
    self.setAttributedTitle(
      NSAttributedString(string: title,
                         attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 12.0, weight: .semibold)]),
      for: .normal
    )
  }
}

extension PlayerControlsButton: Themeable {
  func applyTheme(_ theme: SimpleTheme) {
    self.titleLabel?.textColor = .white
    self.titleLabel?.backgroundColor = theme.secondaryColor
  }
}
