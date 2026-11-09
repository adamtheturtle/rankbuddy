//
//  NativeRecordPresentation.swift
//  rankbuddy-macos
//

enum NativeRecordStyle {
    case general, audit
}

enum NativeRecordPresentation {
    static func label(_ field: String, style: NativeRecordStyle) -> String {
        if field == "ip_address" {
            return "IP Address"
        }
        if style == .audit {
            switch field {
            case "from": return "Before"
            case "to": return "After"
            case "modified_fields": return "Changed Fields"
            case "modified_values": return "Changes"
            case "av_provider": return "AV Provider"
            default: break
            }
        }
        return NativeFormSchema.title(field)
    }
}
