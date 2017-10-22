//
//  Scale.swift
//  LunarScale
//
//  Created by Nicolas Pouvesle on 10/21/17.
//  Copyright © 2017 Nicolas Pouvesle. All rights reserved.
//

import Foundation
import CoreBluetooth

public class Scale {
    
    enum ScaleError: Error {
        case invalidLength
        case unknownEvent
    }
    
    enum Message: UInt8 {
        case MSG_SYSTEM = 0
        case MSG_TARE = 4
        case MSG_INFO = 7
        case MSG_STATUS = 8
        case MSG_IDENTIFY = 11
        case MSG_EVENT = 12
        case MSG_TIMER = 13
    }
    
    enum Event: UInt8 {
        case WEIGHT = 5
        case BATTERY = 6
        case TIMER = 7
        case KEY = 8
        case ACK = 11
    }
    
    let EVENT_WEIGHT_LEN = 6
    let EVENT_BATTERY_LEN = 1
    let EVENT_TIMER_LEN = 3
    let EVENT_KEY_LEN = 1
    let EVENT_ACK_LEN = 2
    
    enum State {
        case HEADER
        case DATA
    }
    
    struct Time {
        let minutes: UInt8
        let seconds: UInt8
        let millis: UInt8
    }
    
    enum TimerCommand: UInt8 {
        case START = 0
        case STOP
        case PAUSE
    }
    
    enum TimerState: UInt8 {
        case STOPPED = 0
        case STARTED
        case PAUSED
    }
    
    let HEADER1: UInt8 = 0xef
    let HEADER2: UInt8 = 0xdd
    
    var state = State.HEADER
    var msgType = Message(rawValue: 0)!
    var battery: UInt8 = 0
    var notificationInfoSent = false
    var lastHeartbeat: Int64 = 0
    var weight: Double?
    var time: Time?
    var hearbeatTimer: Timer?
    
    var peripheral: CBPeripheral!
    var characteristic: CBCharacteristic!
    
    func sendMessage(type: Message, payload: [UInt8]) {
        var cksum1: UInt8 = 0
        var cksum2: UInt8 = 0
        var bytes: [UInt8] = [UInt8](repeating: 0, count: 5 + payload.count)
        
        bytes[0] = HEADER1
        bytes[1] = HEADER2
        bytes[2] = type.rawValue
        
        for i in 0..<payload.count {
            bytes[i + 3] = payload[i]
            if i % 2 == 0 {
                (cksum1, _) = cksum1.addingReportingOverflow(payload[i])
            }
            else {
                (cksum2, _) = cksum2.addingReportingOverflow(payload[i])
            }
        }
        
        bytes[payload.count + 3] = cksum1
        bytes[payload.count + 4] = cksum2
        
        peripheral.writeValue(Data(bytes), for: characteristic, type: .withoutResponse)
    }
    
    func sendEvent(_ payload: [UInt8]) {
        var bytes: [UInt8] = [UInt8](repeating: 0, count: 1 + payload.count)
        
        bytes[0] = UInt8(payload.count + 1)
        
        for i in 0..<payload.count {
            bytes[i+1] = payload[i]
        }
        
        sendMessage(type: Message.MSG_EVENT, payload: bytes);
    }
    
    func getCurrentMillis() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
    
    @objc func sendHeartbeat() {
        let now: Int64 = getCurrentMillis()
        if (lastHeartbeat + 3000 > now) {
            return
        }
        
        let payload: [UInt8] = [0x02,0x00]
        sendMessage(type: Message.MSG_SYSTEM, payload: payload)
        lastHeartbeat = now
    }
    
    func sendTare() {
        let payload: [UInt8] = [0x00]
        sendMessage(type: Message.MSG_TARE, payload: payload)
    }
    
    func sendTimerCommand(_ command: TimerCommand) {
        let payload: [UInt8] = [0x00, command.rawValue]
        sendMessage(type: Message.MSG_TARE, payload: payload)
    }
    
    func sendId() {
        let payload: [UInt8] = [0x2d,0x2d,0x2d,0x2d,0x2d,0x2d,0x2d,0x2d,0x2d,0x2d,0x2d,0x2d,0x2d,0x2d,0x2d]
        sendMessage(type: Message.MSG_IDENTIFY, payload: payload)
    }
    
    // arguments are for notification frequency: x * 100ms
    func sendNotificationRequest() {
        let payload: [UInt8] = [
            0,  // weight
            1,  // weight argument
            1,  // battery
            5,  // battery argument
            2,  // timer
            5,  // timer argument
            3,  // key
            4   // setting
        ]
        
        sendEvent(payload)
        notificationInfoSent = true
    }
    
    func dump(msg: String, payload: [UInt8]) {
        print(payload.reduce(msg) { $0 + String(format: "%02X ", $1) })
    }
    
