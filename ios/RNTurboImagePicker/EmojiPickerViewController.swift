//
//  EmojiPickerViewController.swift
//  RNTurboImagePicker
//

import UIKit

class PassThroughView: UIView {
    weak var dimView: UIView?
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        if hitView == self { return nil }
        if hitView == dimView {
            return (dimView?.alpha ?? 0) > 0 ? hitView : nil
        }
        return hitView
    }
}

class EmojiPickerViewController: UIViewController {

    var onEmojiSelected: ((String) -> Void)?
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?
    var themeColor: UIColor = .systemYellow

    private var selectedCategoryIndex = 0
    private var currentEmojis: [String] { EmojiData.categories[selectedCategoryIndex].emojis }
    private var isGridVisible = true

    private let gridAreaHeight: CGFloat = 340
    private let bottomBarContentHeight: CGFloat = 60

    private lazy var dimView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var panelView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor { t in t.userInterfaceStyle == .dark ? UIColor(white:0.1,alpha:1) : UIColor(white:0.97,alpha:1) }
        v.layer.cornerRadius = 20
        v.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        v.layer.masksToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var emojiCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.dataSource = self
        cv.delegate = self
        cv.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.id)
        cv.showsVerticalScrollIndicator = false
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    // Bottom bar (extends to screen bottom, covering safe area)
    private lazy var bottomBarView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor { t in t.userInterfaceStyle == .dark ? UIColor(white:0.12,alpha:1) : UIColor(white:0.94,alpha:1) }
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var cancelButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor { t in t.userInterfaceStyle == .dark ? .white : .black }
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var confirmButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        btn.setImage(UIImage(systemName: "checkmark", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor { t in t.userInterfaceStyle == .dark ? .white : .black }
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var tabScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var tabStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 0
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var tabIndicatorView: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 1.5
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private var tabButtons: [UIButton] = []
    private var tabIndicatorLeadingConstraint: NSLayoutConstraint?
    private var tabIndicatorWidthConstraint: NSLayoutConstraint?
    private var panelBottomConstraint: NSLayoutConstraint?
    private var bottomBarHeightConstraint: NSLayoutConstraint?
    private var bottomBarBottomConstraint: NSLayoutConstraint?

    // MARK: - Lifecycle
    
    override func loadView() {
        let passThroughView = PassThroughView()
        passThroughView.backgroundColor = .clear
        self.view = passThroughView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        FontHelper.registerFontIfNeeded()
        setupUI()
        buildCategoryTabs()
        tabIndicatorView.backgroundColor = themeColor
        
        // Initial State (Offscreen)
        panelBottomConstraint?.constant = gridAreaHeight + 40
        bottomBarBottomConstraint?.constant = bottomBarContentHeight + 60
        dimView.alpha = 0
        updateTabSelection(animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Slide up animation
        bottomBarBottomConstraint?.constant = 0
        setGridVisible(true, animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safeBottom = view.safeAreaInsets.bottom
        bottomBarHeightConstraint?.constant = bottomBarContentHeight + safeBottom
    }

    // MARK: - Setup

    private func setupUI() {
        if let passView = self.view as? PassThroughView {
            passView.dimView = dimView
        }
        
        // 1. Dim (tap to close grid, but keep bottom bar)
        view.addSubview(dimView)
        let tap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimView.addGestureRecognizer(tap)
        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // 2. Panel (Grid Area)
        view.addSubview(panelView)
        panelView.addSubview(emojiCollectionView)
        NSLayoutConstraint.activate([
            panelView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panelView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panelView.heightAnchor.constraint(equalToConstant: gridAreaHeight),
            
            emojiCollectionView.topAnchor.constraint(equalTo: panelView.topAnchor, constant: 8),
            emojiCollectionView.leadingAnchor.constraint(equalTo: panelView.leadingAnchor),
            emojiCollectionView.trailingAnchor.constraint(equalTo: panelView.trailingAnchor),
            emojiCollectionView.bottomAnchor.constraint(equalTo: panelView.bottomAnchor, constant: -8),
        ])

        // 3. Bottom Bar
        view.addSubview(bottomBarView)
        bottomBarHeightConstraint = bottomBarView.heightAnchor.constraint(equalToConstant: bottomBarContentHeight + 34)
        bottomBarBottomConstraint = bottomBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0)
        NSLayoutConstraint.activate([
            bottomBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBarHeightConstraint!,
            bottomBarBottomConstraint!
        ])
        
        // Link Panel to Bottom Bar Top
        panelBottomConstraint = panelView.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: 0)
        panelBottomConstraint?.isActive = true

        // Ensure Panel is behind Bottom Bar so it slides underneath
        view.bringSubviewToFront(bottomBarView)

        // Cancel button
        bottomBarView.addSubview(cancelButton)
        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor, constant: 8),
            cancelButton.topAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: 8),
            cancelButton.widthAnchor.constraint(equalToConstant: 44),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        // Confirm button
        bottomBarView.addSubview(confirmButton)
        NSLayoutConstraint.activate([
            confirmButton.trailingAnchor.constraint(equalTo: bottomBarView.trailingAnchor, constant: -8),
            confirmButton.topAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: 8),
            confirmButton.widthAnchor.constraint(equalToConstant: 44),
            confirmButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        // Tab scroll
        bottomBarView.addSubview(tabScrollView)
        tabScrollView.addSubview(tabStackView)
        tabScrollView.addSubview(tabIndicatorView)
        NSLayoutConstraint.activate([
            tabScrollView.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 4),
            tabScrollView.trailingAnchor.constraint(equalTo: confirmButton.leadingAnchor, constant: -4),
            tabScrollView.topAnchor.constraint(equalTo: bottomBarView.topAnchor),
            tabScrollView.heightAnchor.constraint(equalToConstant: bottomBarContentHeight),

            tabStackView.topAnchor.constraint(equalTo: tabScrollView.topAnchor),
            tabStackView.leadingAnchor.constraint(equalTo: tabScrollView.leadingAnchor),
            tabStackView.trailingAnchor.constraint(equalTo: tabScrollView.trailingAnchor),
            tabStackView.bottomAnchor.constraint(equalTo: tabScrollView.bottomAnchor),
            tabStackView.heightAnchor.constraint(equalTo: tabScrollView.heightAnchor),
        ])

        // Indicator
        tabIndicatorLeadingConstraint = tabIndicatorView.leadingAnchor.constraint(equalTo: tabScrollView.leadingAnchor)
        tabIndicatorWidthConstraint   = tabIndicatorView.widthAnchor.constraint(equalToConstant: 40)
        NSLayoutConstraint.activate([
            tabIndicatorView.bottomAnchor.constraint(equalTo: tabScrollView.bottomAnchor, constant: -1),
            tabIndicatorView.heightAnchor.constraint(equalToConstant: 3),
            tabIndicatorLeadingConstraint!,
            tabIndicatorWidthConstraint!,
        ])
    }

    private func buildCategoryTabs() {
        let iconSize: CGFloat = 36
        for (index, category) in EmojiData.categories.enumerated() {
            let btn = UIButton(type: .custom)
            btn.tag = index
            btn.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(equalToConstant: iconSize + 12),
                btn.heightAnchor.constraint(equalToConstant: bottomBarContentHeight),
            ])

            let iconView = GoogleEmojiImageView()
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.emoji = category.icon
            btn.addSubview(iconView)
            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: btn.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: iconSize),
                iconView.heightAnchor.constraint(equalToConstant: iconSize),
            ])

            btn.addTarget(self, action: #selector(categoryTabTapped(_:)), for: .touchUpInside)
            tabStackView.addArrangedSubview(btn)
            tabButtons.append(btn)
        }
    }

    // MARK: - Tab Selection

    @objc private func categoryTabTapped(_ sender: UIButton) {
        if !isGridVisible {
            setGridVisible(true, animated: true)
        }
        
        guard sender.tag != selectedCategoryIndex else { return }
        selectedCategoryIndex = sender.tag
        updateTabSelection(animated: true)
        emojiCollectionView.reloadData()
        emojiCollectionView.setContentOffset(.zero, animated: false)
    }

    private func updateTabSelection(animated: Bool) {
        for (i, btn) in tabButtons.enumerated() {
            btn.alpha = i == selectedCategoryIndex ? 1.0 : 0.4
        }
        if tabButtons.indices.contains(selectedCategoryIndex) {
            let btn = tabButtons[selectedCategoryIndex]
            let indicatorW = btn.bounds.width > 0 ? btn.bounds.width : (36 + 12)
            let indicatorX = btn.frame.minX + (indicatorW - 36) / 2
            tabIndicatorLeadingConstraint?.constant = indicatorX
            tabIndicatorWidthConstraint?.constant   = 36
            
            if animated {
                UIView.animate(withDuration: 0.2) {
                    self.tabScrollView.layoutIfNeeded()
                }
            } else {
                self.tabScrollView.layoutIfNeeded()
            }
            tabScrollView.scrollRectToVisible(btn.frame, animated: animated)
        }
    }
    
    private func setGridVisible(_ visible: Bool, animated: Bool) {
        isGridVisible = visible
        panelBottomConstraint?.constant = visible ? 0 : (gridAreaHeight + 40)
        
        if visible {
            updateTabSelection(animated: false)
        }
        
        let duration = animated ? 0.35 : 0.0
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5) {
            self.view.layoutIfNeeded()
            self.dimView.alpha = visible ? 1.0 : 0.0
            self.tabIndicatorView.alpha = visible ? 1.0 : 0.0
        }
    }

    // MARK: - Actions

    @objc private func dimTapped() {
        if isGridVisible {
            setGridVisible(false, animated: true)
        }
    }

    @objc private func cancelTapped() {
        dismissEntirely { [weak self] in self?.onCancel?() }
    }

    @objc private func doneTapped() {
        dismissEntirely { [weak self] in self?.onDone?() }
    }

    private func dismissEntirely(completion: @escaping () -> Void) {
        panelBottomConstraint?.constant = gridAreaHeight + 40
        bottomBarBottomConstraint?.constant = bottomBarContentHeight + 80
        UIView.animate(withDuration: 0.3, animations: {
            self.view.layoutIfNeeded()
            self.dimView.alpha = 0
        }) { _ in
            completion()
        }
    }
}

