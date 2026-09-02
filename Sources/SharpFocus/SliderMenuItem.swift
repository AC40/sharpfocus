import AppKit

/// A menu item hosting a labelled slider, for live-adjustable settings.
final class SliderMenuItem: NSMenuItem {
    private let slider: NSSlider
    private let valueLabel: NSTextField
    private let format: (Double) -> String
    private let onValueChange: (Double) -> Void

    init(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        format: @escaping (Double) -> String = { "\(Int($0 * 100))%" },
        onChange: @escaping (Double) -> Void
    ) {
        self.format = format
        self.onValueChange = onChange

        slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                          target: nil, action: nil)
        valueLabel = NSTextField(labelWithString: format(value))
        super.init(title: title, action: nil, keyEquivalent: "")

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .menuFont(ofSize: NSFont.smallSystemFontSize)
        titleLabel.textColor = .secondaryLabelColor

        valueLabel.font = .monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right

        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.isContinuous = true

        let header = NSStackView(views: [titleLabel, NSView(), valueLabel])
        header.orientation = .horizontal
        header.distribution = .fill

        let stack = NSStackView(views: [header, slider])
        stack.orientation = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 14, bottom: 4, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // NSMenuItem.view is sized by its frame, not by Auto Layout — a
        // constraint-only container collapses to zero height and the item
        // becomes invisible in the menu.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 230, height: 50))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            slider.widthAnchor.constraint(equalToConstant: 202),
            header.widthAnchor.constraint(equalToConstant: 202),
        ])
        let fittingHeight = container.fittingSize.height
        if fittingHeight > 0 {
            container.frame.size.height = fittingHeight
        }
        view = container
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func sliderMoved(_ sender: NSSlider) {
        valueLabel.stringValue = format(sender.doubleValue)
        onValueChange(sender.doubleValue)
    }

    /// Syncs the control when the setting was changed elsewhere (sfctl, defaults).
    func update(value: Double) {
        guard abs(slider.doubleValue - value) > 0.0001 else { return }
        slider.doubleValue = value
        valueLabel.stringValue = format(value)
    }
}
