#import "RNEstimoteProximity.h"

#import <React/RCTLog.h>

#import <CoreLocation/CoreLocation.h>

#import "EPXCloudCredentials.h"
#import "EPXDeviceAttachment.h"
#import "EPXProximityObserver.h"
#import "EPXProximityZone.h"
#import "EPXProximityZoneContext.h"

NSString * authStringForCurrentAuthStatus() {
    switch ([CLLocationManager authorizationStatus]) {
        case kCLAuthorizationStatusNotDetermined:
            return nil;
        case kCLAuthorizationStatusRestricted:
        case kCLAuthorizationStatusDenied:
            return @"denied";
        case kCLAuthorizationStatusAuthorizedAlways:
            return @"always";
        case kCLAuthorizationStatusAuthorizedWhenInUse:
            return @"when_in_use";
    }
}

NSDictionary * contextToJSON(id<EPXProximityZoneContext> context) {
    NSDictionary *attachments = context.attachments[0].payload;
    return @{@"tag": context.tag,
             @"attachments": attachments == nil ? [NSNull null] : attachments,
             @"deviceIdentifier": context.deviceIdentifier};
}


@interface RNEstimoteProximity () <CLLocationManagerDelegate>

@property (nonatomic, strong) EPXProximityObserver *observer;

@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) RCTPromiseResolveBlock locationPermissionResolver;

@end

@implementation RNEstimoteProximity

RCT_EXPORT_MODULE()

- (dispatch_queue_t)methodQueue {
    return dispatch_get_main_queue();
}

- (NSArray<NSString *> *)supportedEvents {
    return @[@"Enter", @"Exit", @"Change"];
}

- (void)dealloc {
    [self.observer stopObservingZones];
}

RCT_EXPORT_METHOD(initialize:(NSDictionary *)config) {
    RCTLogInfo(@"Initializing with config: %@", config);

    EPXCloudCredentials *credentials = [[EPXCloudCredentials alloc] initWithAppID:config[@"appId"] appToken:config[@"appToken"]];

    self.observer = [[EPXProximityObserver alloc] initWithCredentials:credentials errorBlock:^(NSError * _Nonnull error) {
        RCTLogError(@"Proximity Observer error: %@", error);
    }];
}

RCT_EXPORT_METHOD(startObservingZones:(NSArray *)zonesJSON) {
    NSMutableArray *zones = [NSMutableArray arrayWithCapacity:zonesJSON.count];

    for (NSDictionary *zoneJSON in zonesJSON) {
        NSString *_id = zoneJSON[@"_id"];
        NSNumber *range = zoneJSON[@"range"];
        NSString *tag = zoneJSON[@"tag"];

        RCTLogInfo(@"Creating Proximity Zone _id = %@, range = %@, tag = %@", _id, range, tag);

        EPXProximityZone *zone = [[EPXProximityZone alloc]
                                  initWithRange:[EPXProximityRange customRangeWithDesiredMeanTriggerDistance:range.doubleValue]
                                  tag:tag];

        __weak __typeof(self) weakSelf = self;

        zone.onEnterAction = ^(id<EPXProximityZoneContext> context) {
            RCTLogInfo(@"onEnterAction, zoneId = %@, context = %@", _id, context);

            [weakSelf sendEventWithName:@"Enter" body:@{@"zoneId": _id,
                                                        @"context": contextToJSON(context)}];
        };

        zone.onExitAction = ^(id<EPXProximityZoneContext> context) {
            RCTLogInfo(@"onExitAction, zoneId = %@, context = %@", _id, context);

            [weakSelf sendEventWithName:@"Exit" body:@{@"zoneId": _id,
                                                       @"context": contextToJSON(context)}];
        };

        zone.onChangeAction = ^(NSSet<id<EPXProximityZoneContext>> *contexts) {
            RCTLogInfo(@"onChangeAction, zoneId = %@, contexts = %@", _id, contexts);

            NSMutableArray *convertedContexts = [NSMutableArray arrayWithCapacity:contexts.count];
            for (id<EPXProximityZoneContext> context in contexts) {
                [convertedContexts addObject:contextToJSON(context)];
            }
            [weakSelf sendEventWithName:@"Change" body:@{@"zoneId": _id,
                                                         @"contexts": convertedContexts}];
        };

        [zones addObject:zone];
    }

    [self.observer startObservingZones:zones];

    RCTLogInfo(@"Started observing for %lu zone(s)", (unsigned long) zones.count);
}

RCT_EXPORT_METHOD(stopObservingZones) {
    [self.observer stopObservingZones];

    RCTLogInfo(@"Stopped observing");
}

RCT_REMAP_METHOD(requestLocationPermission,
                 requestLocationPermissionWithResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {
    if ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusNotDetermined) {
        self.locationPermissionResolver = resolve;
        self.locationManager = [CLLocationManager new];
        self.locationManager.delegate = self;
        [self.locationManager requestAlwaysAuthorization];
    } else {
        resolve(authStringForCurrentAuthStatus());
    }
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    if (status != kCLAuthorizationStatusNotDetermined) {
        self.locationPermissionResolver(authStringForCurrentAuthStatus());
        self.locationPermissionResolver = nil;
        self.locationManager = nil;
    }
}

@end
