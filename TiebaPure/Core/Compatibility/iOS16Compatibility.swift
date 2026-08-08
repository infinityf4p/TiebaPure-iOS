import SwiftUI
import UIKit

// MARK: - ContentUnavailableView (iOS 17+)

struct CompatibleContentUnavailableView<Label: View, Description: View>: View {
    private let label: Label
    private let description: Description?

    init(
        @ViewBuilder label: () -> Label,
        @ViewBuilder description: () -> Description
    ) {
        self.label = label()
        self.description = description()
    }

    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView {
                label
            } description: {
                description
            }
        } else {
            VStack(spacing: 12) {
                label
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                if let description {
                    description
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

extension CompatibleContentUnavailableView where Description == EmptyView {
    init(@ViewBuilder label: () -> Label) {
        self.label = label()
        self.description = nil
    }
}

struct CompatibleContentUnavailableSimple: View {
    let title: String
    let systemImage: String
    let description: String?

    init(_ title: String, systemImage: String, description: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        if #available(iOS 17.0, *) {
            if let description {
                ContentUnavailableView(
                    title,
                    systemImage: systemImage,
                    description: Text(description)
                )
            } else {
                ContentUnavailableView(title, systemImage: systemImage)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let description {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

// MARK: - onChange helpers

extension View {
    @ViewBuilder
    func onChangeCompat<V: Equatable>(
        of value: V,
        perform action: @escaping (V) -> Void
    ) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value, perform: action)
        }
    }

    @ViewBuilder
    func onChangeCompat<V: Equatable>(
        of value: V,
        perform action: @escaping (_ oldValue: V, _ newValue: V) -> Void
    ) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value) { oldValue, newValue in
                action(oldValue, newValue)
            }
        } else {
            self.onChange(of: value) { newValue in
                action(value, newValue)
            }
        }
    }

    @ViewBuilder
    func onChangeCompat<V: Equatable>(
        of value: V,
        initial: Bool,
        perform action: @escaping (_ oldValue: V, _ newValue: V) -> Void
    ) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value, initial: initial) { oldValue, newValue in
                action(oldValue, newValue)
            }
        } else {
            self
                .onAppear {
                    if initial {
                        action(value, value)
                    }
                }
                .onChange(of: value) { newValue in
                    action(value, newValue)
                }
        }
    }
}

// MARK: - Task.sleep Duration bridge

enum CompatibleTaskSleep {
    static func milliseconds(_ value: UInt64) async throws {
        try await Task.sleep(nanoseconds: value * 1_000_000)
    }

    static func seconds(_ value: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(value * 1_000_000_000))
    }

    static func duration(_ duration: Duration) async throws {
        let components = duration.components
        let nanos = UInt64(components.seconds) * 1_000_000_000
            + UInt64(components.attoseconds / 1_000_000_000)
        try await Task.sleep(nanoseconds: nanos)
    }
}

// MARK: - Scroll / toolbar helpers

extension View {
    @ViewBuilder
    func scrollBounceBehaviorAlwaysVertical() -> some View {
        if #available(iOS 16.4, *) {
            self.scrollBounceBehaviorAlwaysVertical()
        } else {
            self
        }
    }

    @ViewBuilder
    func removeSidebarToggleIfAvailable() -> some View {
        if #available(iOS 17.0, *) {
            self.toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }

    @ViewBuilder
    func presentationBackgroundClearIfAvailable() -> some View {
        if #available(iOS 16.4, *) {
            self.presentationBackground(.clear)
        } else {
            self
        }
    }

    @ViewBuilder
    func navigationDestinationCompat<V: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: @escaping () -> V
    ) -> some View {
        if #available(iOS 17.0, *) {
            self.navigationDestination(isPresented: isPresented, destination: destination)
        } else {
            self.background(
                NavigationLink(
                    isActive: isPresented,
                    destination: destination,
                    label: { EmptyView() }
                )
                .hidden()
            )
        }
    }
}

// MARK: - Trait change observation

extension UIView {
    func observePreferredContentSizeCategoryChanges(
        _ handler: @escaping (UIView) -> Void
    ) {
        if #available(iOS 17.0, *) {
            registerForTraitChanges(
                [UITraitPreferredContentSizeCategory.self, UITraitLegibilityWeight.self]
            ) { (view: UIView, _) in
                handler(view)
            }
        } else {
            NotificationCenter.default.addObserver(
                forName: UIContentSizeCategory.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                handler(self)
            }
        }
    }
}
