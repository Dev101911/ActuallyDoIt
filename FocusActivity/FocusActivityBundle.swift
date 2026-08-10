//
//  FocusActivityBundle.swift
//  FocusActivity
//
//  Created by Devin Harmse on 03/08/2026.
//

import WidgetKit
import SwiftUI

@main
struct FocusActivityBundle: WidgetBundle {
    var body: some Widget {
        FocusActivityLiveActivity()
        TasksWidget()
    }
}
