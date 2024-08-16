//
//  RMDeviceController.m
//  Replay
//
//  Created by John Holdsworth on 21/12/2014.
//  Copyright (c) 2014 John Holdsworth. All rights reserved.
//
//  Repo: https://github.com/johnno1962/Remote
//  $Id: //depot/Remote/Sources/RemoteUI/RMDeviceController.m#17 $
//

#define REMOTE_IMPL
#import "RMDeviceController.h"
#import "RMWindowController.h"
#import "RMImageView.h"

#import <zlib.h>

#define COMPRESS_SNAPSHOT
//#define RemoteCapture REMOTE_APPNAME

@implementation  RemoteCapture(Recover)

// run length encoding used to only transmit differrences between frames
- (void)recover:(const void *)tmp against:(RemoteCapture *)prevbuff {

    register rmencoded_t expectedDiff = 0, check = 0, *data = (rmencoded_t *)tmp;
    BOOL keyframe = *data++;

    for (register rmpixel_t
         *curr = self->buffer,
         *prev = prevbuff->buffer;
         curr < self->buffend ;) {

        register rmencoded_t diff = *data++;
        unsigned count = diff & 0xff;
        diff &= 0xffffff00;

        check += *curr++ = ((keyframe ? 0 : *prev++) + diff + expectedDiff) | 0x000000ff;
        if (count) {
            if (count == 0xff)
                count = *data++;
            for (register rmpixel_t *end = MIN(curr + count, self->buffend) ; curr < end ;)
                check += *curr++ = ((keyframe ? 0 : *prev++) +
                                    diff + expectedDiff) | 0x000000ff;
        }

        expectedDiff = curr[-1] - prev[-1];
    }

    if (check != *data)
        NSLog(@"RemoteCapture: recover problem");
}

@end

@implementation RMDeviceController {
    __weak id<RMDeviceDelegate> owner;
    int clientSocket;

    RemoteCapture *currentBuffer;
}

- (instancetype)initSocket:(int)socket owner:(id<RMDeviceDelegate>)theOwner {
    if ((self = [super init])) {
        [owner = theOwner reset];
        clientSocket = socket;
        FILE *renderStream = fdopen(clientSocket, "r");
        NSLog(@"Initialising device from fd #%d", clientSocket);
        if (fread(&device.version, 1, sizeof device.version, renderStream) != sizeof device.version)
            [RMWindowController error:@"Could not read device version: %s", strerror(errno)];
        else if (device.version == MINICAP_VERSION &&
                 fread(&device.minicap, 1, sizeof device.minicap, renderStream) == sizeof device.minicap) {
            [self performSelectorInBackground:@selector(renderService:)
                    withObject:[NSValue valueWithPointer:renderStream]];
            return self;
        }
        else if (device.version && device.version > REMOTE_VERSION)
            [RMWindowController error:@"Invalid remote version: %d != %d",
                  device.version, REMOTE_VERSION];
        else if (fread(&device.remote, 1, sizeof device.remote, renderStream) != sizeof device.remote)
            [RMWindowController error:@"Could not read remote info: %s", strerror(errno)];
        else if(*(int *)device.remote.magic != REMOTE_MAGIC)
            [RMWindowController error:@"Non-matching RemoteCapture.h?"];
        else {
            int32_t keylen = 0;
            char *nokey = "", *key = nokey;

            if (device.version == REMOTE_VERSION) {
                if (fread(&keylen, 1, sizeof keylen, renderStream) != sizeof keylen)
                    [RMWindowController error:@"Could not read keylen: %s",
                     strerror(errno)];
                key = malloc(keylen+1);
                key[keylen] = '\000';
                if (!key || fread(key, 1, keylen, renderStream) != keylen)
                    [RMWindowController error:@"Could not read %d bytes of key: %s",
                     keylen, strerror(errno)];
                else {
                    for (int i=0 ; i<keylen; i++)
                        key[i] ^= REMOTE_XOR;
                }
//                NSString *source = [NSString stringWithUTF8String:key];
//                NSLog(@"%@", source);
                free(key);
            }

            [self performSelectorInBackground:@selector(renderService:)
                    withObject:[NSValue valueWithPointer:renderStream]];
            return self;
        }
    }
    close(socket);
    return self;
}

