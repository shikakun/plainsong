import AppKit

final class OrientationOptions: NSObject {
    private let model: SettingsModel
    private let radios = EditorSettings.Orientation.allCases.map { orientation in
        NSButton(radioButtonWithTitle: orientation.title, target: nil, action: nil)
    }

    init(model: SettingsModel) {
        self.model = model
        super.init()
        for (index, radio) in radios.enumerated() {
            radio.tag = index
            radio.target = self
            radio.action = #selector(change(_:))
        }
    }

    func makeSection() -> NSGridView {
        let label = SettingsPane.label(String(localized: "settings.orientation"))
        let grid = SettingsPane.columns(radios.enumerated().map { index, radio in
            [index == 0 ? label : NSGridCell.emptyContentView, radio]
        })
        grid.rowSpacing = 6
        return grid
    }

    func update(with settings: EditorSettings) {
        for (radio, orientation) in zip(radios, EditorSettings.Orientation.allCases) {
            radio.state = settings.orientation == orientation ? .on : .off
        }
    }

    @objc private func change(_ sender: NSButton) {
        model.update { $0.orientation = EditorSettings.Orientation.allCases[sender.tag] }
    }
}
