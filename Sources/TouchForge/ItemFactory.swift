import AppKit

/// ItemConfig → 실제 NSTouchBarItem
enum ItemFactory {
    struct Built {
        let item: NSTouchBarItem
        let widget: Widget?
    }

    static let barHeight: CGFloat = 30

    static func make(_ config: ItemConfig, identifier: NSTouchBarItem.Identifier) -> Built {
        let type = config.type.lowercased()
        switch type {
        case "button":
            return wrap(makeButton(config, bordered: true), identifier, config)

        case "label":
            return wrap(makeButton(config, bordered: false), identifier, config)

        case "escape", "esc":
            var c = config
            if c.title == nil && c.symbol == nil { c.title = "esc" }
            if c.action == nil { c.action = ActionConfig(type: "key", key: "esc") }
            return wrap(makeButton(c, bordered: true), identifier, c)

        case "close", "minimize":
            var c = config
            if c.title == nil && c.symbol == nil { c.symbol = "chevron.left.2" }
            c.action = ActionConfig(type: "minimize")
            let built = wrap(makeButton(c, bordered: true), identifier, c)
            // 자리가 모자라도 닫기 버튼은 끝까지 남긴다
            built.item.visibilityPriority = .high
            return built

        case "clock":
            let button = makeButton(config, bordered: false, monospaced: true, useTitle: false)
            return wrap(button, identifier, config, widget: ClockWidget(button: button, format: config.format, prefix: config.title))

        case "battery":
            let button = makeButton(config, bordered: false, monospaced: true, useTitle: false)
            return wrap(button, identifier, config, widget: BatteryWidget(button: button, interval: config.interval ?? 30, prefix: config.title))

        case "cpu":
            let button = makeButton(config, bordered: false, monospaced: true, useTitle: false)
            return wrap(button, identifier, config, widget: CPUWidget(button: button, interval: config.interval ?? 2, prefix: config.title ?? "CPU"))

        case "memory", "ram":
            let button = makeButton(config, bordered: false, monospaced: true, useTitle: false)
            return wrap(button, identifier, config, widget: MemoryWidget(button: button, interval: config.interval ?? 5, prefix: config.title ?? "RAM"))

        case "weather":
            let button = makeButton(config, bordered: false, monospaced: false, useTitle: false)
            let widget = WeatherWidget(
                button: button,
                latitude: config.latitude ?? 37.5665,
                longitude: config.longitude ?? 126.9780,
                interval: config.interval ?? 900,
                prefix: config.title
            )
            return wrap(button, identifier, config, widget: widget)

        case "stock":
            let button = makeButton(config, bordered: false, monospaced: true, useTitle: false)
            let widget = StockWidget(
                button: button,
                ticker: config.ticker ?? "005930.KS",
                name: config.name,
                interval: config.interval ?? 60,
                prefix: config.title
            )
            return wrap(button, identifier, config, widget: widget)

        case "limitlens", "usage":
            // LimitLens 앱이 저장한 구독 한도 % 표시. 누르면 LimitLens 를 연다
            var c = config
            if c.action == nil { c.action = ActionConfig(type: "launch", app: "com.m32k.limitlens") }
            let button = makeButton(c, bordered: false, monospaced: true, useTitle: false)
            let widget = LimitLensUsageWidget(
                button: button,
                providers: config.providers,
                interval: config.interval ?? 30,
                prefix: config.title
            )
            return wrap(button, identifier, c, widget: widget)

        case "shell":
            let button = makeButton(config, bordered: false, monospaced: false, useTitle: false)
            let widget = ShellWidget(button: button, command: config.command ?? "echo 'command 없음'", interval: config.interval ?? 10, prefix: config.title)
            return wrap(button, identifier, config, widget: widget)

        case "image", "gif":
            return makeImage(config, identifier: identifier)

        case "marquee":
            return makeMarquee(config, identifier: identifier)

        case "space":
            let view = NSView(frame: .zero)
            return wrap(view, identifier, config, defaultWidth: 16)

        default:
            return wrap(makeButton(.label("알 수 없는 type: \(config.type)", color: "#FF453A"), bordered: false), identifier, config)
        }
    }