// process a connection
- (void)renderService:(NSValue *)filePtr {
    FILE *renderStream = (FILE *)filePtr.pointerValue;
    void *tmp = NULL;
    int tmpsize = 0;

    NSLog(@"renderService started %p", renderStream);
    NSArray *buffers;

    int frameno = 0, frameSize;
    struct _rmframe newFrame;
    void *framePtr;

    if (device.version == MINICAP_VERSION) {
        NSString *deviceString = [NSString stringWithFormat:
                        @"Device w:%d h:%d iscale:%g scale:%g",
                        *(uint32_t *)&device.minicap.virtualWidth,
                        *(uint32_t *)&device.minicap.virtualHeight,
                        1.0, (CGFloat)*(uint32_t *)device.minicap.realWidth /
                                  *(uint32_t *)device.minicap.virtualWidth];
        [(NSObject *)owner performSelectorOnMainThread:@selector(logAdd:)
                                            withObject:deviceString waitUntilDone:NO];
    }
    else {
        NSString *deviceString = [NSString stringWithFormat:@"<div>Hardware %s</div>", device.remote.machine];
        [(NSObject *)owner performSelectorOnMainThread:@selector(logSet:) withObject:deviceString waitUntilDone:NO];
        deviceString = [NSString stringWithFormat:@"Host: %@", [NSString stringWithUTF8String:device.remote.hostname]];
        [(NSObject *)owner performSelectorOnMainThread:@selector(logAdd:) withObject:deviceString waitUntilDone:NO];
        deviceString = [NSString stringWithFormat:@"App: %s %s", device.remote.appname, device.remote.appvers];
        [(NSObject *)owner performSelectorOnMainThread:@selector(logAdd:) withObject:deviceString waitUntilDone:NO];
    }

    if (device.version <= HYBRID_VERSION) {
        framePtr = &newFrame.length;
        frameSize = sizeof newFrame.length;
    }
    else {
        framePtr = &newFrame;
        frameSize = sizeof newFrame;
    }

    // loop through frames
    while (fread(framePtr, 1, frameSize, renderStream) == frameSize) {
        // event from device
        if (newFrame.length < 0) {
            // If minicap image length < 0 read remote touch(es) from the device
            if (device.version <= HYBRID_VERSION &&
                fread(&newFrame, 1, sizeof newFrame, renderStream) != sizeof newFrame)
                break;
            int touchCount = -newFrame.length;

            struct _rmevent event;

            BOOL isMutipleStart = newFrame.phase == RMTouchBegan && touchCount > 1;
            event.phase = isMutipleStart ? RMTouchBeganDouble : newFrame.phase;

            NSMutableString *arg = [self startEvent:newFrame.phase];

            do {
                int touchno = newFrame.length + touchCount;
                if (touchno < RMMAX_TOUCHES) {
                    event.touches[touchno].x = newFrame.x;
                    event.touches[touchno].y = newFrame.y;
                }
                [arg appendFormat:@" x:%.1f y:%.1f", newFrame.x, newFrame.y];
            } while (newFrame.length != -1 && fread(&newFrame, 1,
                            sizeof newFrame, renderStream) == sizeof newFrame);

            [owner.imageView drawTouches:&event];

            [(NSObject *)owner performSelectorOnMainThread:@selector(logAdd:)
                                    withObject:arg waitUntilDone:NO];
            continue;
        }

        if (device.version <= HYBRID_VERSION) {
            if (tmpsize < newFrame.length) {
                free(tmp);
                tmp = malloc(newFrame.length);
                tmpsize = newFrame.length;
            }
            if (fread(tmp, 1, newFrame.length, renderStream) != newFrame.length)
                break;
            NSData *imageData = [NSData dataWithBytesNoCopy:tmp length:newFrame.length
                                               freeWhenDone:NO];
            NSImage *image = [[NSImage alloc] initWithData:imageData];
            CGRect imageRect = CGRectMake(0, 0, image.size.width, image.size.height);
            [owner updateImage:[image CGImageForProposedRect:&imageRect context: nil hints: nil]];
            if (device.version == HYBRID_VERSION) {
                imageRect.size.width /= *(float *)device.remote.scale;
                imageRect.size.height /= *(float *)device.remote.scale;
            }
            if (frame.width != imageRect.size.width)
                dispatch_sync(dispatch_get_main_queue(), ^{
                    [owner resize:imageRect.size];
                });
            frame.width = imageRect.size.width;
            frame.height = imageRect.size.height;
            continue;
        }

        // resize display window/NSImageView
        if (!buffers || newFrame.imageScale != frame.imageScale ||
            newFrame.width != frame.width || newFrame.height != frame.height) {

            dispatch_sync(dispatch_get_main_queue(), ^{
                [owner resize:NSMakeSize(newFrame.width, newFrame.height)];
            });

            NSString *deviceString = [NSString stringWithFormat:
                            @"Device w:%g h:%g iscale:%g scale:%g",
                            newFrame.width, newFrame.height,
                            newFrame.imageScale, *(float *)device.remote.scale];
            [(NSObject *)owner performSelectorOnMainThread:@selector(logAdd:)
                                                withObject:deviceString waitUntilDone:NO];

            // buffer current and previous frame to only render differences
            buffers = nil;
            buffers = @[[[RemoteCapture alloc] initFrame:&newFrame],
                        [[RemoteCapture alloc] initFrame:&newFrame]];
            frameno = 0;
        }

        frame = newFrame;

        //NSLog(@"Incoming bytes from client: %u", frame.length);

        BOOL isCompressed = frame.length >= REMOTE_COMPRESSED_OFFSET;
        if (isCompressed)
            frame.length -= REMOTE_COMPRESSED_OFFSET;

        if (tmpsize < frame.length) {
            free(tmp);
            tmp = malloc(frame.length);
            tmpsize = frame.length;
        }

        [owner loading:TRUE];
        if (!frame.length ||
            fread(tmp, 1, frame.length, renderStream) != frame.length) {
            [owner loading:FALSE];
            break;
        }
        [owner loading:FALSE];

        if (isCompressed) {
            struct _rmcompress *buff = (struct _rmcompress *)tmp;
            uLong bytes = buff->bytes;
            void *buff2 = malloc(bytes);

            if (!buff || !buff2 ||
                uncompress(buff2, &bytes, buff->data, frame.length-sizeof buff->bytes) != Z_OK || bytes != buff->bytes) {
                NSLog(@"RemoteCapture: Uncompress problem");
                break;
            }

            free(tmp);
            tmp = buff2;
            tmpsize = (int)buff->bytes;
        }

        // alternate buffers
        RemoteCapture *buffer = buffers[frameno++%2];
        RemoteCapture *prevbuff = buffers[frameno%2];

        [buffer recover:tmp against:prevbuff];
        currentBuffer = buffer;

        CGImageRef imageRef = [currentBuffer cgImage];
        [owner updateImage:imageRef];
    }

    NSLog(@"renderFrames: exits");
    fclose(renderStream);
    owner.device = nil;
    free(tmp);
}

