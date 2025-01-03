//
//  ContentView.swift
//  demo-esp32
//
//  Created by 信测iOS开发 on 2024/12/23.
//

import SwiftUI
import CoreBluetooth
import UIKit

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

class BluetoothViewModel: ObservableObject {
    @Published var state: BluetoothState = .poweredOff
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var wifiNetworks: [WiFiNetwork] = []
    @Published var isWifiScanning: Bool = false
    
    private let blufiManager = BlufiManager.shared
    
    init() {
        setupCallbacks()
    }
    
    private func setupCallbacks() {
        blufiManager.onStateUpdate = { [weak self] message in
            DispatchQueue.main.async {
                switch message {
                case "蓝牙已开启":
                    self?.state = .poweredOn
                case "蓝牙已关闭":
                    self?.state = .poweredOff
                default:
                    break
                }
            }
        }
        
        blufiManager.onError = { [weak self] message in
            DispatchQueue.main.async {
                self?.state = .error(message)
            }
        }
        
        blufiManager.onConnected = { [weak self] in
            DispatchQueue.main.async {
                self?.state = .connected
            }
        }
        
        blufiManager.onConfigured = { [weak self] in
            DispatchQueue.main.async {
                self?.state = .configured
            }
        } 

        // 在 setupCallbacks() 中添加
        blufiManager.onWifiScanResult = { [weak self] results in
            DispatchQueue.main.async {
                self?.isWifiScanning = false
                print("【DEBUGView】处理扫描结果:")
                self?.wifiNetworks = results
                    .compactMap { result in
                        print("【DEBUGView】处理WiFi: \(result.ssid)")
                        return WiFiNetwork(ssid: result.ssid, rssi: result.rssi)
                    }
                    .sorted { $0.rssi > $1.rssi }
            }
        }
        
        // 添加设备发现回调
        blufiManager.onDeviceFound = { [weak self] (peripheral, RSSI) in
            DispatchQueue.main.async {
                // 检查设备是否已存在
                if !(self?.discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) ?? false) {
                    let device = DiscoveredDevice(
                        id: UUID(),
                        peripheral: peripheral,
                        name: peripheral.name ?? "Unknown Device",
                        rssi: RSSI.intValue
                    )
                    self?.discoveredDevices.append(device)
                }
            }
        }
    }
    
    func startScan() {
        state = .scanning
        discoveredDevices.removeAll()
        blufiManager.startScan()
    }
    
    func stopScan() {
        blufiManager.stopScan()
        state = .poweredOn
    }
    
    func connectToDevice(_ device: DiscoveredDevice) {
        blufiManager.connect(peripheral: device.peripheral)
    }
    
    func configureWiFi(ssid: String, password: String) {
        state = .configuring
        blufiManager.configureWiFi(ssid: ssid, password: password)
    }
    
    func reset() {
        blufiManager.disconnect()
        state = .poweredOn
        discoveredDevices.removeAll()
    }
    
    func scanWiFi() {
        isWifiScanning = true
        wifiNetworks.removeAll()
        blufiManager.scanWiFi()
    }
}

struct WiFiNetwork: Identifiable, Hashable {
    let id = UUID()
    let ssid: String
    let rssi: Int8
    
    static func == (lhs: WiFiNetwork, rhs: WiFiNetwork) -> Bool {
        return lhs.ssid == rhs.ssid
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ssid)
    }
}

struct ContentView: View {
    @StateObject private var viewModel = BluetoothViewModel()
    @State private var wifiSSID: String? = nil
    @State private var wifiPassword: String = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                statusView
                
                if viewModel.state == .scanning {
                    deviceListView
                }
                
                if viewModel.state == .connected {
                    wifiConfigForm
                }
                
