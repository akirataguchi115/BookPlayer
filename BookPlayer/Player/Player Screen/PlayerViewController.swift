//
//  PlayerViewController.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/8/21.
//  Copyright © 2021 Tortuga Power. All rights reserved.
//

import AVFoundation
import AVKit
import BookPlayerKit
import Combine
import MediaPlayer
import StoreKit
import Themeable
import UIKit

class PlayerViewController: BaseViewController<PlayerCoordinator, PlayerViewModel>, TelemetryProtocol, Storyboarded {
  @IBOutlet private weak var closeButton: UIButton!
  @IBOutlet private weak var closeButtonTop: NSLayoutConstraint!
  @IBOutlet private weak var bottomToolbar: UIToolbar!
  @IBOutlet weak var toolbarBottomConstraint: NSLayoutConstraint!
  @IBOutlet private var playerControlsBarItem: UIBarButtonItem!
  @IBOutlet private var chaptersButton: UIBarButtonItem!
  @IBOutlet private var bookmarkButton: UIBarButtonItem!
  @IBOutlet private weak var moreButton: UIBarButtonItem!

  @IBOutlet private weak var artworkControl: ArtworkControl!
  @IBOutlet private weak var progressSlider: ProgressSlider!
  @IBOutlet private weak var currentTimeLabel: UILabel!
  @IBOutlet private weak var chapterTitleButton: UIButton!
  @IBOutlet private weak var maxTimeButton: UIButton!
  @IBOutlet private weak var progressButton: UIButton!
  @IBOutlet weak var previousChapterButton: UIButton!
  @IBOutlet weak var nextChapterButton: UIButton!
  @IBOutlet weak var rewindIconView: PlayerJumpIconRewind!
  @IBOutlet weak var playIconView: PlayPauseIconView!
  @IBOutlet weak var forwardIconView: PlayerJumpIconForward!
  @IBOutlet weak var containerItemStackView: UIStackView!

  private let playerControlsButton = PlayerControlsButton(title: "1x")
  private var themedStatusBarStyle: UIStatusBarStyle?
  private var panGestureRecognizer: UIPanGestureRecognizer!
  private let dismissThreshold: CGFloat = 44.0 * UIScreen.main.nativeScale
  private var dismissFeedbackTriggered = false

  private var disposeBag = Set<AnyCancellable>()
  private var playingProgressSubscriber: AnyCancellable?

  // computed properties
  override var preferredStatusBarStyle: UIStatusBarStyle {
    let style = ThemeManager.shared.useDarkVariant ? UIStatusBarStyle.lightContent : UIStatusBarStyle.default
    return self.themedStatusBarStyle ?? style
  }

  // MARK: - Lifecycle
  override func viewDidLoad() {
    super.viewDidLoad()

    setup()

    setUpTheming()

    setupToolbar()

    setupGestures()

    bindGeneralObservers()

    bindProgressObservers()

    bindPlaybackControlsObservers()

    bindBookPlayingProgressEvents()

    bindTimerObserver()

    self.containerItemStackView.setCustomSpacing(26, after: self.artworkControl)
  }

  // Prevents dragging the view down from changing the safeAreaInsets.top and .bottom
  // Note: I'm pretty sure there is a better solution for this that I haven't found yet - @pichfl
  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()

    let window = UIApplication.shared.windows[0]
    let insets: UIEdgeInsets = window.safeAreaInsets