- (void)shutdown {
    close(clientSocket);
}

- (NSString *)snapshot:(RemoteCapture *)reference withFormat:(NSString *)format {
    if (!reference)
        reference = currentBuffer;

    struct _rmframe ftmp = {0.0, frame.width, frame.height, 0.5};
    RemoteCapture *btmp = [[RemoteCapture alloc] initFrame:&ftmp];
    CGImageRef img = [reference cgImage];

    CGContextScaleCTM(btmp->cg, 1., -1.);
    CGContextDrawImage(btmp->cg, CGRectMake(0., -frame.height, frame.width, frame.height), img);
    CGImageRelease(img);

    img = [btmp cgImage];
    NSMutableData *data = [NSMutableData new];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, kUTTypePNG, 1, NULL);
    CGImageDestinationAddImage(destination, img, nil);
    CGImageDestinationFinalize(destination);
    CGImageRelease(img);

    NSString *png64 = [data base64EncodedStringWithOptions:0];
    CFRelease(destination);

    NSData *out = [reference subtractAndEncode:nil];

#ifdef COMPRESS_SNAPSHOT
    struct _rmcompress *buff = malloc(sizeof buff->bytes+out.length+100);
    uLongf clen = buff->bytes = (unsigned)out.length;
    if (compress(buff->data, &clen,
                  (const Bytef *)out.bytes, buff->bytes) != Z_OK)
        NSLog(@"RemoteCapture: Compression problem");

    data = [NSMutableData dataWithBytesNoCopy:buff length:sizeof buff->bytes + clen freeWhenDone:YES];
#endif

    NSString *enc64 = [data base64EncodedStringWithOptions:0];
    return [NSString stringWithFormat:format, png64, enc64];
}

