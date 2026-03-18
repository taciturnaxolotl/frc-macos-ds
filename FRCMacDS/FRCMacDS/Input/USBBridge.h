#ifndef USBBridge_h
#define USBBridge_h

#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>

// These C extern globals aren't visible to Swift, so we expose them as inline functions.

static inline CFUUIDRef USBBridge_kIOUSBDeviceUserClientTypeID(void) {
    return kIOUSBDeviceUserClientTypeID;
}

static inline CFUUIDRef USBBridge_kIOCFPlugInInterfaceID(void) {
    return kIOCFPlugInInterfaceID;
}

static inline CFUUIDRef USBBridge_kIOUSBDeviceInterfaceID(void) {
    return kIOUSBDeviceInterfaceID;
}

static inline CFUUIDRef USBBridge_kIOUSBInterfaceUserClientTypeID(void) {
    return kIOUSBInterfaceUserClientTypeID;
}

static inline CFUUIDRef USBBridge_kIOUSBInterfaceInterfaceID(void) {
    return kIOUSBInterfaceInterfaceID;
}

#endif /* USBBridge_h */
