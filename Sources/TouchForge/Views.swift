import AppKit

/// 클로저로 탭/길게 누르기를 처리하는 터치바 버튼
final class ActionButton: NSButton {
    var onTap: (() -> Void)?
    var onLongPress: (() -> Void)?
    var textColor: NSColor?
    var textFont: NSFont = .systemFont(ofSize: 15)

    func configureTarget() {
        target = self
        action = #selector(fire)
    }

    @objc private func fire() {
        onTap?()
    }

    func installLongPress() {
        let recognizer = NSPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        recognizer.allowedTouchTypes = .direct
        recognizer.minimumPressDuration = 0.5
        addGestureRecognizer(recognizer)
    }

    @objc private func handlePress(_ recognizer: NSPressGestureRecognizer) {
        if recognizer.state == .began {
            onLongPress?()
        }
    }

    /// 글자 색/폰트를 유지한 채 제목만 바꾼다
    func setText(_ text: String, color overrideColor: NSColor? = nil) {
        var attributes: [NSAttributedString.Key: Any] = [.font: textFont]
        if let color = overrideColor ?? textColor {
            attributes[.foregroundColor] = color
        } else {
            attributes[.foregroundColor] = NSColor.white
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        attributes[.paragraphStyle] = paragraph
        attributedTitle = NSAttributedString(string: text, attributes: attributes)
    }

    /// 조각마다 다른 색으로 제목을 만든다 (예: C42 는 흰색, X73 은 주황)
    func setParts(_ parts: [(text: String, color: NSColor?)]) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let result = NSMutableAttributedString()
        for part in parts {
            result.append(NSAttributedString(string: part.text, attributes: [
                .font: textFont,
                .foregroundColor: part.color ?? textColor ?? NSColor.white,
                .paragraphStyle: paragraph,
            ]))
        }
        attributedTitle = result
    }
}

/// 탭할 수 있는 이미지 뷰 (PNG/JPG/GIF 애니메이션)
final class TapImageView: NSImageView {
    var onTap: (() -> Void)? {
        didSet { installTapIfNeeded() }
    }
    private var tapInstalled = false

    private func installTapIfNeeded() {
        guard onTap != nil, !tapInstalled else { return }
        tapInstalled = true
        let recognizer = NSClickGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.allowedTouchTypes = .direct
        addGestureRecognizer(recognizer)
    }

    @objc private func handleTap(_ recognizer: NSClickGestureRecognizer) {
        onTap?()
    }
}

/// 흐르는 글자 (전광판)
final class MarqueeView: NSView, BarWidget {
    var text: String = "" {
        didSet { textWidth = (text as NSString).size(withAttributes: attributes).width }
    }
    var attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15),
        .foregroundColor: NSColor.white,
    ] {
        didSet { textWidth = (text as NSString).size(withAttributes: attributes).width }
    }
    var speed: CGFloat = 40
    var backgroundColor: NSColor?
    var onTap: (() -> Void)?

    private let gap: CGFloat = 60
    private var offset: CGFloat = 0
    private var textWidth: CGFloat = 0
    private var timer: Timer?
    private let fps: Double = 30

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let recognizer = NSClickGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.allowedTouchTypes = .direct
        addGestureRecognizer(recognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func handleTap(_ recognizer: NSClickGestureRecognizer) {
        onTap?()
    }

    func start() {
        stop()
        offset = 0
        let timer = Timer(timeInterval: 1 / fps, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func tick() {
        // 글자가 칸보다 짧으면 움직이지 않고 가운데 정렬
        guard textWidth > bounds.width else {
            needsDisplay = true
            return
        }
        offset -= speed / CGFloat(fps)
        if offset <= -(textWidth + gap) {
            offset += textWidth + gap
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if let backgroundColor {
            backgroundColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        let y = (bounds.height - size.height) / 2

        if textWidth <= bounds.width {
            string.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: y), withAttributes: attributes)
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        var x = offset
        while x < bounds.width {
            string.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
            x += textWidth + gap
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
