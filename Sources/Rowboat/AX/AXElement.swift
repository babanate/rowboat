import AppKit
import ApplicationServices

/// Thin wrapper over AXUIElement. Every call is an IPC round trip into the
/// target app; batch with `values(for:)` wherever possible.
struct AXElement: Hashable {
    let raw: AXUIElement

    init(_ raw: AXUIElement) { self.raw = raw }

    static func application(pid: pid_t) -> AXElement { AXElement(AXUIElementCreateApplication(pid)) }
    static let systemWide = AXElement(AXUIElementCreateSystemWide())

    static func == (a: AXElement, b: AXElement) -> Bool { CFEqual(a.raw, b.raw) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(raw)) }

    var pid: pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(raw, &p)
        return p
    }

    func value(_ attribute: String) -> Any? {
        var out: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(raw, attribute as CFString, &out)
        guard err == .success, let out else { return nil }
        return Self.unwrap(out)
    }

    /// Fetches several attributes in one IPC call. Missing attributes are nil.
    func values(for attributes: [String]) -> [Any?] {
        var out: CFArray?
        let err = AXUIElementCopyMultipleAttributeValues(raw, attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &out)
        guard err == .success, let array = out as? [AnyObject], array.count == attributes.count else {
            return Array(repeating: nil, count: attributes.count)
        }
        return array.map(Self.unwrap)
    }

    func string(_ attribute: String) -> String? { value(attribute) as? String }
    func element(_ attribute: String) -> AXElement? { value(attribute) as? AXElement }
    func elements(_ attribute: String) -> [AXElement] { value(attribute) as? [AXElement] ?? [] }

    var role: String? { string(kAXRoleAttribute) }
    var children: [AXElement] { elements(kAXChildrenAttribute) }
    var frame: CGRect? { Self.frame(position: value(kAXPositionAttribute), size: value(kAXSizeAttribute)) }

    var actionNames: [String] {
        var out: CFArray?
        guard AXUIElementCopyActionNames(raw, &out) == .success else { return [] }
        return out as? [String] ?? []
    }

    @discardableResult
    func perform(_ action: String) -> AXError { AXUIElementPerformAction(raw, action as CFString) }

    @discardableResult
    func set(_ attribute: String, _ value: Any) -> AXError {
        AXUIElementSetAttributeValue(raw, attribute as CFString, value as CFTypeRef)
    }

    func parameterized(_ attribute: String, parameter: Any) -> Any? {
        var out: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(raw, attribute as CFString, parameter as CFTypeRef, &out)
        guard err == .success, let out else { return nil }
        return Self.unwrap(out)
    }

    // MARK: conversions

    /// Converts CF values to Swift values: AXUIElement to AXElement, AXValue
    /// to CGPoint/CGSize/CGRect, error placeholders to nil.
    static func unwrap(_ value: AnyObject) -> Any? {
        let typeID = CFGetTypeID(value)
        if typeID == AXUIElementGetTypeID() {
            return AXElement(value as! AXUIElement)
        }
        if typeID == AXValueGetTypeID() {
            let axValue = value as! AXValue
            switch AXValueGetType(axValue) {
            case .cgPoint:
                var p = CGPoint.zero; AXValueGetValue(axValue, .cgPoint, &p); return p
            case .cgSize:
                var s = CGSize.zero; AXValueGetValue(axValue, .cgSize, &s); return s
            case .cgRect:
                var r = CGRect.zero; AXValueGetValue(axValue, .cgRect, &r); return r
            case .cfRange:
                var r = CFRange(); AXValueGetValue(axValue, .cfRange, &r); return r
            case .axError:
                return nil
            default:
                return nil
            }
        }
        if typeID == CFArrayGetTypeID() {
            let items = (value as! [AnyObject]).map(unwrap)
            let elements = items.compactMap { $0 as? AXElement }
            return elements.count == items.count ? elements : items
        }
        if typeID == CFNullGetTypeID() { return nil }
        if typeID == CFBooleanGetTypeID() { return (value as! CFBoolean) == kCFBooleanTrue }
        if typeID == CFNumberGetTypeID() { return (value as! NSNumber).doubleValue }
        if typeID == CFStringGetTypeID() { return value as! String }
        if typeID == CFAttributedStringGetTypeID() { return (value as! NSAttributedString).string }
        if typeID == CFURLGetTypeID() { return (value as! URL).absoluteString }
        return value
    }

    static func frame(position: Any?, size: Any?) -> CGRect? {
        guard let p = position as? CGPoint, let s = size as? CGSize else { return nil }
        return CGRect(origin: p, size: s)
    }
}

