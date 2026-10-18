#if canImport(UIKit)
import SwiftUI
import UIKit
import Brudcast

enum InboxScreen {
    static func make(inbox: BrudcastInbox, title: String) -> UIViewController {
        let list = InboxListController(inbox: inbox)
        list.title = title
        let navigation = UINavigationController(rootViewController: list)
        return navigation
    }

    static func detail(design: InAppDesign, messageId: String, inbox: BrudcastInbox, onContentHeightChange: ((CGFloat) -> Void)? = nil) -> UIViewController {
        let accent = BrudcastPresentation.keyWindow()?.tintColor ?? .systemBlue
        let view = InboxDetailView(design: design, theme: InAppTheme(accent: accent), onButton: { [weak inbox] buttonId, action in
            inbox?.buttonTapped(messageId: messageId, buttonId: buttonId, action: action)
        }, onContentHeightChange: onContentHeightChange)
        let host = UIHostingController(rootView: view)
        host.title = design.title
        return host
    }
}

/// Holds the hosting controller behind a rendered inbox entry, so the SwiftUI view keeps updating
/// while the host only keeps the view.
final class InboxDetailContainerView: UIView {
    private let controller: UIViewController

    init(controller: UIViewController) {
        self.controller = controller
        super.init(frame: .zero)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

struct InboxDetailView: View {
    let design: InAppDesign
    let theme: InAppTheme
    let onButton: (String?, InAppAction) -> Void
    var onContentHeightChange: ((CGFloat) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                InAppCardView(design: design, theme: theme, width: min(proxy.size.width, 600), onButton: onButton)
                    .frame(width: proxy.size.width)
                    .background(GeometryReader { content in
                        Color.clear.preference(key: InboxContentHeightKey.self, value: content.size.height)
                    })
            }
        }
        .onPreferenceChange(InboxContentHeightKey.self) { height in
            onContentHeightChange?(height)
        }
        .background(InAppBackground(layout: design.layout).edgesIgnoringSafeArea(.all))
    }
}

/// The height an inbox entry's design needs at the width it was given.
struct InboxContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

final class InboxListController: UITableViewController {
    private let inbox: BrudcastInbox
    private var messages: [BrudcastInAppMessage] = []
    private var hasMore = true
    private var loading = false
    private let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "No messages yet"
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    init(inbox: BrudcastInbox) {
        self.inbox = inbox
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(InboxCell.self, forCellReuseIdentifier: InboxCell.reuseId)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(reload), for: .valueChanged)
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
        reload()
    }

    @objc private func done() {
        dismiss(animated: true)
    }

    @objc private func reload() {
        load(before: nil)
    }

    private func load(before: Date?) {
        guard !loading else { return }
        loading = true
        inbox.list(before: before, limit: 20) { [weak self] result in
            guard let self = self else { return }
            self.loading = false
            self.refreshControl?.endRefreshing()
            switch result {
            case .success(let page):
                self.messages = before == nil ? page.messages : self.messages + page.messages
                self.hasMore = page.hasMore
                self.tableView.reloadData()
            case .failure(let error):
                BrudcastLogger.shared.warning("Inbox failed to load: \(error)")
            }
            self.tableView.backgroundView = self.messages.isEmpty ? self.emptyLabel : nil
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: InboxCell.reuseId, for: indexPath) as! InboxCell
        let message = messages[indexPath.row]
        cell.configure(message: message, time: formatter.localizedString(for: message.createdAt, relativeTo: Date()))
        if indexPath.row == messages.count - 1, hasMore {
            load(before: message.createdAt)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let message = messages[indexPath.row]
        inbox.open(message, from: navigationController)
        messages[indexPath.row] = BrudcastInAppMessage(
            id: message.id, campaignId: message.campaignId, format: message.format, isTest: message.isTest,
            title: message.title, preview: message.preview, thumbnailURL: message.thumbnailURL,
            isRead: true, createdAt: message.createdAt, design: message.design
        )
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        inbox.delete(messages[indexPath.row].id)
        messages.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        tableView.backgroundView = messages.isEmpty ? emptyLabel : nil
    }
}

final class InboxCell: UITableViewCell {
    static let reuseId = "BrudcastInboxCell"

    private let dot = UIView()
    private let thumbnail = UIImageView()
    private let titleLabel = UILabel()
    private let previewLabel = UILabel()
    private let timeLabel = UILabel()
    private var imageURL: URL?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        dot.backgroundColor = tintColor
        dot.layer.cornerRadius = 4
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.clipsToBounds = true
        thumbnail.layer.cornerRadius = 8
        thumbnail.backgroundColor = .secondarySystemFill
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        previewLabel.font = .preferredFont(forTextStyle: .subheadline)
        previewLabel.textColor = .secondaryLabel
        previewLabel.numberOfLines = 2
        previewLabel.adjustsFontForContentSizeCategory = true
        timeLabel.font = .preferredFont(forTextStyle: .caption1)
        timeLabel.textColor = .secondaryLabel
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let header = UIStackView(arrangedSubviews: [titleLabel, timeLabel])
        header.spacing = 8
        let text = UIStackView(arrangedSubviews: [header, previewLabel])
        text.axis = .vertical
        text.spacing = 2
        let row = UIStackView(arrangedSubviews: [dot, thumbnail, text])
        row.alignment = .center
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            thumbnail.widthAnchor.constraint(equalToConstant: 40),
            thumbnail.heightAnchor.constraint(equalToConstant: 40),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor, constant: -6),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(message: BrudcastInAppMessage, time: String) {
        titleLabel.text = message.title
        previewLabel.text = message.preview
        timeLabel.text = time
        dot.alpha = message.isRead ? 0 : 1
        accessibilityLabel = [message.isRead ? nil : "Unread", message.title, message.preview, time].compactMap { $0 }.joined(separator: ", ")
        imageURL = message.thumbnailURL
        thumbnail.image = nil
        thumbnail.isHidden = message.thumbnailURL == nil
        if let url = message.thumbnailURL {
            InAppImageLoader.shared.load(url) { [weak self] image in
                DispatchQueue.main.async {
                    guard self?.imageURL == url else { return }
                    self?.thumbnail.image = image
                }
            }
        }
    }
}
#endif
