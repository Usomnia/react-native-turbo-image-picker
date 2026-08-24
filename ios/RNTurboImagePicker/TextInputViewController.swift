//
//  TextInputViewController.swift
//  RNTurboImagePicker
//

import UIKit

class TextInputViewController: UIViewController {
    public var languageCode: String = "en"
    
    var initialText: String = ""
    var initialColor: UIColor = .white
    
    var onConfirm: ((String, UIColor) -> Void)?
    var onCancel: (() -> Void)?
    
    // MARK: - UI Elements
    
    private lazy var backgroundDimView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private lazy var topBar: UIView = {
        let v = UIView()
        v.backgroundColor = .clear
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private lazy var cancelBtn: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(Localizer.getString(key: "cancel", languageCode: languageCode), for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        return btn
    }()
    
    private lazy var confirmBtn: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(Localizer.getString(key: "confirm", languageCode: languageCode), for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        return btn
    }()
    
    private lazy var textView: UITextView = {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.font = UIFont(name: "Pretendard-SemiBold", size: 28) ?? .systemFont(ofSize: 28, weight: .semibold)
        tv.textColor = initialColor
        tv.tintColor = .white
        tv.textAlignment = .center
        tv.isScrollEnabled = true
        tv.text = initialText
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.delegate = self
        return tv
    }()
    
    private lazy var placeholderLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = Localizer.getString(key: "enter_text", languageCode: languageCode)
        lbl.textColor = UIColor.white.withAlphaComponent(0.5)
        lbl.font = UIFont(name: "Pretendard-SemiBold", size: 28) ?? .systemFont(ofSize: 28, weight: .semibold)
        lbl.textAlignment = .center
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.isHidden = !initialText.isEmpty
        return lbl
    }()
    
    private lazy var colorPickerContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.1, alpha: 0.95)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private lazy var colorScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    
    private lazy var colorStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 16
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    
    // MARK: - Color Palette
    
    private let colors: [UIColor] = [
        .white, .lightGray, .gray, .darkGray, .black,
        .systemRed, .systemOrange, .systemYellow,
        .systemGreen, .systemTeal, .systemBlue, .systemPurple, .systemPink
    ]
    
    private var currentColor: UIColor = .white
    private var colorButtons: [UIButton] = []
    /// Index of the previously selected color button for O(1) deselection
    private var selectedColorIndex: Int = 0
    private var keyboardHeightConstraint: NSLayoutConstraint?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        currentColor = initialColor
        selectedColorIndex = colors.firstIndex(where: { $0 == initialColor }) ?? 0
        
        view.backgroundColor = .clear
        
        view.addSubview(backgroundDimView)
        view.addSubview(topBar)
        topBar.addSubview(cancelBtn)
        topBar.addSubview(confirmBtn)
        
        view.addSubview(textView)
        view.addSubview(placeholderLabel)
        
        view.addSubview(colorPickerContainer)
        colorPickerContainer.addSubview(colorScrollView)
        colorScrollView.addSubview(colorStack)
        
        setupConstraints()
        setupColorPicker()
        
        // Keyboard observers
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        backgroundDimView.addGestureRecognizer(tap)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        textView.becomeFirstResponder()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Constraints
    
    private func setupConstraints() {
        let safeArea = view.safeAreaLayoutGuide
        
        keyboardHeightConstraint = colorPickerContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        
        NSLayoutConstraint.activate([
            backgroundDimView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundDimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundDimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundDimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.bottomAnchor.constraint(equalTo: safeArea.topAnchor, constant: 44),
            
            cancelBtn.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            cancelBtn.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -8),
            
            confirmBtn.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
            confirmBtn.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -8),
            
            colorPickerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            colorPickerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            colorPickerContainer.heightAnchor.constraint(equalToConstant: 50),
            keyboardHeightConstraint!,
            
            colorScrollView.topAnchor.constraint(equalTo: colorPickerContainer.topAnchor),
            colorScrollView.leadingAnchor.constraint(equalTo: colorPickerContainer.leadingAnchor),
            colorScrollView.trailingAnchor.constraint(equalTo: colorPickerContainer.trailingAnchor),
            colorScrollView.bottomAnchor.constraint(equalTo: colorPickerContainer.bottomAnchor),
            
            colorStack.topAnchor.constraint(equalTo: colorScrollView.topAnchor),
            colorStack.leadingAnchor.constraint(equalTo: colorScrollView.leadingAnchor, constant: 16),
            colorStack.trailingAnchor.constraint(equalTo: colorScrollView.trailingAnchor, constant: -16),
            colorStack.bottomAnchor.constraint(equalTo: colorScrollView.bottomAnchor),
            colorStack.heightAnchor.constraint(equalTo: colorScrollView.heightAnchor),
            
            textView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: colorPickerContainer.topAnchor, constant: -16),
            
            placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor)
        ])
    }
    
    // MARK: - Color Picker
    
    private func setupColorPicker() {
        var sizeConstraints: [NSLayoutConstraint] = []
        sizeConstraints.reserveCapacity(colors.count * 2)
        
        for (index, color) in colors.enumerated() {
            let btn = UIButton(type: .custom)
            btn.backgroundColor = color
            btn.layer.cornerRadius = 15
            btn.layer.borderWidth = 2
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.tag = index
            btn.addTarget(self, action: #selector(colorTapped(_:)), for: .touchUpInside)
            
            // Apply initial border
            applyColorButtonBorder(btn, color: color, isSelected: index == selectedColorIndex)
            
            sizeConstraints.append(btn.widthAnchor.constraint(equalToConstant: 30))
            sizeConstraints.append(btn.heightAnchor.constraint(equalToConstant: 30))
            
            colorStack.addArrangedSubview(btn)
            colorButtons.append(btn)
        }
        
        // Batch activate all size constraints at once
        NSLayoutConstraint.activate(sizeConstraints)
    }
    
    /// Applies border styling to a color button based on selection state.
    private func applyColorButtonBorder(_ btn: UIButton, color: UIColor, isSelected: Bool) {
        if isSelected {
            btn.layer.borderColor = UIColor.white.cgColor
        } else if color == .black || color == .darkGray {
            btn.layer.borderColor = UIColor(white: 1.0, alpha: 0.3).cgColor
        } else {
            btn.layer.borderColor = UIColor.clear.cgColor
        }
    }
    
    // MARK: - Actions
    
    @objc private func colorTapped(_ sender: UIButton) {
        let newIndex = sender.tag
        guard newIndex != selectedColorIndex else { return }
        
        // Deselect previous (O(1))
        let prevBtn = colorButtons[selectedColorIndex]
        applyColorButtonBorder(prevBtn, color: colors[selectedColorIndex], isSelected: false)
        
        // Select new (O(1))
        selectedColorIndex = newIndex
        currentColor = colors[newIndex]
        textView.textColor = currentColor
        applyColorButtonBorder(sender, color: currentColor, isSelected: true)
    }
    
    @objc private func cancelTapped() {
        onCancel?()
        dismiss(animated: true)
    }
    
    @objc private func confirmTapped() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            onConfirm?(text, currentColor)
        } else {
            onCancel?()
        }
        dismiss(animated: true)
    }
    
    @objc private func backgroundTapped() {
        confirmTapped()
    }
    
    // MARK: - Keyboard Handling
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        
        keyboardHeightConstraint?.constant = -keyboardFrame.height
        
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        
        keyboardHeightConstraint?.constant = 0
        
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }
}

extension TextInputViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }
}
