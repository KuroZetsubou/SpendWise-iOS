import SwiftUI

// MARK: - Segmented tabs
//
// Segmented control on a gray-100 track: the selected segment is a white pill with a soft
// shadow and a blue label.

public struct DSSegmentedTabs<Value: Hashable>: View {
    private let options: [(value: Value, label: String)]
    @Binding private var selection: Value

    public init(options: [(value: Value, label: String)], selection: Binding<Value>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let isActive = option.value == selection
                Button {
                    withAnimation(DS.Motion.standard) { selection = option.value }
                } label: {
                    Text(option.label)
                        .dsText(DS.Font.labelBold,
                                color: isActive ? DS.Colors.actionPrimary : DS.Colors.textMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background {
                            if isActive {
                                Capsule().fill(DS.Colors.surfaceCard).dsShadow(.card)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(DSPressStyle())
            }
        }
        .padding(4)
        .background(DS.Palette.gray100)
        .clipShape(Capsule())
    }
}

// MARK: - Text field
//
// 14pt radius, gray-50 fill, no visible border at rest; focus is a blue border plus halo.

public struct DSTextField: View {
    private let title: String?
    private let placeholder: String
    @Binding private var text: String
    private let icon: String?
    private let keyboard: DSKeyboard

    @FocusState private var isFocused: Bool

    public init(_ title: String? = nil,
                placeholder: String,
                text: Binding<String>,
                icon: String? = nil,
                keyboard: DSKeyboard = .default) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.icon = icon
        self.keyboard = keyboard
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.x2) {
            if let title {
                Text(title).dsText(DS.Font.labelBold, color: DS.Colors.textSecondary)
            }
            HStack(spacing: DS.Space.x3) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(DS.Colors.textMuted)
                }
                TextField(placeholder, text: $text)
                    .dsText(DS.Font.body, color: DS.Colors.textBody)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .dsKeyboard(keyboard)
            }
            .padding(.horizontal, DS.Space.cardPad)
            .frame(height: 52)
            .background(DS.Colors.surfaceSunken)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.field, style: .continuous)
                    .strokeBorder(isFocused ? DS.Colors.borderSelected : .clear,
                                  lineWidth: DS.Radius.strokeSelected)
            }
            .animation(DS.Motion.standard, value: isFocused)
        }
    }
}

public enum DSKeyboard { case `default`, decimal, number, email }

extension View {
    @ViewBuilder
    func dsKeyboard(_ kind: DSKeyboard) -> some View {
        #if os(iOS)
        switch kind {
        case .default: self.textInputAutocapitalization(.sentences)
        case .decimal: self.keyboardType(.decimalPad)
        case .number:  self.keyboardType(.numberPad)
        case .email:   self.keyboardType(.emailAddress).textInputAutocapitalization(.never)
        }
        #else
        self
        #endif
    }
}

// MARK: - Amount input
//
// The loudest field on the screen: 34pt/700, currency symbol spaced away from the figure.

public struct DSAmountInput: View {
    private let label: String
    @Binding private var text: String
    private let currency: String

    @FocusState private var isFocused: Bool

    public init(label: String = "Importo", text: Binding<String>, currency: String = "€") {
        self.label = label
        self._text = text
        self.currency = currency
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.x2) {
            Text(label).dsText(DS.Font.labelBold, color: DS.Colors.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.x3) {
                Text(currency).dsText(DS.Font.amountHero, color: DS.Colors.textMuted)
                TextField("0,00", text: $text)
                    .dsText(DS.Font.amountHero, color: DS.Colors.textHeading)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .dsKeyboard(.decimal)
            }
            .padding(.horizontal, DS.Space.cardPad)
            .padding(.vertical, DS.Space.x3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Colors.surfaceSunken)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.field, style: .continuous)
                    .strokeBorder(isFocused ? DS.Colors.borderSelected : .clear,
                                  lineWidth: DS.Radius.strokeSelected)
            }
            .animation(DS.Motion.standard, value: isFocused)
        }
    }
}

// MARK: - Select row and switch row
//
// A select row is a field-height tile showing the current value with a chevron.
// The kit's switch is the platform toggle tinted brand blue.

public struct DSSelectRow: View {
    private let label: String
    private let value: String
    private let icon: String?
    private let action: () -> Void

    public init(label: String, value: String, icon: String? = nil, action: @escaping () -> Void) {
        self.label = label
        self.value = value
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.x3) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(DS.Colors.textMuted)
                }
                Text(label).dsText(DS.Font.body, color: DS.Colors.textSecondary)
                Spacer(minLength: DS.Space.x2)
                Text(value)
                    .dsText(DS.Font.bodyMedium, color: DS.Colors.textBody)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.gray400)
            }
            .padding(.horizontal, DS.Space.cardPad)
            .frame(height: 52)
            .background(DS.Colors.surfaceSunken)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.field, style: .continuous))
        }
        .buttonStyle(DSPressStyle())
    }
}

public struct DSSwitchRow: View {
    private let icon: String?
    private let label: String
    private let sublabel: String?
    @Binding private var isOn: Bool

    public init(icon: String? = nil, label: String, sublabel: String? = nil, isOn: Binding<Bool>) {
        self.icon = icon
        self.label = label
        self.sublabel = sublabel
        self._isOn = isOn
    }

    public var body: some View {
        DSListRow(icon: icon, label: label, sublabel: sublabel, showChevron: false) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(DS.Colors.actionPrimary)
        }
    }
}
