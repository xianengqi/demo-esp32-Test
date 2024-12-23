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
    
    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // 开始扫描设备
    func startScan() {
        centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    // 停止扫描
    func stopScan() {
        centralManager?.stopScan()
    }
    
    // 连接设备
    func connect(peripheral: CBPeripheral) {
        currentPeripheral = peripheral
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
            onStateUpdate?("蓝牙已开启")
        case .poweredOff:
            onStateUpdate?("蓝牙已关闭")
        default:
            onError?("蓝牙状态异常")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // 创建并配置 BlufiClient
        let client = BlufiClient()
        client.blufiDelegate = self
        client.connect(peripheral.identifier.uuidString)
        blufiClient = client
        
        onConnected?()
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onError?("连接失败: \(error?.localizedDescription ?? "未知错误")")
    }
}

// MARK: - BlufiDelegate
extension BlufiManager: BlufiDelegate {
    func blufi(_ client: BlufiClient!, gattPrepared status: Int32, service: CBService!, writeChar: CBCharacteristic!, notifyChar: CBCharacteristic!) {
        if status == 0 {
            client.negotiateSecurity()
        } else {
            onError?("GATT准备失败")
        }
    }
    
    func blufi(_ client: BlufiClient!, didNegotiateSecurity status: Int32) {
        if status == 0 {
            onStateUpdate?("安全协商成功")
        } else {
            onError?("安全协商失败")
        }
    }
    
    func blufi(_ client: BlufiClient!, didPostConfigureParams status: Int32) {
        if status == 0 {
            onConfigured?()
        } else {
            onError?("WiFi配置失败")
        }
    }
} 