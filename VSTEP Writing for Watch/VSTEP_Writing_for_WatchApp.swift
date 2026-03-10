//
//  VSTEP_Writing_for_WatchApp.swift
//  VSTEP Writing for Watch Watch App
//
//  Created by Vinh Hap Hoi on 3/10/26.
//

import SwiftUI

@main
struct VSTEP_Writing_for_WatchApp: App {
    init() {
        // Must activate on init, not onAppear
        WatchSessionManager.shared.activateSession()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
