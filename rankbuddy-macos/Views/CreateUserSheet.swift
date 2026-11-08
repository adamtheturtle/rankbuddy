//
//  CreateUserSheet.swift
//  rankbuddy-macos
//

import SwiftUI

struct CreateUserSheet: View {
    let account: Account
    var onCreated: () -> Void
    var body: some View {
        NativeFeatureFormSheet(
            title: "New Person",
            operationID: "api_create_user",
            account: account,
            onSaved: onCreated
        )
    }
}
