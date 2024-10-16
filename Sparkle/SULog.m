//
//  SULog.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#include "SULog.h"

#include <asl.h>
#include <Availability.h>
#include <os/log.h>

#include "AppKitPrevention.h"
#import "SUOperatingSystem.h"


#include "AppKitPrevention.h"

// For converting constants to string literals using the preprocessor
#define STRINGIFY(x) #x
#define TO_STRING(x) STRINGIFY(x)

void SULog(SULogLevel level, NSString *format, ...)
{
    static aslclient client;
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;

    static os_log_t logger;
    static BOOL hasOSLogging;

    dispatch_once(&onceToken, ^{
        NSBundle *mainBundle = [NSBundle mainBundle];

        if (@available(macOS 10.12, *)) {
            hasOSLogging = YES;
        } else {
            hasOSLogging = NO;
        }

        if (hasOSLogging) {
            const char *subsystem = SPARKLE_BUNDLE_IDENTIFIER;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
            // This creates a thread-safe object
            logger = os_log_create(subsystem, "Sparkle");
#pragma clang diagnostic pop
        } else {
            uint32_t options = ASL_OPT_NO_DELAY;
            // Act the same way os_log() does; don't log to stderr if a terminal device is attached
            if (!isatty(STDERR_FILENO)) {
                options |= ASL_OPT_STDERR;
            }

            NSString *displayName = [[NSFileManager defaultManager] displayNameAtPath:mainBundle.bundlePath];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            client = asl_open([displayName stringByAppendingString:@" [Sparkle]"].UTF8String, SPARKLE_BUNDLE_IDENTIFIER, options);
#pragma clang diagnostic pop
            queue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
        }
    });

    if (!hasOSLogging && client == NULL) {
        return;
    }

    va_list ap;
    va_start(ap, format);
    NSString *logMessage = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);

    // Use os_log if available (on 10.12+)
    if (hasOSLogging) {
        // We'll make all of our messages formatted as public; just don't log sensitive information.
        // Note we don't take advantage of info like the source line number because we wrap this macro inside our own function
        // And we don't really leverage of os_log's deferred formatting processing because we format the string before passing it in
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        switch (level) {
            case SULogLevelDefault:
                // See docs for OS_LOG_TYPE_DEFAULT
                // By default, OS_LOG_TYPE_DEFAULT seems to be more noticable than OS_LOG_TYPE_INFO
                os_log(logger, "%{public}@", logMessage);
                break;
            case SULogLevelError:
                // See docs for OS_LOG_TYPE_ERROR
                os_log_error(logger, "%{public}@", logMessage);
                break;
        }
#pragma clang diagnostic pop
        return;
    }

    // Otherwise use ASL
    // Make sure we do not async, because if we async, the log may not be delivered deterministically
    // TODO: When we remove support for macOS 10.11, remove all this asl code
    dispatch_sync(queue, ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        aslmsg message = asl_new(ASL_TYPE_MSG);
#pragma clang diagnostic pop
        if (message == NULL) {
            return;
        }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if (asl_set(message, ASL_KEY_MSG, logMessage.UTF8String) != 0) {
#pragma clang diagnostic pop
            return;
        }
        
        int levelSetResult;
        switch (level) {
            case SULogLevelDefault:
                // Just use one level below the error level
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                levelSetResult = asl_set(message, ASL_KEY_LEVEL, TO_STRING(ASL_LEVEL_WARNING));
#pragma clang diagnostic pop
                break;
            case SULogLevelError:
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                levelSetResult = asl_set(message, ASL_KEY_LEVEL, TO_STRING(ASL_LEVEL_ERR));
#pragma clang diagnostic pop
                break;
        }
        if (levelSetResult != 0) {
            return;
        }
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        asl_send(client, message);
#pragma clang diagnostic pop
    });
}
