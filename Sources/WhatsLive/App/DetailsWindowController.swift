import AppKit

@MainActor
final class DetailsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let store: ServiceStore
    private let tableView = NSTableView()
    private let detailView = NSTextView()
    private var services: [RunningService] = []
    private var observerID: UUID?

    init(store: ServiceStore) {
        self.store = store

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = tableView

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("service"))
        column.title = "Services"
        column.width = 220
        tableView.addTableColumn(column)
        tableView.headerView = nil
        detailView.isEditable = false
        detailView.isSelectable = true
        detailView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detailView.textContainerInset = NSSize(width: 14, height: 14)

        let detailScroll = NSScrollView()
        detailScroll.hasVerticalScroller = true
        detailScroll.documentView = detailView

        splitView.addArrangedSubview(scroll)
        splitView.addArrangedSubview(detailScroll)
        splitView.setPosition(230, ofDividerAt: 0)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "What's Live Details"
        window.contentView = splitView

        super.init(window: window)

        tableView.delegate = self
        tableView.dataSource = self

        observerID = store.observe { [weak self] _ in
            self?.reload()
        }
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        services.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier
        cell.textField = cell.textField ?? NSTextField(labelWithString: "")
        if cell.textField?.superview == nil, let textField = cell.textField {
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        let service = services[row]
        cell.textField?.stringValue = "\(service.title) :\(service.portSummary)"
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard services.indices.contains(row) else { return }
        store.selectedServiceID = services[row].id
        render(service: services[row])
    }

    private func reload() {
        services = store.snapshot.services
        tableView.reloadData()
        if let selected = store.selectedService {
            if let index = services.firstIndex(where: { $0.id == selected.id }) {
                tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            }
            render(service: selected)
        } else if let first = services.first {
            store.selectedServiceID = first.id
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            render(service: first)
        } else {
            detailView.string = "No services matched the current filters."
        }
    }

    private func render(service: RunningService) {
        detailView.string = """
        \(service.title)
        \(service.kind.rawValue) - \(service.status.rawValue)

        PID: \(service.pid.map(String.init) ?? "none")
        Parent PID: \(service.parentPID.map(String.init) ?? "none")
        User: \(service.user)
        Ports: \(service.ports.map { "\($0.displayAddress):\($0.port)" }.joined(separator: ", "))
        HTTP: \(service.httpProbe ?? "not detected")
        Age: \(TimeFormatters.shortDate(service.startDate))
        CWD: \(pathDisplay(service.cwd))
        Safety: \(service.safety.rawValue)
        Docker: \(service.dockerStatus ?? "none")

        Command:
        \(service.command)

        Classification:
        \(service.classificationReason)

        Stale signals:
        \(service.staleReasons.isEmpty ? "none" : service.staleReasons.joined(separator: ", "))

        Kill history:
        \(service.killHistory.isEmpty ? "none" : service.killHistory.map { "\(TimeFormatters.shortDate($0.date)): \($0.message)" }.joined(separator: "\n"))
        """
    }
}
