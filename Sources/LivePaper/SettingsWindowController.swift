import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let settings: SettingsStore
    private let thumbnailView = NSImageView()
    private let videoLabel = NSTextField(labelWithString: "No video selected")
    private let frameSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let liveDesktopCheckbox = NSButton(checkboxWithTitle: "Live Home Screen", target: nil, action: nil)
    private let batterySlider = NSSlider(value: 50, minValue: 1, maxValue: 100, target: nil, action: nil)
    private let batteryValueLabel = NSTextField(labelWithString: "50%")
    private let statusLabel = NSTextField(labelWithString: "")
    private var loadedDurationVideoURL: URL?
    private var loadedDuration: Double = 1

    init(settings: SettingsStore) {
        self.settings = settings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LivePaper"
        window.minSize = NSSize(width: 640, height: 440)
        window.center()
        super.init(window: window)
        buildUI()
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        contentView.addSubview(scrollView)

        let chooseButton = NSButton(title: "Choose Video...", target: self, action: #selector(chooseVideo))
        let installLockButton = NSButton(title: "Install Live Lock Screen", target: self, action: #selector(installLiveLockScreen))
        let repairButton = NSButton(title: "Repair Now", target: self, action: #selector(repairLiveLockScreen))
        let applyStaticButton = NSButton(title: "Apply Static Desktop", target: self, action: #selector(applyStaticDesktop))

        frameSlider.target = self
        frameSlider.action = #selector(frameChanged)
        liveDesktopCheckbox.target = self
        liveDesktopCheckbox.action = #selector(liveDesktopChanged)
        batterySlider.target = self
        batterySlider.action = #selector(batteryThresholdChanged)

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.backgroundColor = NSColor.black.cgColor
        thumbnailView.layer?.cornerRadius = 6

        videoLabel.lineBreakMode = .byTruncatingMiddle
        videoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 3

        let videoRow = NSStackView(views: [videoLabel, chooseButton])
        videoRow.orientation = .horizontal
        videoRow.spacing = 12
        videoRow.alignment = .centerY

        let buttonRow = NSStackView(views: [installLockButton, repairButton, applyStaticButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12

        batteryValueLabel.alignment = .right
        let batteryRow = NSStackView(views: [label("Pause Below"), batterySlider, batteryValueLabel])
        batteryRow.orientation = .horizontal
        batteryRow.spacing = 12
        batteryRow.alignment = .centerY

        let root = NSStackView(views: [
            label("Video"),
            videoRow,
            thumbnailView,
            label("Static Frame"),
            frameSlider,
            label("Home Screen"),
            liveDesktopCheckbox,
            batteryRow,
            buttonRow,
            statusLabel
        ])
        root.orientation = .vertical
        root.spacing = 14
        root.alignment = .leading
        root.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(root)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),

            root.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 24),
            root.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -24),
            chooseButton.widthAnchor.constraint(equalToConstant: 140),
            thumbnailView.widthAnchor.constraint(equalTo: root.widthAnchor),
            thumbnailView.heightAnchor.constraint(equalToConstant: 220),
            frameSlider.widthAnchor.constraint(equalTo: root.widthAnchor),
            batterySlider.widthAnchor.constraint(equalToConstant: 240),
            batteryValueLabel.widthAnchor.constraint(equalToConstant: 48),
            statusLabel.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    @objc private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.selectedVideoPath = url.path
        settings.statusMessage = "Video selected."
        refresh()
    }

    @objc private func installLiveLockScreen() {
        do {
            try AerialWallpaperInstaller().installSelectedVideo(settings: settings)
            try LaunchAgentInstaller().install(settings: settings)
            settings.statusMessage = "Installed live lock-screen wallpaper and auto repair."
        } catch {
            settings.statusMessage = error.localizedDescription
        }
        refresh()
    }

    @objc private func repairLiveLockScreen() {
        do {
            let repaired = try AerialWallpaperInstaller().repairSelectedVideo(settings: settings)
            settings.statusMessage = repaired ? "Repaired live lock-screen wallpaper." : "Live lock-screen wallpaper is already installed."
        } catch {
            settings.statusMessage = error.localizedDescription
        }
        refresh()
    }

    @objc private func applyStaticDesktop() {
        do {
            try WallpaperController().generateAndApplyStaticFrame(settings: settings)
            settings.statusMessage = "Applied static desktop wallpaper."
        } catch {
            settings.statusMessage = error.localizedDescription
        }
        refresh()
    }

    @objc private func frameChanged() {
        settings.selectedFrameTime = frameSlider.doubleValue
        updateThumbnail()
    }

    @objc private func liveDesktopChanged() {
        settings.liveDesktopAllowed = liveDesktopCheckbox.state == .on
        settings.statusMessage = settings.liveDesktopAllowed ? "Live home screen enabled." : "Live home screen disabled."
        refresh()
    }

    @objc private func batteryThresholdChanged() {
        settings.batteryThreshold = max(1, min(100, Int(batterySlider.doubleValue.rounded())))
        refresh()
    }

    private func refresh() {
        videoLabel.stringValue = settings.selectedVideoURL?.path ?? "No video selected"
        statusLabel.stringValue = settings.statusMessage
        liveDesktopCheckbox.state = settings.liveDesktopAllowed ? .on : .off
        batterySlider.integerValue = settings.batteryThreshold
        batterySlider.isEnabled = settings.liveDesktopAllowed
        batteryValueLabel.stringValue = "\(settings.batteryThreshold)%"
        batteryValueLabel.textColor = settings.liveDesktopAllowed ? .labelColor : .secondaryLabelColor

        if let videoURL = settings.selectedVideoURL {
            loadDurationIfNeeded(videoURL)
            frameSlider.maxValue = max(loadedDuration, 1)
            frameSlider.doubleValue = min(settings.selectedFrameTime, frameSlider.maxValue)
        }

        updateThumbnail()
    }

    private func loadDurationIfNeeded(_ videoURL: URL) {
        guard loadedDurationVideoURL != videoURL else { return }
        loadedDurationVideoURL = videoURL
        Task { [weak self] in
            let duration = await FrameExtractor.duration(of: videoURL)
            await MainActor.run {
                self?.loadedDuration = max(duration, 1)
                self?.frameSlider.maxValue = max(duration, 1)
            }
        }
    }

    private func updateThumbnail() {
        guard let videoURL = settings.selectedVideoURL else {
            thumbnailView.image = nil
            return
        }
        let frameTime = settings.selectedFrameTime
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = try? FrameExtractor.image(from: videoURL, atSeconds: frameTime, maximumSize: CGSize(width: 900, height: 580))
            DispatchQueue.main.async {
                self?.thumbnailView.image = image
            }
        }
    }
}
