#ifndef CIOHIDPrivate_h
#define CIOHIDPrivate_h

#include <CoreFoundation/CoreFoundation.h>

typedef CFTypeRef IOHIDEventSystemClientRef;
typedef CFTypeRef IOHIDServiceClientRef;
typedef CFTypeRef IOHIDEventRef;

CF_RETURNS_RETAINED IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
CF_RETURNS_RETAINED CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
CF_RETURNS_RETAINED CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef key);
CF_RETURNS_RETAINED IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

#endif
