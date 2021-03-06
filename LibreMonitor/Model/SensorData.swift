//
//  SensorData
//  LibreMonitor
//
//  Created by Uwe Petersen on 26.07.16.
//  Copyright © 2016 Uwe Petersen. All rights reserved.
//

import Foundation


/// Structure for data from Freestyle Libre sensor
/// To be initialized with the bytes as read via nfc. Provides all derived data.
struct SensorData {
    
    /// Number of bytes of sensor data to be used (read only), i.e. 344 bytes (24 for header, 296 for body and 24 for footer)
    let numberOfBytes = 344 // Header and body and footer of Freestyle Libre data (i.e. 40 blocks of 8 bytes)
    /// Array of 344 bytes as read via nfc
    let bytes: [UInt8]
    /// Subarray of 24 header bytes
    let header: [UInt8]
    /// Subarray of 296 body bytes
    let body: [UInt8]
    /// Subarray of 24 footer bytes
    let footer: [UInt8]
    /// Date when data was read from sensor
    let date: Date
    /// Minutes (approx) since start of sensor
    let minutesSinceStart: Int
    /// Index on the next block of trend data that the sensor will measure and store
    let nextTrendBlock: Int
    /// Index on the next block of history data that the sensor will create from trend data and store
    let nextHistoryBlock: Int
    /// true if the header crc, stored in the first two bytes, is equal to the calculated crc
    var hasValidHeaderCRC: Bool {
        return Crc.hasValidCrc16InFirstTwoBytes(header)
    }
    /// true if the body crc, stored in the first two bytes, is equal to the calculated crc
    var hasValidBodyCRC: Bool {
        return Crc.hasValidCrc16InFirstTwoBytes(body)
    }
    /// true if the footer crc, stored in the first two bytes, is equal to the calculated crc
    var hasValidFooterCRC: Bool {
        return Crc.hasValidCrc16InFirstTwoBytes(footer)
    }
    
    /// Sensor state (ready, failure, starting etc.)
    var state: SensorState {
        switch header[4] {
        case 01:
            return SensorState.notYetStarted
        case 02:
            return SensorState.starting
        case 03:
            return SensorState.ready
        case 04:
            return SensorState.expired
        case 05:
            return SensorState.shutdown
        case 06:
            return SensorState.failure
        default:
            return SensorState.unknown
        }
    }
    
    
    init?(bytes: [UInt8], date: Date = Date()) {
        guard bytes.count == numberOfBytes else {
            return nil
        }
        self.bytes = bytes
        self.date = date
        
        let headerRange =   0..<24   //  24 bytes, i.e.  3 blocks a 8 bytes
        let bodyRange   =  24..<320  // 296 bytes, i.e. 37 blocks a 8 bytes
        let footerRange = 320..<344  //  24 bytes, i.e.  3 blocks a 8 bytes
        
        self.header = Array(bytes[headerRange])
        self.body   = Array(bytes[bodyRange])
        self.footer = Array(bytes[footerRange])
        
        self.nextTrendBlock = Int(body[2])
        self.nextHistoryBlock = Int(body[3])
        self.minutesSinceStart = Int(body[293]) << 8 + Int(body[292])
    }

    
    /// Get array of 16 trend glucose measurements. 
    /// Each array is sorted such that the most recent value is at index 0 and corresponds to the time when the sensor was read, i.e. self.date. The following measurements are each one more minute behind, i.e. -1 minute, -2 mintes, -3 minutes, ... -15 minutes.
    ///
    /// - parameter offset: offset in mg/dl that is added
    /// - parameter slope:  slope in (mg/dl)/ raw
    ///
    /// - returns: Array of Measurements
    func trendMeasurements(_ offset: Double = 0.0, slope: Double = 0.1) -> [Measurement] {
        var measurements = [Measurement]()
        
        // Trend data is stored in body from byte 4 to byte 4+96=100 in units of 6 bytes. Index on data such that most recent block is first.
        for blockIndex in 0...15 {
            
            var index = 4 + (nextTrendBlock - 1 - blockIndex) * 6 // runs backwards
            if index < 4 {
                index = index + 96 // if end of ring buffer is reached shift to beginning of ring buffer
            }
            
            let range = index..<index+6
            let measurementBytes = Array(body[range])
            let measurementDate = date.addingTimeInterval(Double(-60 * blockIndex))
            
            let measurement = Measurement(bytes: measurementBytes, slope: slope, offset: offset, date: measurementDate)
            
            measurements.append(measurement)
        }
        return measurements
    }
    
    
    /// Get array of 32 history glucose measurements. 
    /// Each array is sorted such that the most recent value is at index 0. This most recent value corresponds to -(minutesSinceStart - 3) % 15 + 3. The following measurements are each 15 more minutes behind, i.e. -15 minutes behind, -30 minutes, -45 minutes, ... .
    ///
    /// - parameter offset: offset in mg/dl that is added
    /// - parameter slope:  slope in (mg/dl)/ raw
    ///
    /// - returns: Array of Measurements
    func historyMeasurements(_ offset: Double = 0.0, slope: Double = 0.1) -> [Measurement] {
      
        let mostRecentHistoryDate = date.addingTimeInterval( 60.0 * -Double( (minutesSinceStart - 3) % 15 + 3 ) )
        var measurements = [Measurement]()
        // History data is stored in body from byte 100 to byte 100+192-1=291 in units of 6 bytes. Index on data such that most recent block is first.
        for blockIndex in 0..<32 {
            
            var index = 100 + (nextHistoryBlock - 1 - blockIndex) * 6 // runs backwards
            if index < 100 {
                index = index + 192 // if end of ring buffer is reached shift to beginning of ring buffer
            }
            
            let range = index..<index+6
            let measurementBytes = Array(body[range])
            let measurementDate = mostRecentHistoryDate.addingTimeInterval(Double(-900 * blockIndex)) // 900 = 60 * 15
            
            let measurement = Measurement(bytes: measurementBytes, slope: slope, offset: offset, date: measurementDate)
            
            measurements.append(measurement)
        }
        return measurements
    }
    

}



