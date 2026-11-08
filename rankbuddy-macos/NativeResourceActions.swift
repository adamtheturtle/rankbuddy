//
//  NativeResourceActions.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

struct NativeResourceAction: Identifiable {
    let title: String
    let operationID: String
    var id: String {
        operationID
    }
}

enum NativeResourceKind: String, CaseIterable {
    case test, candidate, interview, question, person, team, provisioningUser, provisioningGroup

    var actions: [NativeResourceAction] {
        let pairs: [(String, String)] = switch self {
        case .test:
            [("Assessment Settings…", "api_update_test"),
             ("Additional Assessment Details…", "api_retrieve_test"),
             ("Invite Candidate…", "api_invite_candidate"),
             ("Search Candidates…", "api_search_test_candidates"),
             ("Inviters…", "api_list_all_inviters_for_a_test")]

        case .candidate:
            [("Candidate Settings…", "api_update_candidate"),
             ("Additional Candidate Details…", "api_show_candidate")]

        case .interview:
            [("Interview Settings…", "api_update_interview"),
             ("Artifacts…", "api_get_interview_artifacts"),
             ("Interviewer Notes…", "api_show_interviewer_notes"),
             ("Edit My Interviewer Note…", "api_update_interviewer_note")]

        case .question:
            [("Question Settings…", "api_update_question"),
             ("Generate Code Stubs…", "api_generate_codestubs"),
             ("Custom Code Stubs…", "api_update_codestubs"),
             ("Add Testcase…", "api_add_testcase"),
             ("Edit Testcase…", "api_update_testcase"),
             ("Delete Testcase…", "api_delete_testcase")]

        case .person:
            [("User Settings and Permissions…", "api_update_user")]

        case .team:
            [("Team Settings…", "api_update_team"),
             ("Add Existing Person…", "api_create_membership"),
             ("Membership Details…", "api_retrieve_membership")]

        case .provisioningUser:
            [("Replace User…", "api_scim_edit_user_put"),
             ("Change User Fields…", "api_scim_edit_user_patch"),
             ("Deactivate User…", "api_scim_lock_user")]

        case .provisioningGroup:
            [("Change Group…", "api_scim_update_team"),
             ("Deprovision Group…", "api_scim_deprovision_team")]
        }
        return pairs.map { NativeResourceAction(title: $0.0, operationID: $0.1) }
    }
}

private struct NativeResourceActionsModifier: ViewModifier {
    let kind: NativeResourceKind
    let account: Account?
    let path: [String: String]
    let onSaved: () -> Void
    @State private var selected: NativeResourceAction?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if account != nil {
                        Menu("\(kind.rawValue.capitalized) Actions", systemImage: "ellipsis.circle") {
                            ForEach(kind.actions) { action in
                                Button(action.title) { selected = action }
                            }
                        }
                        .help("Settings and actions")
                    }
                }
            }
            .sheet(item: $selected) { action in
                if let account {
                    NativeFeatureFormSheet(title: action.title.replacingOccurrences(of: "…", with: ""),
                                           operationID: action.operationID, account: account, path: path,
                                           onSaved: onSaved)
                }
            }
    }
}

extension View {
    func nativeResourceActions(_ kind: NativeResourceKind, account: Account?, path: [String: String],
                               onSaved: @escaping () -> Void = {}) -> some View {
        modifier(NativeResourceActionsModifier(kind: kind, account: account, path: path, onSaved: onSaved))
    }
}