- (RemoteCapture *)recoverBuffer:(NSString *)enc64 {
    NSData *encData = [[NSData alloc] initWithBase64EncodedString:enc64 options:0];

#ifdef COMPRESS_SNAPSHOT
    struct _rmcompress *buff = (struct _rmcompress *)encData.bytes;
    uLong bytes = buff->bytes;
    void *buff2 = malloc(bytes);

    Bytef *backwardCompatibility = buff->data + sizeof(uLongf) - sizeof buff->bytes;
    if (uncompress(buff2, &bytes, buff->data, encData.length - sizeof buff->bytes) != Z_OK &&
        uncompress(buff2, &bytes, backwardCompatibility, encData.length - sizeof buff->bytes) != Z_OK)
        NSLog(@"RemoteCapture: Uncompress problem");

    encData = [NSData dataWithBytesNoCopy:buff2 length:bytes freeWhenDone:YES];
#endif

    RemoteCapture *reference = [[RemoteCapture alloc] initFrame:&frame];
    [reference recover:encData.bytes against:[[RemoteCapture alloc] initFrame:&frame]];
    return reference;
}

- (NSImage *)recoverImage:(NSString *)enc64 {
    RemoteCapture *snapshot = [self recoverBuffer:enc64];
    CGImageRef current = [currentBuffer cgImage];
    CGContextScaleCTM(snapshot->cg, 1., -1.);
    CGContextSetBlendMode(snapshot->cg, kCGBlendModeDifference);
    CGContextDrawImage(snapshot->cg, CGRectMake(0., -frame.height, frame.width, frame.height), current);
    CGImageRef img = [snapshot cgImage];
    NSImage *image = [[NSImage alloc] initWithCGImage:img size:NSMakeSize(frame.width, frame.height)];
    CGImageRelease(current);
    CGImageRelease(img);
    return image;
}

- (unsigned)differenceAgainst:(RemoteCapture *)snapshot {
    NSData *out = [currentBuffer subtractAndEncode:snapshot];
    return (unsigned)out.length-REMOTE_MINDIFF;
}

- (NSMutableString *)startEvent:(RMTouchPhase)phase {
    NSString *phaseString;
    switch (phase) {
        case RMTouchBegan: phaseString = @"Began"; break;
        case RMTouchMoved: phaseString = @"Moved"; break;
        case RMTouchStationary: phaseString = @"Stationary"; break;
        case RMTouchEnded: phaseString = @"Ended"; break;
        case RMTouchCancelled: phaseString = @"Cancelled"; break;
        case RMTouchRegionEntered: phaseString = @"Tracked"; break;
        case RMTouchRegionMoved: phaseString = @"Oved"; break;
        case RMTouchRegionExited: phaseString = @"Xited"; break;
        default: phaseString = @"Unknown";
    }
    return [NSMutableString stringWithFormat:@"%@ t:%.3f",
            phaseString, [owner timeSinceLastEvent]];
}

- (void)writeEvent:(const struct _rmevent *)event {
    [owner.imageView drawTouches:event];
    if (event && write(clientSocket, event, sizeof *event) != sizeof *event)
        NSLog(@"Remote: event write error");
}

- (void)sendEvent:(NSEvent *)theEvent phase:(RMTouchPhase)phase {
    NSPoint loc = theEvent.locationInWindow;
    float locScale = frame.height/owner.imageView.frame.size.height;
    struct _rmevent event = {
        REMOTE_NOW, phase, loc.x*locScale,
        (owner.imageView.frame.size.height-loc.y)*locScale };

    [self writeEvent:&event];

    NSMutableString *arg = [self startEvent:phase];
    [arg appendFormat:@" x:%.1f y:%.1f", event.touches[0].x, event.touches[0].y];
    [owner logAdd:arg];
}

- (void)sendText:(NSString *)text {
    const char *chars = text.UTF8String;
    size_t len = strlen(chars);
    struct _rmevent event = {
        REMOTE_NOW, RMTouchInsertText+(int)len, 0.0, 0.0};
    if (write(clientSocket, &event, sizeof event) != sizeof event ||
        write(clientSocket, chars, len) != len)
        NSLog(@"Remote: text write error");
    [owner logAdd:[NSString stringWithFormat:@"Text: %@", text]];
}

@end
