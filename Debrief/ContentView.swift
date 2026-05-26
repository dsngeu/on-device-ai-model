//
//  ContentView.swift
//  Debrief
//
//  Created by Deepak Singh on 12/03/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        AppShellView(store: store)
    }
}

#Preview {
    ContentView(store: AppStore())
}
