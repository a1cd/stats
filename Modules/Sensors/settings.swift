//
//  settings.swift
//  Sensors
//
//  Created by Serhiy Mytrovtsiy on 23/06/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Settings: NSStackView, Settings_v {
    private var updateIntervalValue: Int = 3
    private var hidState: Bool
    private var fanSpeedState: Bool = false
    private var fansSyncState: Bool = false
    private var unknownSensorsState: Bool = false
    private var fanValueState: FanValue = .percentage
    
    // Rolling average settings
    private var rollingAverageEnabled: Bool = false
    private var rollingAverageType: RollingAverageType = .sma
    private var rollingAveragePeriod: Int = 60
    private var rollingAverageAlpha: Double = 0.3
    private var rollingAverageSection: PreferencesSection?
    
    public var callback: (() -> Void) = {}
    public var HIDcallback: (() -> Void) = {}
    public var unknownCallback: (() -> Void) = {}
    public var rollingAverageCallback: (() -> Void) = {}
    public var setInterval: ((_ value: Int) -> Void) = {_ in }
    public var selectedHandler: (String) -> Void = {_ in }
    
    private let title: String
    private var button: NSPopUpButton?
    private var list: [Sensor_p] = []
    private var sensorsPrefs: PreferencesSection?
    private var selectedSensor: String = "Average System Total"
    
    public init(_ module: ModuleType) {
        self.title = module.stringValue
        self.hidState = SystemKit.shared.device.platform == .m1 ? true : false
        
        super.init(frame: NSRect.zero)
        self.orientation = .vertical
        self.spacing = Constants.Settings.margin
        
        self.updateIntervalValue = Store.shared.int(key: "\(self.title)_updateInterval", defaultValue: self.updateIntervalValue)
        self.hidState = Store.shared.bool(key: "\(self.title)_hid", defaultValue: self.hidState)
        self.fanSpeedState = Store.shared.bool(key: "\(self.title)_speed", defaultValue: self.fanSpeedState)
        self.fansSyncState = Store.shared.bool(key: "\(self.title)_fansSync", defaultValue: self.fansSyncState)
        self.unknownSensorsState = Store.shared.bool(key: "\(self.title)_unknown", defaultValue: self.unknownSensorsState)
        self.fanValueState = FanValue(rawValue: Store.shared.string(key: "\(self.title)_fanValue", defaultValue: self.fanValueState.rawValue)) ?? .percentage
        self.selectedSensor = Store.shared.string(key: "\(self.title)_sensor", defaultValue: self.selectedSensor)
        
        // Load rolling average settings
        self.rollingAverageEnabled = Store.shared.bool(key: "\(self.title)_rollingAverage", defaultValue: self.rollingAverageEnabled)
        self.rollingAverageType = RollingAverageType(rawValue: Store.shared.string(key: "\(self.title)_rollingAverageType", defaultValue: self.rollingAverageType.rawValue)) ?? .sma
        self.rollingAveragePeriod = Store.shared.int(key: "\(self.title)_rollingAveragePeriod", defaultValue: self.rollingAveragePeriod)
        let alphaString = Store.shared.string(key: "\(self.title)_rollingAverageAlpha", defaultValue: "\(self.rollingAverageAlpha)")
        self.rollingAverageAlpha = Double(alphaString) ?? 0.3
        
        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Update interval"), component: selectView(
                action: #selector(self.changeUpdateInterval),
                items: ReaderUpdateIntervals,
                selected: "\(self.updateIntervalValue)"
            ))
        ]))
        
        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Fan value"), component: selectView(
                action: #selector(self.toggleFanValue),
                items: FanValues,
                selected: self.fanValueState.rawValue
            )),
            PreferencesRow(localizedString("Save the fan speed"), component: switchView(
                action: #selector(self.toggleSpeedState),
                state: self.fanSpeedState
            )),
            PreferencesRow(localizedString("Synchronize fan's control"), component: switchView(
                action: #selector(self.toggleFansSync),
                state: self.fansSyncState
            ))
        ]))
        
        var sensorsRows: [PreferencesRow] = [
            PreferencesRow(localizedString("Show unknown sensors"), component: switchView(
                action: #selector(self.toggleuUnknownSensors),
                state: self.unknownSensorsState
            ))
        ]
        if isARM {
            sensorsRows.append(PreferencesRow(localizedString("HID sensors"), component: switchView(
                action: #selector(self.toggleHID),
                state: self.hidState
            )))
        }
        sensorsRows.append(PreferencesRow(localizedString("Sensor to show"), id: "active_sensor", component: selectView(
            action: #selector(self.handleSelection),
            items: [],
            selected: self.selectedSensor)
        ))
        let sensorsPrefs = PreferencesSection(sensorsRows)
        self.sensorsPrefs = sensorsPrefs
        self.addArrangedSubview(sensorsPrefs)
        
        // Rolling average settings section
        self.createRollingAverageSection()
    }
    
    private func createRollingAverageSection() {
        // Remove existing rolling average section if it exists
        if let existingSection = self.rollingAverageSection {
            existingSection.removeFromSuperview()
        }
        
        var rollingRows: [PreferencesRow] = [
            PreferencesRow(localizedString("Enable rolling average"), component: switchView(
                action: #selector(self.toggleRollingAverage),
                state: self.rollingAverageEnabled
            )),
            PreferencesRow(localizedString("Algorithm type"), component: selectView(
                action: #selector(self.toggleRollingAverageType),
                items: RollingAverageTypes,
                selected: self.rollingAverageType.rawValue
            )),
            PreferencesRow(localizedString("Sample count"), component: selectView(
                action: #selector(self.toggleRollingAveragePeriod),
                items: RollingAveragePeriods,
                selected: "\(self.rollingAveragePeriod)"
            ))
        ]
        
        if self.rollingAverageType == .ema {
            rollingRows.append(PreferencesRow(localizedString("Smoothing factor"), component: selectView(
                action: #selector(self.toggleRollingAverageAlpha),
                items: EMAAlphaValues,
                selected: "\(self.rollingAverageAlpha)"
            )))
        }
        
        let rollingPrefs = PreferencesSection(rollingRows, label: localizedString("Rolling Average System Total"))
        self.rollingAverageSection = rollingPrefs
        self.addArrangedSubview(rollingPrefs)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func load(widgets: [widget_t]) {
        var sensors = self.list
        guard !sensors.isEmpty else {
            return
        }
        if !self.unknownSensorsState {
            sensors = sensors.filter({ $0.group != .unknown })
        }
        
        self.subviews.filter({ $0.identifier == NSUserInterfaceItemIdentifier("sensor") }).forEach { v in
            v.removeFromSuperview()
        }
        
        var types: [SensorType] = []
        sensors.forEach { (s: Sensor_p) in
            if !types.contains(s.type) {
                types.append(s.type)
            }
        }
        
        var buttonList: [KeyValue_t] = []
        types.forEach { (typ: SensorType) in
            let section = PreferencesSection(label: localizedString(typ.rawValue))
            section.identifier = NSUserInterfaceItemIdentifier("sensor")
            
            let filtered = sensors.filter{ $0.type == typ }
            var groups: [SensorGroup] = []
            filtered.forEach { (s: Sensor_p) in
                if !groups.contains(s.group) {
                    groups.append(s.group)
                }
            }
            groups.forEach { (group: SensorGroup) in
                filtered.filter{ $0.group == group }.forEach { (s: Sensor_p) in
                    let btn = switchView(
                        action: #selector(self.toggleSensor),
                        state: s.state
                    )
                    btn.identifier = NSUserInterfaceItemIdentifier(rawValue: s.key)
                    section.add(PreferencesRow(localizedString(s.name), component: btn))
                    buttonList.append(KeyValue_t(key: s.key, value: "\(localizedString(typ.rawValue)) - \(s.name)"))
                }
            }
            
            self.addArrangedSubview(section)
        }
        
        if let row = self.sensorsPrefs?.findRow("active_sensor") {
            if !widgets.isEmpty {
                self.sensorsPrefs?.setRowVisibility(row, newState: widgets.contains(where: { $0 == .mini }))
            }
            row.replaceComponent(with: selectView(
                action: #selector(self.handleSelection),
                items: buttonList,
                selected: self.selectedSensor
            ))
        }
    }
    
    public func setList(_ list: [Sensor_p]?) {
        guard let list else { return }
        self.list = self.unknownSensorsState ? list : list.filter({ $0.group != .unknown })
        self.load(widgets: [])
    }
    
    @objc private func toggleSensor(_ sender: NSControl) {
        guard let id = sender.identifier else { return }
        Store.shared.set(key: "sensor_\(id.rawValue)", value: controlState(sender))
        self.callback()
    }
    @objc private func changeUpdateInterval(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let value = Int(key) else { return }
        self.updateIntervalValue = value
        Store.shared.set(key: "\(self.title)_updateInterval", value: value)
        self.setInterval(value)
    }
    @objc private func toggleSpeedState(_ sender: NSControl) {
        self.fanSpeedState = controlState(sender)
        Store.shared.set(key: "\(self.title)_speed", value: self.fanSpeedState)
        self.callback()
    }
    @objc private func toggleHID(_ sender: NSControl) {
        self.hidState = controlState(sender)
        Store.shared.set(key: "\(self.title)_hid", value: self.hidState)
        self.HIDcallback()
    }
    @objc private func toggleFansSync(_ sender: NSControl) {
        self.fansSyncState = controlState(sender)
        Store.shared.set(key: "\(self.title)_fansSync", value: self.fansSyncState)
    }
    @objc private func toggleuUnknownSensors(_ sender: NSControl) {
        self.unknownSensorsState = controlState(sender)
        Store.shared.set(key: "\(self.title)_unknown", value: self.unknownSensorsState)
        self.unknownCallback()
    }
    @objc private func toggleFanValue(_ sender: NSMenuItem) {
        if let key = sender.representedObject as? String, let value = FanValue(rawValue: key) {
            self.fanValueState = value
            Store.shared.set(key: "\(self.title)_fanValue", value: self.fanValueState.rawValue)
            self.callback()
        }
    }
    @objc private func handleSelection(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem, let id = item.representedObject as? String else { return }
        self.selectedSensor = id
        Store.shared.set(key: "\(self.title)_sensor", value: self.selectedSensor)
        self.selectedHandler(self.selectedSensor)
    }
    
    // MARK: - Rolling Average Actions
    
    @objc private func toggleRollingAverage(_ sender: NSControl) {
        self.rollingAverageEnabled = controlState(sender)
        Store.shared.set(key: "\(self.title)_rollingAverage", value: self.rollingAverageEnabled)
        self.rollingAverageCallback()
    }
    
    @objc private func toggleRollingAverageType(_ sender: NSMenuItem) {
        if let key = sender.representedObject as? String, let value = RollingAverageType(rawValue: key) {
            self.rollingAverageType = value
            Store.shared.set(key: "\(self.title)_rollingAverageType", value: self.rollingAverageType.rawValue)
            self.rollingAverageCallback()
            
            // Recreate the rolling average section to show/hide EMA settings
            self.createRollingAverageSection()
        }
    }
    
    @objc private func toggleRollingAveragePeriod(_ sender: NSMenuItem) {
        if let key = sender.representedObject as? String, let value = Int(key) {
            self.rollingAveragePeriod = value
            Store.shared.set(key: "\(self.title)_rollingAveragePeriod", value: self.rollingAveragePeriod)
            self.rollingAverageCallback()
        }
    }
    
    @objc private func toggleRollingAverageAlpha(_ sender: NSMenuItem) {
        if let key = sender.representedObject as? String, let value = Double(key) {
            self.rollingAverageAlpha = value
            Store.shared.set(key: "\(self.title)_rollingAverageAlpha", value: "\(self.rollingAverageAlpha)")
            self.rollingAverageCallback()
        }
    }
}