    self.closeButtonTop.constant = self.view.safeAreaInsets.top == 0.0 ? insets.top : 0
    self.toolbarBottomConstraint.constant = self.view.safeAreaInsets.bottom == 0.0 ? insets.bottom : 0
  }

  func setup() {
    self.closeButton.accessibilityLabel = "voiceover_dismiss_player_title".localized

    self.chapterTitleButton.titleLabel?.numberOfLines = 2
    self.chapterTitleButton.titleLabel?.textAlignment = .center
    self.chapterTitleButton.titleLabel?.lineBreakMode = .byWordWrapping
  }

  func setupPlayerView(with currentBook: Book) {
    guard !currentBook.isFault else { return }

    self.artworkControl.setupInfo(with: currentBook)

    self.updateView(with: self.viewModel.getCurrentProgressState(currentBook))

    applyTheme(self.themeProvider.currentTheme)

    // Solution thanks to https://forums.developer.apple.com/thread/63166#180445
    self.modalPresentationCapturesStatusBarAppearance = true

    self.setNeedsStatusBarAppearanceUpdate()
  }

  func updateView(with progressObject: ProgressObject, shouldSetSliderValue: Bool = true) {
    if shouldSetSliderValue && self.progressSlider.isTracking { return }

    self.currentTimeLabel.text = progressObject.formattedCurrentTime
    self.currentTimeLabel.accessibilityLabel = String(
      describing: String.localizedStringWithFormat(self.viewModel.getCurrentTimeVoiceOverPrefix(),
                                                   VoiceOverService.secondsToMinutes(progressObject.currentTime))
    )

    if let progress = progressObject.progress {
      self.progressButton.setTitle(progress, for: .normal)
    }

    if let maxTime = progressObject.maxTime,
       let formattedMaxTime = progressObject.formattedMaxTime {
      self.maxTimeButton.setTitle(formattedMaxTime, for: .normal)
      self.maxTimeButton.accessibilityLabel = String(
        describing: self.viewModel.getMaxTimeVoiceOverPrefix() + VoiceOverService.secondsToMinutes(maxTime)
      )
    }

    self.chapterTitleButton.setTitle(progressObject.chapterTitle, for: .normal)

    if shouldSetSliderValue {
      self.progressSlider.setProgress(progressObject.sliderValue)
    }

    let leftChevron = UIImage(
      systemName: progressObject.prevChapterImageName,
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 18,
                                                     weight: .semibold)
    )
    let rightChevron = UIImage(
      systemName: progressObject.nextChapterImageName,
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 18,
                                                     weight: .semibold)
    )

    self.previousChapterButton.setImage(leftChevron, for: .normal)
    self.nextChapterButton.setImage(rightChevron, for: .normal)
  }
}

// MARK: - Observers
extension PlayerViewController {
  func bindProgressObservers() {
    self.progressSlider.publisher(for: .touchDown)
      .sink { [weak self] _ in
        // Disable recurring playback time events
        self?.playingProgressSubscriber?.cancel()

        self?.viewModel.handleSliderDownEvent()
      }.store(in: &disposeBag)

    self.progressSlider.publisher(for: .touchUpInside)
      .sink { [weak self] sender in
        guard let slider = sender as? UISlider else { return }

        self?.viewModel.handleSliderUpEvent(with: slider.value)
        // Enable back recurring playback time events after one second
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
          self?.bindBookPlayingProgressEvents()
        }
      }.store(in: &disposeBag)

