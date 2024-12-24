import CoreBluetooth
import Foundation

class BlufiManager: NSObject {
  static let shared = BlufiManager()
    
  private var blufiClient: BlufiClient?
  private var centralManager: CBCentralManager?
  private var currentPeripheral: CBPeripheral?
  private var writeCharacteristic: CBCharacteristic?
  private var notifyCharacteristic: CBCharacteristic?

  // 添加强引用
  private var retainedSelf: BlufiManager?

   // 添加 state 属性
    var state: BluetoothState = .poweredOff
    
  // 回调闭包
  var onStateUpdate: ((String) -> Void)?
  var onError: ((String) -> Void)?
  var onConnected: (() -> Void)?
  var onConfigured: (() -> Void)?
  var onDeviceFound: ((CBPeripheral, NSNumber) -> Void)?
  var onWifiScanResult: (([BlufiScanResponse]) -> Void)?
    
  override private init() {
    super.init()
    centralManager = CBCentralManager(delegate: self, queue: nil)
    retainedSelf = self
    // 在初始化时就创建 BlufiClient
    let client = BlufiClient()
    client.blufiDelegate = self
    blufiClient = client
  }

  deinit {
    print("【DEBUG】BlufiManager 被释放")
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
    print("【DEBUG】开始连接设备")
    currentPeripheral = peripheral
    peripheral.delegate = self
    
    // 直接使用已存在的 client
    if let client = blufiClient {
      client.connect(peripheral.identifier.uuidString)
      print("【DEBUG】调用 client.connect 完成")
    }
    
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
    writeCharacteristic = nil
    notifyCharacteristic = nil
  }

  func scanWiFi() {
    print("开始扫描 WiFi...")
    blufiClient?.requestDeviceScan()
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
  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
//        print("发现设备: \(peripheral.name ?? "Unknown") RSSI: \(RSSI)")
        
    // 通知发��了新设备
    onDeviceFound?(peripheral, RSSI)
  }
    
  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    print("已连接到设备: \(peripheral.name ?? "Unknown")")
        
    currentPeripheral = peripheral
    peripheral.delegate = self
    print("【DEBUG】开始搜索服务")
    peripheral.discoverServices(nil)
        
    onConnected?()
  }
    
  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    print("连接失败: \(error?.localizedDescription ?? "未错误")")
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
    print("【DEBUG】发现服务: \(error?.localizedDescription ?? "成功")")
        
    // 遍历所有服务
    guard let services = peripheral.services else { return }
    for service in services {
      print("【DEBUG】发现服务 UUID: \(service.uuid)")
      peripheral.discoverCharacteristics(nil, for: service)
    }
  }
    
  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    print("【DEBUG】发现特征: \(error?.localizedDescription ?? "成功")")
        
    // 遍历所有特征
    guard let characteristics = service.characteristics else { return }
    for characteristic in characteristics {
      print("【DEBUG】发现特征 UUID: \(characteristic.uuid)")
            
      // 根据特征 UUID 进行具体处理
      switch characteristic.uuid.uuidString {
      case "FF01":
        print("【DEBUG】找到写特征: \(characteristic.uuid)")
        // 保存写特征引用
        writeCharacteristic = characteristic
                
      case "FF02":
        print("【DEBUG】找到通知特征: \(characteristic.uuid)")
        // 订阅通知
        peripheral.setNotifyValue(true, for: characteristic)
        // 保存通知特征引用
        notifyCharacteristic = characteristic
                
      default:
        break
      }
    }
        
    // 如果两个特征都找到了
    if writeCharacteristic != nil && notifyCharacteristic != nil {
      print("【DEBUG】找到所有必要特征，等待 GATT 准备回调")
      print("【DEBUG】writeCharacteristic: \(writeCharacteristic!)")
      print("【DEBUG】notifyCharacteristic: \(notifyCharacteristic!)")
    }
  }
    
  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    print("【DEBUG】收到特征值更新: \(characteristic.uuid)")
  }
    
  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    print("【DEBUG】写入特征值: \(characteristic.uuid), 错误: \(error?.localizedDescription ?? "无")")
  }
    
  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    print("【DEBUG】通知状态更新: \(characteristic.uuid), error: \(error?.localizedDescription ?? "无")")
    if error == nil && characteristic.uuid.uuidString == "FF02" {
      print("【DEBUG】通知特征订阅成功")
    }
  }
}

// MARK: - BlufiDelegate

extension BlufiManager: BlufiDelegate {
  func blufi(_ client: BlufiClient!, gattPrepared status: BlufiStatusCode, service: CBService?, writeChar: CBCharacteristic?, notifyChar: CBCharacteristic?) {
    print("【DEBUG】进入 gattPrepared 回调")
    print("【DEBUG】进入 gattPrepared 回调，status: \(status)")
    if status == StatusSuccess {
      print("GATT准备完成，开始安全协商")
      client.negotiateSecurity()
    } else {
      print("GATT准备失败: \(status)")
      onError?("GATT准备失败")
    }
  }

  func blufi(_ client: BlufiClient!, didNegotiateSecurity status: BlufiStatusCode) {
    print("【DEBUG】安全协商结果: \(status)")
    if status == StatusSuccess {
      print("安全协商成功")
      // 可在这里开始配置 WiFi
      // 通知 UI 层可以开始配置 WiFi
            DispatchQueue.main.async { [weak self] in
                self?.onStateUpdate?("设备已连接")
            }
    } else {
      print("安全协商失败")
      onError?("安全协商失败")
    }
  }

  // 添加配网结果回调
  func blufi(_ client: BlufiClient!, didPostConfigureParams status: BlufiStatusCode) {
    print("【DEBUG】配网结果: \(status)")
    if status == StatusSuccess {
      print("配网成功")
      DispatchQueue.main.async { [weak self] in
        self?.onConfigured?()
      }
    } else {
      print("配网失败")
      onError?("配网失败")
    }
  }

  func blufi(_ client: BlufiClient!, gattNotification data: Data!, packageType: UInt8, subType: UInt8) -> Bool {
    print("收到GATT通知: packageType=\(packageType), subType=\(subType)")
    // 返回 false 让 BlufiClient 继续处理数据
    return false
  }

  func blufi(_ client: BlufiClient!, didReceiveDeviceScanResponse scanResults: [BlufiScanResponse]?, status: BlufiStatusCode) {
    if status == StatusSuccess {
        print("【DEBUG】WiFi 扫描成功")
        if let results = scanResults {
            print("【DEBUG】扫描到 \(results.count) 个WiFi网络:")
            for result in results {
                print("【DEBUG】SSID: \(result.ssid), RSSI: \(result.rssi)dBm")
            }
            DispatchQueue.main.async { [weak self] in
                self?.onWifiScanResult?(results)
            }
        }
    } else {
        print("【DEBUG】WiFi 扫描失败: \(status)")
        onError?("WiFi 扫描失败")
    }
  }
}
