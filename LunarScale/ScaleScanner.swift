//
//  ScaleScanner.swift
//  LunarScale
//
//  Created by Nicolas Pouvesle on 10/21/17.
//  Copyright © 2017 Nicolas Pouvesle. All rights reserved.
//

import Foundation
import CoreBluetooth

public class ScaleScanner: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    var scale: Scale?
    var manager: CBCentralManager!
    var peripheral: CBPeripheral?
    
    var hasFocus = true
    var bleStatus = false
    var state: String!
    var keepScanning = true
    let timerPauseInterval: TimeInterval = 10.0
    let timerScanInterval: TimeInterval = 2.0
    
    let SCALE_SERVICE_NAME = "PROCHBT001"
    let SCALE_SERVICE_UUID = CBUUID(string: "00001820-0000-1000-8000-00805f9b34fb")
    let SCALE_CHARACTERISTIC_UUID = CBUUID(string: "00002a80-0000-1000-8000-00805f9b34fb")
    
    public func appMovedToBackground() {
        hasFocus = false
        
        if scale != nil {
            scale = nil
            manager.cancelPeripheralConnection(peripheral!)
        }
        else {
            stopScan()
        }
    }
    
    public func appMovedToForeground() {
        if !bleStatus {
            return
        }
        
        hasFocus = true
        resumeScan()
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(withServices: [SCALE_SERVICE_UUID], options: nil)
            bleStatus = true
        case .unknown:
            bleStatus = false
        case .resetting:
            bleStatus = false
        case .unsupported:
            bleStatus = false
        case .unauthorized:
            bleStatus = false
        case .poweredOff:
            bleStatus = false
        }
    }
    
    @objc func stopScan() {
        manager.stopScan()
    }
    
    @objc func resumeScan() {
        if (!hasFocus) {
            return
        }
        
        manager.scanForPeripherals(withServices: [SCALE_SERVICE_UUID], options: nil)
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if let peripheralName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            if peripheralName == SCALE_SERVICE_NAME {
                self.peripheral = peripheral
                self.peripheral!.delegate = self
                
                stopScan()
                central.connect(self.peripheral!, options: nil)
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([SCALE_SERVICE_UUID])
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        resumeScan()
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        scale = nil
        self.peripheral = nil
        
        resumeScan()
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if error != nil {
            print("discovery error: \(String(describing: error?.localizedDescription) )")
            return
        }
        
        if let services = peripheral.services {
            for service in services where service.uuid == SCALE_SERVICE_UUID {
                peripheral.discoverCharacteristics([SCALE_CHARACTERISTIC_UUID], for: service)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if error != nil {
            print("characteristic discovery error: \(String(describing: error?.localizedDescription))")
            return
        }
        
        for characteristic in service.characteristics! where characteristic.uuid == SCALE_CHARACTERISTIC_UUID {
            scale = Scale(peripheral: peripheral, characteristic: characteristic)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid != SCALE_CHARACTERISTIC_UUID {
            return
        }
        
        scale?.processData(characteristic.value!)
    }
    
    public override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: nil)
    }
}

