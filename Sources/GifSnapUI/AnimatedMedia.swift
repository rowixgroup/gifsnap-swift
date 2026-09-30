#if canImport(UIKit)
import SwiftUI
import SDWebImage
import GifSnap

/// Registers the ImageIO animated WebP coder once. GIF decoding is built into SDWebImage.
@MainActor enum GifSnapAnimation {
    static let prepare: Void = { SDImageCodersManager.shared.addCoder(SDImageAWebPCoder.shared) }()
    static let manager: SDWebImageManager = {
        let cacheConfig = SDImageCacheConfig()
        cacheConfig.maxMemoryCost = 32 * 1024 * 1024
        cacheConfig.maxDiskSize = 64 * 1024 * 1024
        let cache = SDImageCache(namespace: "com.rowix.gifsnap", diskCacheDirectory: nil, config: cacheConfig)
        let config = SDWebImageDownloaderConfig()
        config.maxConcurrentDownloads = 4; config.downloadTimeout = 15
        let session = URLSessionConfiguration.ephemeral
        session.timeoutIntervalForResource = 15
        session.httpCookieStorage = nil; session.urlCredentialStorage = nil
        session.httpShouldSetCookies = false
        config.sessionConfiguration = session
        return SDWebImageManager(cache: cache, loader: SDWebImageDownloader(config: config))
    }()
}

struct AnimatedMedia: UIViewRepresentable {
    let full: String
    let preview: String
    let isAnimating: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MediaContainer {
        _ = GifSnapAnimation.prepare
        let view = MediaContainer()
        view.imageView.maxBufferSize = 4 * 1024 * 1024
        view.imageView.contentMode = .scaleAspectFit
        view.imageView.clipsToBounds = true
        view.isAccessibilityElement = false
        return view
    }
    func updateUIView(_ view: MediaContainer, context: Context) {
        let urls = GifSnapMediaCandidates(full: full, preview: preview).urls
        context.coordinator.update(view: view, urls: urls, isAnimating: isAnimating)
    }
    static func dismantleUIView(_ view: MediaContainer, coordinator: Coordinator) {
        coordinator.token = UUID()
        view.imageView.sd_cancelCurrentImageLoad()
        view.imageView.stopAnimating()
        view.imageView.image = nil
    }
    @MainActor final class Coordinator {
        var urls: [URL]?
        let manager: SDWebImageManager
        init(manager: SDWebImageManager? = nil) { self.manager = manager ?? GifSnapAnimation.manager }
        var token = UUID()
        var animate = true
        func update(view: MediaContainer, urls: [URL], isAnimating: Bool) {
            animate = isAnimating
            view.imageView.autoPlayAnimatedImage = isAnimating
            if self.urls != urls {
                self.urls = urls; token = UUID()
                view.imageView.sd_cancelCurrentImageLoad(); view.imageView.image = nil
                view.message.text = "Loading…"; view.message.isHidden = false
                load(view: view, index: 0, token: token)
            }
            if isAnimating { view.imageView.startAnimating() } else { view.imageView.stopAnimating() }
        }
        private func load(view: MediaContainer, index: Int, token current: UUID) {
            guard let urls, index < urls.count else { view.message.text = "Media unavailable"; view.message.isHidden = false; return }
            view.imageView.sd_setImage(with: urls[index], placeholderImage: nil, options: [],
                context: [.customManager: manager, .animatedImageClass: SDAnimatedImage.self, .imageThumbnailPixelSize: CGSize(width: 480, height: 480)], progress: nil, completed: { [weak self, weak view] image, _, _, _ in
                guard let self, let view, self.token == current else { return }
                if image != nil {
                    view.message.isHidden = true
                    if self.animate { view.imageView.startAnimating() } else { view.imageView.stopAnimating() }
                } else { self.load(view: view, index: index + 1, token: current) }
            })
        }
    }
}

final class MediaContainer: UIView {
    let imageView = SDAnimatedImageView()
    let message = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        message.font = .preferredFont(forTextStyle: .caption1); message.textColor = .secondaryLabel
        message.textAlignment = .center; message.adjustsFontForContentSizeCategory = true
        for child in [imageView, message] {
            child.translatesAutoresizingMaskIntoConstraints = false; addSubview(child)
            NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: leadingAnchor), child.trailingAnchor.constraint(equalTo: trailingAnchor), child.topAnchor.constraint(equalTo: topAnchor), child.bottomAnchor.constraint(equalTo: bottomAnchor)])
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
#endif
