import UIKit

class FilterThumbnailCell: UICollectionViewCell {
    static let id = "FilterThumbnailCell"
    
    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 4
        iv.layer.borderWidth = 2
        iv.layer.borderColor = UIColor.clear.cgColor
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    
    private let nameLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = .systemFont(ofSize: 11, weight: .regular)
        lbl.textColor = UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? .white : .darkGray
        }
        lbl.textAlignment = .center
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()
    
    private let intensityLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = .systemFont(ofSize: 14, weight: .bold)
        lbl.textColor = UIColor.systemYellow
        lbl.textAlignment = .center
        lbl.isHidden = true
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()
    
    private let dimmingView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        v.isHidden = true
        v.layer.cornerRadius = 4
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func setupUI() {
        contentView.addSubview(imageView)
        contentView.addSubview(dimmingView)
        contentView.addSubview(intensityLabel)
        contentView.addSubview(nameLabel)
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
            
            dimmingView.topAnchor.constraint(equalTo: imageView.topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            
            intensityLabel.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            intensityLabel.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            
            nameLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
    }
    
    func configure(with image: UIImage?, name: String, isSelected: Bool, intensity: CGFloat, themeColor: UIColor? = nil) {
        imageView.image = image
        nameLabel.text = name
        
        let color = themeColor ?? UIColor.systemYellow
        
        let unselectedColor = UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? .white : .darkGray
        }
        
        imageView.layer.borderColor = isSelected ? color.cgColor : UIColor.clear.cgColor
        nameLabel.textColor = isSelected ? color : unselectedColor
        nameLabel.font = isSelected ? .systemFont(ofSize: 11, weight: .bold) : .systemFont(ofSize: 11, weight: .regular)
        
        intensityLabel.textColor = color
        
        if isSelected && intensity > 0 && name != "원본" {
            dimmingView.isHidden = false
            intensityLabel.isHidden = false
            intensityLabel.text = "\(Int(intensity * 100))"
        } else {
            dimmingView.isHidden = true
            intensityLabel.isHidden = true
        }
    }
    
    func updateIntensity(_ intensity: CGFloat) {
        intensityLabel.text = "\(Int(intensity * 100))"
    }
    
    func updateImage(_ image: UIImage?) {
        imageView.image = image
    }
}
