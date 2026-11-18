import AppKit

final class ParagraphOptions: NSObject {
    private let model: SettingsModel
    let spacingCheckbox = NSButton(
        checkboxWithTitle: String(localized: "settings.addsParagraphSpacing"),
        target: nil,
        action: nil
    )
    let spacingButton = NSPopUpButton()
    let indentCheckbox = NSButton(
        checkboxWithTitle: String(localized: "settings.indentsParagraphs"),
        target: nil,
        action: nil
    )
    let indentButton = NSPopUpButton()
    let hangingCheckbox = NSButton(
        checkboxWithTitle: String(localized: "settings.hangsPunctuation"),
        target: nil,
        action: nil
    )

    init(model: SettingsModel) {
        self.model = model
        super.init()
        spacingCheckbox.target = self
        spacingCheckbox.action = #selector(changeAddsParagraphSpacing(_:))
        spacingButton.addItems(for: EditorSettings.ParagraphSpacing.self, title: \.title)
        spacingButton.target = self
        spacingButton.action = #selector(changeParagraphSpacing(_:))
        spacingButton.setAccessibilityLabel(String(localized: "settings.paragraphSpacing"))

        indentCheckbox.target = self
        indentCheckbox.action = #selector(changeIndentsParagraphs(_:))
        indentButton.addItems(for: EditorSettings.ParagraphIndent.self, title: \.title)
        indentButton.target = self
        indentButton.action = #selector(changeParagraphIndent(_:))
        indentButton.setAccessibilityLabel(String(localized: "settings.paragraphIndent"))

        hangingCheckbox.target = self
        hangingCheckbox.action = #selector(changeHangsPunctuation(_:))
    }

    func update(with settings: EditorSettings) {
        spacingCheckbox.state = settings.addsParagraphSpacing ? .on : .off
        spacingButton.selectItem(for: settings.paragraphSpacing)
        indentCheckbox.state = settings.indentsParagraphs ? .on : .off
        indentButton.selectItem(for: settings.paragraphIndent)
        hangingCheckbox.state = settings.hangsPunctuation ? .on : .off
    }

    @objc private func changeAddsParagraphSpacing(_ sender: NSButton) {
        model.update { $0.addsParagraphSpacing = sender.state == .on }
    }

    @objc private func changeParagraphSpacing(_ sender: NSPopUpButton) {
        guard let paragraphSpacing = sender.selectedCase(of: EditorSettings.ParagraphSpacing.self) else { return }
        model.update { $0.paragraphSpacing = paragraphSpacing }
    }

    @objc private func changeIndentsParagraphs(_ sender: NSButton) {
        model.update { $0.indentsParagraphs = sender.state == .on }
    }

    @objc private func changeParagraphIndent(_ sender: NSPopUpButton) {
        guard let paragraphIndent = sender.selectedCase(of: EditorSettings.ParagraphIndent.self) else { return }
        model.update { $0.paragraphIndent = paragraphIndent }
    }

    @objc private func changeHangsPunctuation(_ sender: NSButton) {
        model.update { $0.hangsPunctuation = sender.state == .on }
    }
}
