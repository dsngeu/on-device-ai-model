//
//  DebriefApp.swift
//  Debrief
//
//  Created by Deepak Singh on 12/03/26.
//

import SwiftUI

@main
struct DebriefApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
