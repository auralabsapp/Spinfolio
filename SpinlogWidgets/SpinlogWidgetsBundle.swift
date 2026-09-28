//
//  SpinlogWidgetsBundle.swift
//  SpinlogWidgets
//
//  Created by Aurélien Scarpa on 19/09/2026.
//

import WidgetKit
import SwiftUI

@main
struct SpinlogWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SpinlogWidgets()
        SpinlogWidgetsLiveActivity()
    }
}
