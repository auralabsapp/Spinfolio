//
//  SpinlogWidgetsLiveActivity.swift
//  SpinlogWidgets
//
//  Created by Aurélien Scarpa on 19/09/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct SpinlogWidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct SpinlogWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpinlogWidgetsAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension SpinlogWidgetsAttributes {
    fileprivate static var preview: SpinlogWidgetsAttributes {
        SpinlogWidgetsAttributes(name: "World")
    }
}

extension SpinlogWidgetsAttributes.ContentState {
    fileprivate static var smiley: SpinlogWidgetsAttributes.ContentState {
        SpinlogWidgetsAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: SpinlogWidgetsAttributes.ContentState {
         SpinlogWidgetsAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: SpinlogWidgetsAttributes.preview) {
   SpinlogWidgetsLiveActivity()
} contentStates: {
    SpinlogWidgetsAttributes.ContentState.smiley
    SpinlogWidgetsAttributes.ContentState.starEyes
}
