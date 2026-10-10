import SwiftUI
import WidgetKit

/// The widget extension holds only the hands-free Live Activity: no home screen widgets.
@main
struct OrbActivityBundle: WidgetBundle {
    var body: some Widget {
        OrbLiveActivity()
    }
}