    // MARK: - 버튼

    static func makeButton(_ config: ItemConfig, bordered defaultBordered: Bool, monospaced: Bool = false, useTitle: Bool = true) -> ActionButton {
        let button = ActionButton(title: "", target: nil, action: nil)
        button.configureTarget()

        let size = CGFloat(config.fontSize ?? 15)
        button.textFont = monospaced ? .monospacedDigitSystemFont(ofSize: size, weight: .regular) : .systemFont(ofSize: size)
        button.textColor = NSColor.fromHex(config.color)

        let title = useTitle ? (config.title ?? "") : ""
        if let image = loadImage(config, maxHeight: 22) {
            button.image = image
            button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
            if let color = button.textColor { button.contentTintColor = color }
        }

        let background = NSColor.fromHex(config.bg)
        button.isBordered = config.bordered ?? (background != nil ? true : defaultBordered)
        if let background { button.bezelColor = background }

        button.setText(title)

        if let action = config.action {
            button.onTap = { ActionRunner.run(action) }
        }
        if let longAction = config.longAction {
            button.onLongPress = { ActionRunner.run(longAction) }
            button.installLongPress()
        }
        return button
    }

    /// symbol(SF Symbol) 또는 image(파일) 로 아이콘을 만든다
    static func loadImage(_ config: ItemConfig, maxHeight: CGFloat) -> NSImage? {
        if let symbol = config.symbol {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)
            if image == nil { Log.error("SF Symbol 을 찾지 못함: \(symbol)") }
            return image
        }
        if let path = config.image {
            guard let image = NSImage(contentsOf: ConfigPaths.resolve(path)) else {
                Log.error("이미지를 열지 못함: \(path)")
                return nil
            }
            if image.size.height > maxHeight, image.size.height > 0 {
                image.size = NSSize(width: image.size.width * maxHeight / image.size.height, height: maxHeight)
            }
            return image
        }
        return nil
    }

    // MARK: - 이미지 / GIF

    static func makeImage(_ config: ItemConfig, identifier: NSTouchBarItem.Identifier) -> Built {
        guard let path = config.image, let image = NSImage(contentsOf: ConfigPaths.resolve(path)) else {
            let button = makeButton(.label("이미지 없음: \(config.image ?? "-")", color: "#FF453A"), bordered: false)
            return wrap(button, identifier, config)
        }
        let view = TapImageView(frame: .zero)
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.wantsLayer = true
        if let background = NSColor.fromHex(config.bg) {
            view.layer?.backgroundColor = background.cgColor
            view.layer?.cornerRadius = 6
        }
        if let action = config.action {
            view.onTap = { ActionRunner.run(action) }
        }
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        return wrap(view, identifier, config, defaultWidth: barHeight * aspect)
    }

    // MARK: - 전광판

    static func makeMarquee(_ config: ItemConfig, identifier: NSTouchBarItem.Identifier) -> Built {
        let view = MarqueeView(frame: .zero)
        let size = CGFloat(config.fontSize ?? 15)
        view.attributes = [
            .font: NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: NSColor.fromHex(config.color) ?? .white,
        ]
        view.text = config.text ?? config.title ?? ""
        view.speed = CGFloat(config.speed ?? 40)
        view.backgroundColor = NSColor.fromHex(config.bg)
        if let action = config.action {
            view.onTap = { ActionRunner.run(action) }
        }
        return wrap(view, identifier, config, widget: view, defaultWidth: 200)
    }

    // MARK: - 공통

    private static func wrap(
        _ view: NSView,
        _ identifier: NSTouchBarItem.Identifier,
        _ config: ItemConfig,
        widget: Widget? = nil,
        defaultWidth: CGFloat? = nil
    ) -> Built {
        let item = NSCustomTouchBarItem(identifier: identifier)
        if let width = config.width.map({ CGFloat($0) }) ?? defaultWidth {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        item.view = view
        return Built(item: item, widget: widget)
    }
}
