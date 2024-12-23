import Foundation
import CoreBluetooth

class BlufiManager: NSObject {
    static let shared = BlufiManager()
    
    private var blufiClient: BlufiClient?
    private var centralManager: CBCentralManager?
    private var currentPeripheral: CBPeripheral?
    
    // 回调闭包
    var onStateUpdate: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onConnected: (() -> Void)?
    var onConfigured: (() -> Void)?
    var onDeviceFound: ((CBPeripheral, NSNumber) -> Void)?
    
    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // 开始扫描设备
    func startScan() {
        print("开始扫描...")
        // 扫描所有可用设备，不过滤任何服务
        centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    // 停止扫描
    func stopScan() {
        print("停止扫描")
        centralManager?.stopScan()
    }
    
    // 连接设备
    func connect(peripheral: CBPeripheral) {
        currentPeripheral = peripheral
        peripheral.delegate = self  // 设置代理
        centralManager?.connect(peripheral, options: nil)
    }
    
    // 配置 WiFi
    func configureWiFi(ssid: String, password: String) {
        let params = BlufiConfigureParams()
        params.opMode = OpModeSta
        params.staSsid = ssid
        params.staPassword = password
        
        blufiClient?.configure(params)
    }
    
    // 断开连接
    func disconnect() {
        if let peripheral = currentPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        blufiClient?.close()
        blufiClient = nil
        currentPeripheral = nil
    }
}

// MARK: - CBCentralManagerDelegate
extension BlufiManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("蓝牙已开启")
            onStateUpdate?("蓝牙已开启")
        case .poweredOff:
            print("蓝牙已关闭")
            onStateUpdate?("蓝牙已关闭")
        default:
            print("蓝牙状态异常: \(central.state.rawValue)")
            onError?("蓝牙状态异常")
        }
    }
    
    // 发现外设
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
//        print("发现设备: \(peripheral.name ?? "Unknown") RSSI: \(RSSI)")
        
        // 通知发现了新设备
        onDeviceFound?(peripheral, RSSI)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("已连接到设备: \(peripheral.name ?? "Unknown")")
        
        // 创建并配置 BlufiClient
        let client = BlufiClient()
        client.blufiDelegate = self
        client.connect(peripheral.identifier.uuidString)
        blufiClient = client
        
        onConnected?()
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("连接失败: \(error?.localizedDescription ?? "未知错误")")
        onError?("连接失败: \(error?.localizedDescription ?? "未知错误")")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("设备断开连接: \(error?.localizedDescription ?? "正常断开")")
        if let error = error {
            onError?("设备断开连接: \(error.localizedDescription)")
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BlufiManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        print("发现服务: \(error?.localizedDescription ?? "成功")")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        print("发现特征: \(error?.localizedDescription ?? "成功")")
    }
}

// MARK: - BlufiDelegate
extension BlufiManager: BlufiDelegate {
    func blufi(_ client: BlufiClient!, gattPrepared status: Int32, service: CBService!, writeChar: CBCharacteristic!, notifyChar: CBCharacteristic!) {
        if status == 0 {
            print("GATT准备完成，开始安全协商")
            client.negotiateSecurity()
        } else {
            print("GATT准备失败: \(status)")
            onError?("GATT准备失败")
        }
    }
    
    func blufi(_ client: BlufiClient!, didNegotiateSecurity status: Int32) {
        if status == 0 {
            print("安全协商成功")
            onStateUpdate?("安全协商成功")
        } else {
            print("安全协商失败: \(status)")
            onError?("安全协商失败")
        }
    }
    
    func blufi(_ client: BlufiClient!, didPostConfigureParams status: Int32) {
        if status == 0 {
            print("WiFi配置成功")
            onConfigured?()
        } else {
            print("WiFi配置失败: \(status)")
            onError?("WiFi配置失败")
        }
    }
} 