    self.progressSlider.publisher(for: .valueChanged)
      .sink { [weak self] sender in
        guard let self = self,
              let slider = sender as? UISlider else { return }
        self.progressSlider.setNeedsDisplay()

        let progressObject = self.viewModel.processSliderValueChangedEvent(with: slider.value)

        self.updateView(with: progressObject, shouldSetSliderValue: false)
      }.store(in: &disposeBag)
  }

  func bindBookPlayingProgressEvents() {
    self.playingProgressSubscriber?.cancel()
    self.playingProgressSubscriber = NotificationCenter.default.publisher(for: .bookPlaying)
      .sink { [weak self] _ in
        guard let self = self else { return }
        self.updateView(with: self.viewModel.getCurrentProgressState())
      }
  }

  func bindPlaybackControlsObservers() {
    self.viewModel.isPlayingObserver()
      .receive(on: DispatchQueue.main)
      .sink { isPlaying in
        self.playIconView.isPlaying = isPlaying
      }
      .store(in: &disposeBag)

    self.maxTimeButton.publisher(for: .touchUpInside)
      .sink { [weak self] _ in
        guard let self = self,
              !self.progressSlider.isTracking else { return }

        let progressObject = self.viewModel.processToggleMaxTime()

        self.updateView(with: progressObject)
      }.store(in: &disposeBag)

    self.progressButton.publisher(for: .touchUpInside)
      .merge(with: self.chapterTitleButton.publisher(for: .touchUpInside))
      .sink { [weak self] _ in
        guard let self = self,
              !self.progressSlider.isTracking else { return }

        let progressObject = self.viewModel.processToggleProgressState()

        self.updateView(with: progressObject)
      }.store(in: &disposeBag)

    self.playIconView.observeActionEvents()
      .sink { [weak self] _ in
        self?.viewModel.handlePlayPauseAction()
      }
      .store(in: &disposeBag)

    self.rewindIconView.observeActionEvents()
      .sink { [weak self] _ in
        self?.viewModel.handleRewindAction()
      }
      .store(in: &disposeBag)

    self.forwardIconView.observeActionEvents()
      .sink { [weak self] _ in
        self?.viewModel.handleForwardAction()
      }
      .store(in: &disposeBag)

    self.previousChapterButton.publisher(for: .touchUpInside)
      .sink { [weak self] _ in
        self?.viewModel.handlePreviousChapterAction()
      }
      .store(in: &disposeBag)

    self.nextChapterButton.publisher(for: .touchUpInside)
      .sink { [weak self] _ in
        self?.viewModel.handleNextChapterAction()
      }
      .store(in: &disposeBag)
  }

  func bindTimerObserver() {
    SleepTimer.shared.timeLeftFormatted.sink { timeFormatted in
      guard let timeFormatted = timeFormatted else { return }

      self.playerControlsButton.setCustomTitle(title: timeFormatted)
      let remainingTitle = String(
        describing: String.localizedStringWithFormat("sleep_remaining_title".localized, timeFormatted)
      )
      self.playerControlsBarItem.accessibilityLabel = String(describing: remainingTitle)

    }.store(in: &disposeBag)
  }

  func bindGeneralObservers() {
    NotificationCenter.default.publisher(for: .requestReview)
      .debounce(for: 1.0, scheduler: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.viewModel.requestReview()
      }
      .store(in: &disposeBag)

    NotificationCenter.default.publisher(for: .bookEnd)
      .debounce(for: 1.0, scheduler: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.viewModel.requestReview()
      }
      .store(in: &disposeBag)

    self.closeButton.publisher(for: .touchUpInside)
      .sink { [weak self] _ in
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        self?.viewModel.dismiss()
      }
      .store(in: &disposeBag)

    self.viewModel.currentBookObserver().sink { [weak self] book in
      guard let self = self,
            let book = book else { return }

      self.setupPlayerView(with: book)
    }.store(in: &disposeBag)

    self.viewModel.hasChapters().sink { hasChapters in
      self.chaptersButton.isEnabled = hasChapters
    }.store(in: &disposeBag)

    SpeedManager.shared.currentSpeed.sink { [weak self] speed in
      guard let self = self else { return }

      self.playerControlsButton.setCustomTitle(title: self.formatSpeed(speed))
      self.playerControlsButton.accessibilityLabel = String(describing: self.formatSpeed(speed) + " \("speed_title".localized)")
    }.store(in: &disposeBag)
  }
}

// MARK: - Toolbar
extension PlayerViewController {
  func setupToolbar() {
    self.bottomToolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
    self.bottomToolbar.setShadowImage(UIImage(), forToolbarPosition: .any)

    self.playerControlsButton.addTarget(self, action: #selector(setSpeed), for: .touchUpInside)
    self.playerControlsBarItem = UIBarButtonItem(customView: self.playerControlsButton)
    self.previousChapterButton.accessibilityLabel = "chapters_previous_title".localized
    self.nextChapterButton.accessibilityLabel = "chapters_next_title".localized
    self.bookmarkButton.accessibilityLabel = "bookmark_create_title".localized

    let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

    self.bottomToolbar.setItems(
      [
        self.playerControlsBarItem,
        spacer,
        self.bookmarkButton,
        spacer,
        self.chaptersButton,
        spacer,
        self.moreButton
      ],
      animated: false
    )
  }
}

// MARK: - Toolbar Actions

extension PlayerViewController {
  @IBAction func showChapters(_ sender: UIBarButtonItem) {
    self.viewModel.showChapters()
  }

  @IBAction func createBookmark(_ sender: UIBarButtonItem) {
    let actionSheet = SleepTimer.shared.actionSheet()
    self.present(actionSheet, animated: true, completion: nil)
//    self.viewModel.createBookmark(vc: self)
  }

  @objc func setSpeed() {
    self.viewModel.showControls()
  }

  @IBAction func setSleepTimer() {
    let actionSheet = SleepTimer.shared.actionSheet()
    self.present(actionSheet, animated: true, completion: nil)
  }

