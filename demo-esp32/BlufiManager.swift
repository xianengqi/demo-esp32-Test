import CoreBluetooth
import Foundation

class BlufiManager: NSObject {
  static let shared = BlufiManager()
    
  private var blufiClient: BlufiClient?
  private var centralManager: CBCentralManager?
  private var currentPeripheral: CBPeripheral?
  private var writeCharacteristic: CBCharacteristic?
  private var notifyCharacteristic: CBCharacteristic?
    
  // 回调闭包
  var onStateUpdate: ((String) -> Void)?
  var onError: ((String) -> Void)?
  var onConnected: (() -> Void)?
  var onConfigured: (() -> Void)?
  var onDeviceFound: ((CBPeripheral, NSNumber) -> Void)?
    
  override private init() {
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
    peripheral.delegate = self // 设置代理
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
        
    // 通知发现了新设备
    onDeviceFound?(peripheral, RSSI)
  }
    
  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    print("已连接到设备: \(peripheral.name ?? "Unknown")")
        
    // 1. 先保存外设引用
    currentPeripheral = peripheral
        
    // 2. 设置外设代理
    peripheral.delegate = self
        
    // 3. 开始搜索服务
    print("【DEBUG】开始搜索服务")
    peripheral.discoverServices(nil)
        
    // 4. 创建并配置 BlufiClient
    let client = BlufiClient()
    print("【DEBUG】BlufiClient 创建完成")
        
    // 5. 设置代理并保存引用（重要：要保持强引用）
    client.blufiDelegate = self
    print("【DEBUG】设置 blufiDelegate 完成")
        
    // 6. 连接设备
    client.connect(peripheral.identifier.uuidString)
    print("【DEBUG】调用 client.connect 完成")
        
    // 7. 保存 client 引用
    blufiClient = client
        
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
}

// MARK: - BlufiDelegate

extension BlufiManager: BlufiDelegate {
  func blufi(_ client: BlufiClient!, gattPrepared status: BlufiStatusCode, service: CBService?, writeChar: CBCharacteristic?, notifyChar: CBCharacteristic?) {
    print("【DEBUG】进入 gattPrepared 回调，status: \(status)")
    if status == StatusSuccess {
      print("GATT准备完成，开始安全协商")
      client.negotiateSecurity()
    } else {
      print("GATT准备失败: \(status)")
      onError?("GATT准备失败")
    }
  }
    
  func blufi(_ client: BlufiClient!, didNegotiateSecurity status: UInt32) {
    print("【DEBUG】进入 didNegotiateSecurity 回调，status: \(status)")
    if status == 0 { // StatusSuccess = 0
      print("安全协商成功")
      onStateUpdate?("安全协商成功")
    } else {
      print("安全协商失败: \(status)")
      onError?("安全协商失败")
    }
  }
    
  func blufi(_ client: BlufiClient!, didPostConfigureParams status: UInt32) {
    print("【DEBUG】进入 didPostConfigureParams 回调，status: \(status)")
    if status == 0 { // StatusSuccess = 0
      print("WiFi配置成功")
      onConfigured?()
    } else {
      print("WiFi配置失败: \(status)")
      onError?("WiFi配置失败")
    }
  }
    
  // 可选实现的其他代理方法
  func blufi(_ client: BlufiClient!, gattNotification data: Data!, packageType: UInt8, subType: UInt8) -> Bool {
    print("收到GATT通知: packageType=\(packageType), subType=\(subType)")
    return true
  }
    
  func blufi(_ client: BlufiClient!, didReceiveError errCode: Int) {
    print("��到错误码: \(errCode)")
    onError?("收到错误码: \(errCode)")
  }
}