    func parseWeightEvent(_ payload: [UInt8]) throws -> Int {
        if payload.count < EVENT_WEIGHT_LEN {
            throw ScaleError.invalidLength
        }
        
        let scaleWeight = (UInt(payload[2]) << 16) + (UInt(payload[1]) << 8) + UInt(payload[0])
        var value: Double = Double(scaleWeight)
        let unit: UInt8 = payload[4]
        
        if unit == 1 {
            value /= 10
        }
        else if unit == 2 {
            value /= 100
        }
        else if unit == 3 {
            value /= 1000
        }
        else if unit == 4 {
            value /= 10000
        }
        
        if (payload[5] & 0x02) == 0x02 {
            value *= -1
        }
        
        weight = value
        print("weight: ", value);
        
        return EVENT_WEIGHT_LEN
    }
    
    func parseAckEvent(_ payload: [UInt8]) throws -> Int {
        if payload.count < EVENT_ACK_LEN {
            throw ScaleError.invalidLength
        }
        
        // ignore ack
        return EVENT_ACK_LEN
    }
    
    func parseKeyEvent(_ payload: [UInt8]) throws -> Int {
        if payload.count < EVENT_KEY_LEN {
            throw ScaleError.invalidLength
        }
        
        // ignore key event
        return EVENT_KEY_LEN
    }
    
    func parseBatteryEvent(_ payload: [UInt8]) throws -> Int {
        if payload.count < EVENT_BATTERY_LEN {
            throw ScaleError.invalidLength
        }
        
        battery = payload[0]
        
        return EVENT_BATTERY_LEN
    }
    
    func parseTimerEvent(_ payload: [UInt8]) throws -> Int {
        if payload.count < EVENT_TIMER_LEN {
            throw ScaleError.invalidLength
        }
        
        time = Time(minutes: payload[0], seconds: payload[1], millis: payload[2])
        
        return EVENT_TIMER_LEN
    }
    
    // returns last position in payload
    func parseScaleEvent(_ payload: [UInt8]) throws -> Int {
        guard let event = Event(rawValue: payload[0]) else {
            dump(msg: "Unknown event: ", payload: payload)
            throw ScaleError.unknownEvent
        }
        
        var val: Int
        var bytes: [UInt8] = []
        
        if (payload.count > 1) {
            bytes = Array(payload[1 ... payload.count-1])
        }
        
        do {
            switch(event) {
            case Event.WEIGHT:
                val = try parseWeightEvent(bytes)
                
            case Event.BATTERY:
                val = try parseBatteryEvent(bytes)
                
            case Event.TIMER:
                val = try parseTimerEvent(bytes)
                
            case Event.ACK:
                val = try parseAckEvent(bytes)
                
            case Event.KEY:
                val = try parseKeyEvent(bytes)
            }
        } catch ScaleError.invalidLength {
            dump(msg: "Invalid length (event: " + String(event.rawValue) + "): ", payload: payload)
            throw ScaleError.invalidLength
        }
        
        return val + 1
    }
    
    func parseScaleEvents(_ payload: [UInt8]) {
        var lastPos: Int = 0
        while lastPos < payload.count {
            let bytes: [UInt8] = Array(payload[lastPos ... payload.count-1])
            
            do {
                lastPos += try parseScaleEvent(bytes)
            } catch {
                return
            }
        }
    }
    
    func parseInfo(_ payload: [UInt8]) {
        battery = payload[4]
        // TODO parse other infos
    }
    
    func parseScaleData(_ data: [UInt8]) {
        switch(msgType) {
        case .MSG_INFO:
            parseInfo(data)
            sendId()
            // seems useless with latest firmware
            hearbeatTimer = Timer.scheduledTimer(timeInterval: 4, target: self, selector: #selector(sendHeartbeat), userInfo: nil, repeats: false)
            
        case .MSG_STATUS:
            if !notificationInfoSent {
                sendNotificationRequest()
            }
            
        case .MSG_EVENT:
            parseScaleEvents(data)
            
        default:
            dump(msg: "Unknown scale message: ", payload: data)
        }
    }
    
    func processData(_ data: Data) {
        if state == State.HEADER {
            if data.count != 3 {
                print("Invalid header length", data)
                return
            }
            
            if data[0] != HEADER1 || data[1] != HEADER2 {
                print("Invalid header: ", data)
                return
            }
            
            state = State.DATA
            msgType = Message(rawValue: data[2])!
        }
        else {
            
            var len: UInt8
            var offset: Int = 0
            
            if msgType == Message.MSG_STATUS || msgType == Message.MSG_EVENT || msgType == Message.MSG_INFO {
                len = data[0]
                if len == 0 {
                    len = 1
                }
                offset = 1
            }
            else {
                switch (msgType) {
                case Message.MSG_SYSTEM:
                    len = 2
                    
                default:
                    len = 0
                }
            }
            
            if data.count < len + 2 {
                print("Invalid data length", data)
            }
            else {
                parseScaleData(Array(data[offset ... (offset + Int(len) - 2)]))
            }
            
            state = State.HEADER
        }
    }
    
    init(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        self.peripheral = peripheral
        self.characteristic = characteristic
        self.peripheral.setNotifyValue(true, for: characteristic)
    }
    
    deinit {
        self.peripheral.setNotifyValue(false, for: characteristic)
        hearbeatTimer?.invalidate()
    }
}
