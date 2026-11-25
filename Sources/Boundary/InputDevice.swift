/// enum wlr_input_device_type (wlroots)
public enum WlrInputDeviceType: Equatable, Sendable {
    case keyboard, pointer, touch, tablet, tabletPad, switchDevice
}

/// enum wlr_switch_type (wlroots)
public enum WlrSwitchType: Hashable, Sendable {
    case lid, tabletMode, keypadSlide
}

/// enum wlr_switch_state (wlroots)
public enum WlrSwitchState: Hashable, Sendable {
    case off, on, toggle
}

/// mango InputDevice (input/device.h), with what mango reads of its wlr_input_device and
/// libinput_device. The port's.
public struct InputDevice: Equatable, Sendable {
    /// wlr_input_device.name
    public var name: String
    /// wlr_input_device.type
    public var type: WlrInputDeviceType
    /// libinput_device_get_id_vendor, libinput_device_get_id_product
    public var vendor: Int32
    public var product: Int32
    /// libinput_device_get_device_group: one physical device
    public var deviceGroup: UInt64
    /// libinput_device_config_tap_get_finger_count
    public var tapFingerCount: Int

    public init(name: String, type: WlrInputDeviceType, vendor: Int32, product: Int32, deviceGroup: UInt64,
                tapFingerCount: Int = 0) {
        self.name = name; self.type = type; self.vendor = vendor; self.product = product
        self.deviceGroup = deviceGroup; self.tapFingerCount = tapFingerCount
    }
}