                actionButton
            }
            .padding()
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
    
    private var deviceListView: some View {
        List(viewModel.discoveredDevices) { device in
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
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.connectToDevice(device)
            }
        }
        .listStyle(.plain)
        .frame(height: 200)
    }
    
    private var statusView: some View {
        VStack {
            Image(systemName: statusIcon)
                .imageScale(.large)
                .foregroundStyle(statusColor)
            
            Text(statusText)
                .foregroundColor(statusColor)
        }
    }
    
    private var wifiConfigForm: some View {
        VStack(spacing: 20) {
            Button(action: {
                if let url = URL(string: "App-Prefs:root=PERSONAL_HOTSPOT") {
                    UIApplication.shared.open(url)
                }
            }) {
                HStack {
                    Image(systemName: "personalhotspot")
                    Text("开启个人热点")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(8)
            }

            Button(action: {
                scanWiFiWithRetry()
            }) {
                HStack {
                    Text(viewModel.state == .configuring ? "正在扫描..." : "扫描附近WiFi")
                    if viewModel.state == .configuring {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.state == .configuring ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(viewModel.state == .configuring)
            
            if viewModel.isWifiScanning {
                ProgressView("正在扫描WiFi网络...")
                    .progressViewStyle(CircularProgressViewStyle())
            } else if viewModel.wifiNetworks.isEmpty {
                Text("未找到WiFi网络")
                    .foregroundColor(.gray)
            } else {
                Picker("选择WiFi", selection: $wifiSSID) {
                    Text("请选择WiFi网络").tag(Optional<String>.none)
                    ForEach(viewModel.wifiNetworks) { network in
                        HStack {
                            Image(systemName: "wifi")
                            Text(network.ssid)
                            Spacer()
                            Text("\(network.rssi)dBm")
                                .foregroundColor(.gray)
                        }
                        .tag(Optional(network.ssid))
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
            
            // WiFi密码输入框
            if let selectedSSID = wifiSSID {
                SecureField("WiFi密码", text: $wifiPassword)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
            }
            
            // 配置按钮
            Button(action: configureWiFi) {
                Text("配置WiFi")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
    }
    
    private var actionButton: some View {
        Button(action: handleButtonTap) {
            Text(buttonText)
                .foregroundColor(.white)
                .padding()
                .background(buttonColor)
                .cornerRadius(8)
        }
    }
    
    private var statusIcon: String {
        switch viewModel.state {
        case .poweredOff: return "bolt.horizontal.circle"
        case .poweredOn: return "bolt.horizontal.circle.fill"
        case .scanning: return "arrow.triangle.2.circlepath"
        case .connected: return "wifi.circle.fill"
        case .configuring: return "gearshape.fill"
        case .configured: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
    
    private var statusColor: Color {
        switch viewModel.state {
        case .configured: return .green
        case .error: return .red
        default: return .blue
        }
    }
    
    private var statusText: String {
        switch viewModel.state {
        case .poweredOff: return "蓝牙已关闭"
        case .poweredOn: return "蓝牙已开启"
        case .scanning: return "正在扫描设备..."
        case .connected: return "设备已连接"
        case .configuring: return "正在配置WiFi..."
        case .configured: return "配置成功"
        case .error(let message): return "错误: \(message)"
        }
    }
    
    private var buttonText: String {
        switch viewModel.state {
        case .poweredOff: return "打开蓝牙"
        case .poweredOn: return "开始扫描"
        case .scanning: return "停止扫描"
        case .connected: return "配置WiFi"
        case .configuring: return "配置中..."
        case .configured: return "完成"
        case .error: return "重试"
        }
    }
    
    private var buttonColor: Color {
        switch viewModel.state {
        case .configured: return .green
        case .error: return .red
        case .configuring: return .gray
        default: return .blue
        }
    }
    
    private func handleButtonTap() {
        switch viewModel.state {
        case .poweredOff:
            if let settingsUrl = URL(string: "App-Prefs:root=Bluetooth") {
                UIApplication.shared.open(settingsUrl)
            }
        case .poweredOn:
            viewModel.startScan()
        case .scanning:
            viewModel.stopScan()
        case .connected:
            if let ssid = wifiSSID {
                viewModel.configureWiFi(ssid: ssid, password: wifiPassword)
            }
        case .configured, .error:
            viewModel.reset()
        default:
            break
        }
    }
    
    private func configureWiFi() {
        if let ssid = wifiSSID {
            viewModel.configureWiFi(ssid: ssid, password: wifiPassword)
        }
    }
    
    private func scanWiFiWithRetry() {
        print("【DEBUGView】开始扫描WiFi网络...")
        viewModel.scanWiFi()
        
        // 3秒后自动重试一次
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if viewModel.wifiNetworks.isEmpty {
                print("【DEBUGView】3秒后重试扫描WiFi网络...")
                viewModel.scanWiFi()
            }
        }
    }
}

#Preview {
    ContentView()
}
