import WidgetKit
import SwiftUI

@main
struct SpinlogWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingLiveActivityWidget()
        RandomAlbumWidget()
    }
}