  @IBAction func showMore() {
    guard self.viewModel.hasLoadedBook() else {
      return
    }

    let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

    actionSheet.addAction(UIAlertAction(title: "bookmarks_title".localized, style: .default, handler: { [weak self] _ in
      self?.viewModel.showBookmarks()
    }))

    actionSheet.addAction(UIAlertAction(title: "jump_start_title".localized, style: .default, handler: { [weak self] _ in
      self?.viewModel.handleJumpToStart()
    }))

    let markTitle = self.viewModel.isBookFinished() ? "mark_unfinished_title".localized : "mark_finished_title".localized

    actionSheet.addAction(UIAlertAction(title: markTitle, style: .default, handler: { [weak self] _ in
      self?.viewModel.handleMarkCompletion()
    }))

    actionSheet.addAction(UIAlertAction(title: "cancel_button".localized, style: .cancel, handler: nil))

    self.present(actionSheet, animated: true, completion: nil)
  }
}

extension PlayerViewController: UIGestureRecognizerDelegate {
  func setupGestures() {
    self.panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(self.panAction))
    self.panGestureRecognizer.delegate = self
    self.panGestureRecognizer.maximumNumberOfTouches = 1
    self.panGestureRecognizer.cancelsTouchesInView = true

    self.view.addGestureRecognizer(self.panGestureRecognizer)
  }

  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    if gestureRecognizer == self.panGestureRecognizer {
      return limitPanAngle(self.panGestureRecognizer, degreesOfFreedom: 45.0, comparator: .greaterThan)
    }

    return true
  }

  private func updatePresentedViewForTranslation(_ yTranslation: CGFloat) {
    let translation: CGFloat = rubberBandDistance(yTranslation, dimension: self.view.frame.height, constant: 0.55)

    self.view?.transform = CGAffineTransform(translationX: 0, y: max(translation, 0.0))
  }

  @objc private func panAction(gestureRecognizer: UIPanGestureRecognizer) {
    guard gestureRecognizer.isEqual(self.panGestureRecognizer) else {
      return
    }

    switch gestureRecognizer.state {
    case .began:
      gestureRecognizer.setTranslation(CGPoint(x: 0, y: 0), in: self.view.superview)

    case .changed:
      let translation = gestureRecognizer.translation(in: self.view)

      self.updatePresentedViewForTranslation(translation.y)

      if translation.y > self.dismissThreshold, !self.dismissFeedbackTriggered {
        self.dismissFeedbackTriggered = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      }

    case .ended, .cancelled, .failed:
      let translation = gestureRecognizer.translation(in: self.view)

      if translation.y > self.dismissThreshold {
        self.viewModel.dismiss()
        return
      }

      self.dismissFeedbackTriggered = false

      UIView.animate(withDuration: 0.3,
                     delay: 0.0,
                     usingSpringWithDamping: 0.75,
                     initialSpringVelocity: 1.5,
                     options: .preferredFramesPerSecond60,
                     animations: {
                      self.view?.transform = .identity
                     })

    default: break
    }
  }
}

extension PlayerViewController: Themeable {
  func applyTheme(_ theme: SimpleTheme) {
    self.themedStatusBarStyle = theme.useDarkVariant
      ? .lightContent
      : .default
    setNeedsStatusBarAppearanceUpdate()

    self.view.backgroundColor = theme.systemBackgroundColor
    self.bottomToolbar.tintColor = theme.secondaryColor
    self.closeButton.tintColor = theme.linkColor

    self.progressSlider.tintColor = theme.linkColor
    self.progressSlider.minimumTrackTintColor = theme.linkColor
    self.progressSlider.maximumTrackTintColor = theme.linkColor.withAlpha(newAlpha: 0.3)

    self.currentTimeLabel.textColor = theme.secondaryColor
    self.maxTimeButton.setTitleColor(theme.secondaryColor, for: .normal)
    self.progressButton.setTitleColor(theme.secondaryColor, for: .normal)
    self.chapterTitleButton.setTitleColor(theme.primaryColor, for: .normal)
    self.previousChapterButton.tintColor = theme.primaryColor
    self.nextChapterButton.tintColor = theme.primaryColor
  }
}
