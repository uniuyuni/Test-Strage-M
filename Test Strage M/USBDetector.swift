//
//  USBDetector.swift
//  Test Strage M
//
//  Created by うに on 2020/08/27.
//  Copyright © 2020 うに. All rights reserved.
//

import Foundation
import IOKit
import IOKit.usb

public protocol USBDetectorDelegate: NSObjectProtocol {
    func deviceAdded(_ device: io_object_t)
    func deviceRemoved(_ device: io_object_t)
}

public class USBDetector {
    public weak var delegate: USBDetectorDelegate?
    private let notificationPort = IONotificationPortCreate(kIOMasterPortDefault)
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    public func start() {
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)
        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()

        let runLoop = IONotificationPortGetRunLoopSource(notificationPort)!.takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoop, CFRunLoopMode.defaultMode)

        let addedCallback: IOServiceMatchingCallback = { (pointer, iterator) in
            let detector = Unmanaged<USBDetector>.fromOpaque(pointer!).takeUnretainedValue()
            detector.delegate?.deviceAdded(iterator)
            while case let device = IOIteratorNext(iterator), device != IO_OBJECT_NULL {
                IOObjectRelease(device)
            }
        }

        IOServiceAddMatchingNotification(notificationPort,
                                         kIOMatchedNotification,
                                         matchingDict,
                                         addedCallback,
                                         opaqueSelf,
                                         &addedIterator)

        while case let device = IOIteratorNext(addedIterator), device != IO_OBJECT_NULL {
            IOObjectRelease(device)
        }

        let removedCallback: IOServiceMatchingCallback = { (pointer, iterator) in
            let watcher = Unmanaged<USBDetector>.fromOpaque(pointer!).takeUnretainedValue()
            watcher.delegate?.deviceRemoved(iterator)
            while case let device = IOIteratorNext(iterator), device != IO_OBJECT_NULL {
                IOObjectRelease(device)
            }
        }

        IOServiceAddMatchingNotification(notificationPort,
                                         kIOTerminatedNotification,
                                         matchingDict,
                                         removedCallback,
                                         opaqueSelf,
                                         &removedIterator)

        while case let device = IOIteratorNext(removedIterator), device != IO_OBJECT_NULL {
            IOObjectRelease(device)
        }
    }

    deinit {
        Swift.print("deinit")
        IOObjectRelease(addedIterator)
        IOObjectRelease(removedIterator)
        IONotificationPortDestroy(notificationPort)
    }

}