// MARK: - UICollectionView

extension EmojiPickerViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        currentEmojis.count
    }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: EmojiCell.id, for: indexPath) as! EmojiCell
        cell.configure(with: currentEmojis[indexPath.item])
        return cell
    }

    func collectionView(_ cv: UICollectionView, layout layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let side = floor((cv.bounds.width - 16) / 4)
        return CGSize(width: side, height: side)
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let emoji = currentEmojis[indexPath.item]
        onEmojiSelected?(emoji)
        
        // Hide grid so user can edit sticker
        setGridVisible(false, animated: true)
        
        if let cell = cv.cellForItem(at: indexPath) {
            UIView.animate(withDuration: 0.1, animations: { cell.transform = CGAffineTransform(scaleX: 0.85, y: 0.85) }) { _ in
                UIView.animate(withDuration: 0.15) { cell.transform = .identity }
            }
        }
    }
}

// MARK: - EmojiCell

private class EmojiCell: UICollectionViewCell {
    static let id = "EmojiCell"
    private let emojiView = GoogleEmojiImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(emojiView)
        emojiView.translatesAutoresizingMaskIntoConstraints = false
        emojiView.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([
            emojiView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emojiView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            emojiView.widthAnchor.constraint(equalToConstant: 64),
            emojiView.heightAnchor.constraint(equalToConstant: 64),
            emojiView.topAnchor.constraint(equalTo: contentView.topAnchor),
            emojiView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with emoji: String) {
        emojiView.emoji = emoji
    }
}
