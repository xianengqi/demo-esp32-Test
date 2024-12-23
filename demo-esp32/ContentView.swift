//
//  ContentView.swift
//  demo-esp32
//
//  Created by 信测iOS开发 on 2024/12/23.
//

import SwiftUI
import CoreBluetooth

// 定义发现的设备结构
struct DiscoveredDevice: Identifiable, Hashable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
    
    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// 定义蓝牙状态
enum BluetoothState: Equatable {
    case poweredOff
    case poweredOn
    case scanning
    case connected
    case configuring
    case configured
    case error(String)
    
    // 实现 Equatable
    static func == (lhs: BluetoothState, rhs: BluetoothState) -> Bool {
        switch (lhs, rhs) {
        case (.poweredOff, .poweredOff),
             (.poweredOn, .poweredOn),
             (.scanning, .scanning),
             (.connected, .connected),
             (.configuring, .configuring),
             (.configured, .configured):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

// 主视图
struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @State private var wifiSSID: String = ""
    @State private var wifiPassword: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // 状态显示
            statusView
            
            // 设备列表
            if bluetoothManager.state == .scanning {
                deviceListView
            }
            
            // WiFi配置表单
            if bluetoothManager.state == .connected {
                wifiConfigForm
            }
            
            // 操作按钮
            actionButton
        }
        .padding()
    }
    
