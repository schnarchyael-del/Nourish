import WidgetKit
import SwiftUI

@main
struct NourishWidgetBundle: WidgetBundle {
    var body: some Widget {
        NourishHomeWidget()
        NourishLockScreenWidget()
        if #available(iOS 16.2, *) {
            NourishFeedLiveActivity()
            NourishSleepLiveActivity()
        }
    }
}