    // 设备列表视图
    private var deviceListView: some View {
        List(bluetoothManager.discoveredDevices) { device in
            HStack {
                VStack(alignment: .leading) {
                    Text(device.name)
                        .font(.headline)
                    Text("信号强度: \(device.rssi) dBm")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                Spacer()
                if device.name.contains("ESP32") {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .padding(.vertical, 4)
        }
        .listStyle(.plain)
        .frame(height: 200)
    }
    
    // 状态显示视图
    private var statusView: some View {
        VStack {
            Image(systemName: statusIcon)
                .imageScale(.large)
                .foregroundStyle(statusColor)
            
            Text(statusText)
                .foregroundColor(statusColor)
        }
    }
    
    // WiFi配置表单
    private var wifiConfigForm: some View {
        VStack {
            TextField("WiFi名称", text: $wifiSSID)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            SecureField("WiFi密码", text: $wifiPassword)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
    
    // 操作按钮
    private var actionButton: some View {
        Button(action: handleButtonTap) {
            Text(buttonText)
                .foregroundColor(.white)
                .padding()
                .background(buttonColor)
                .cornerRadius(8)
        }
    }
    
    // 状态图标
    private var statusIcon: String {
        switch bluetoothManager.state {
        case .poweredOff: return "bolt.horizontal.circle"
        case .poweredOn: return "bolt.horizontal.circle.fill"
        case .scanning: return "arrow.triangle.2.circlepath"
        case .connected: return "wifi.circle.fill"
        case .configuring: return "gearshape.fill"
        case .configured: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
    
    // 状态颜色
    private var statusColor: Color {
        switch bluetoothManager.state {
        case .configured: return .green
        case .error: return .red
        default: return .blue
        }
    }
    
    // 状态文本
    private var statusText: String {
        switch bluetoothManager.state {
        case .poweredOff: return "蓝牙已关闭"
        case .poweredOn: return "蓝牙已开启"
        case .scanning: return "正在扫描设备..."
        case .connected: return "设备已连接"
        case .configuring: return "正在配置WiFi..."
        case .configured: return "配置成功"
        case .error(let message): return "错误: \(message)"
        }
    }
    
    // 按钮文本
    private var buttonText: String {
        switch bluetoothManager.state {
        case .poweredOff: return "打开蓝牙"
        case .poweredOn: return "开始扫描"
        case .scanning: return "停止扫描"
        case .connected: return "配置WiFi"
        case .configuring: return "配置中..."
        case .configured: return "完成"
        case .error: return "重试"
        }
    }
    
    // 按钮颜色
    private var buttonColor: Color {
        switch bluetoothManager.state {
        case .configured: return .green
        case .error: return .red
        case .configuring: return .gray
        default: return .blue
        }
    }
    
    // 按钮点击处理
    private func handleButtonTap() {
        switch bluetoothManager.state {
        case .poweredOff:
            if let settingsUrl = URL(string: "App-Prefs:root=Bluetooth") {
                #if canImport(UIKit)
                UIApplication.shared.open(settingsUrl)
                #endif
            }
        case .poweredOn:
            bluetoothManager.startScan()
        case .scanning:
            bluetoothManager.stopScan()
        case .connected:
            bluetoothManager.configureWiFi(ssid: wifiSSID, password: wifiPassword)
        case .configured, .error:
            bluetoothManager.reset()
        default:
            break
        }
    }
}

// 蓝牙管理器
class BluetoothManager: NSObject, ObservableObject {
    @Published var state: BluetoothState = .poweredOff
    @Published var discoveredDevices: [DiscoveredDevice] = []
    
    private var centralManager: CBCentralManager!
    private var blufiClient: BlufiClient?
    private var peripheral: CBPeripheral?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScan() {
        print("开始扫描蓝牙设备...")
        discoveredDevices.removeAll()
        state = .scanning
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    func stopScan() {
        centralManager.stopScan()
        state = .poweredOn
    }
    
    func configureWiFi(ssid: String, password: String) {
        guard let blufiClient = blufiClient else {
            state = .error("BlufiClient未初始化")
            return
        }
        
        state = .configuring
        
        // 创建配置参数
        let params = BlufiConfigureParams()
        params.opMode = OpModeSta
        params.staSsid = ssid
        params.staPassword = password
        
        // 开始配网
        blufiClient.configure(params)
    }
    
    func reset() {
        blufiClient?.close()
        blufiClient = nil
        peripheral = nil
        state = .poweredOn
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            state = .poweredOn
        case .poweredOff:
            state = .poweredOff
        default:
            state = .error("蓝牙状态异常")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
//        print("发现设备: \(peripheral.name ?? "Unknown Device") - RSSI: \(RSSI)")
        
        let deviceName = peripheral.name ?? "Unknown Device"
        
        // 检查设备是否已存在
        if !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
            let device = DiscoveredDevice(
                id: UUID(),
                peripheral: peripheral,
                name: deviceName,
                rssi: RSSI.intValue
            )
            DispatchQueue.main.async {
                self.discoveredDevices.append(device)
            }
        }
        
        // 如果是ESP32设备，自动连接
        if deviceName.contains("ESP32") {
            print("找到目标ESP32设备：\(deviceName)")
            self.peripheral = peripheral
            central.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .connected
        stopScan()
        
        // 初始化BlufiClient
        blufiClient = BlufiClient()
        blufiClient?.blufiDelegate = self
        blufiClient?.connect(peripheral.identifier.uuidString)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        state = .error("连接失败: \(error?.localizedDescription ?? "未知错误")")
    }
}

// MARK: - BlufiDelegate
extension BluetoothManager: BlufiDelegate {
    func blufi(_ client: BlufiClient, gattPrepared status: BlufiStatusCode, service: CBService?, writeChar: CBCharacteristic?, notifyChar: CBCharacteristic?) {
        if status == StatusSuccess {
            // GATT准备就绪，可以开始协商安全
            client.negotiateSecurity()
        } else {
            state = .error("GATT准备失败")
        }
    }
    
    func blufi(_ client: BlufiClient, didNegotiateSecurity status: BlufiStatusCode) {
        if status != StatusSuccess {
            state = .error("安全协商失败")
        }
    }
    
    func blufi(_ client: BlufiClient, didPostConfigureParams status: BlufiStatusCode) {
        DispatchQueue.main.async {
            if status == StatusSuccess {
                self.state = .configured
            } else {
                self.state = .error("WiFi配置失败")
            }
        }
    }
}

#Preview {
    ContentView()
}
