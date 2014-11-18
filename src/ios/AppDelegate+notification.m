//
//  AppDelegate+notification.m
//  pushtest
//
//  Created by Robert Easterday on 10/26/12.
//
//

#import "AppDelegate+notification.h"
#import "PushPlugin.h"
#import <objc/runtime.h>

#import "ApplicationManager.h"

static char launchNotificationKey;
static bool firstPush;

@implementation AppDelegate (notification)

- (id) getCommandInstance:(NSString*)className
{
    return [self.viewController getCommandInstance:className];
}

// its dangerous to override a method from within a category.
// Instead we will use method swizzling. we set this up in the load call.
+ (void)load
{
    Method original, swizzled;
    firstPush = YES;

    original = class_getInstanceMethod(self, @selector(init));
    swizzled = class_getInstanceMethod(self, @selector(swizzled_init));
    method_exchangeImplementations(original, swizzled);
}

- (AppDelegate *)swizzled_init
{
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(createNotificationChecker:)
               name:@"UIApplicationDidFinishLaunchingNotification" object:nil];

	// This actually calls the original init method over in AppDelegate. Equivilent to calling super
	// on an overrided method, this is not recursive, although it appears that way. neat huh?
	return [self swizzled_init];
}

// This code will be called immediately after application:didFinishLaunchingWithOptions:. We need
// to process notifications in cold-start situations
- (void)createNotificationChecker:(NSNotification *)notification
{
	if (notification)
	{
		NSDictionary *launchOptions = [notification userInfo];
		if (launchOptions)
			self.launchNotification = [launchOptions objectForKey: @"UIApplicationLaunchOptionsRemoteNotificationKey"];
	}
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    ApplicationViewController *root = (ApplicationViewController*)[[ApplicationManager instance] currentRootViewController];

    for (WebViewController *controller in [root.allWebViewControllers allValues]) {
        PushPlugin *pushHandler = [controller getCommandInstance:@"PushPlugin"];
        [pushHandler didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
    }
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    ApplicationViewController *root = (ApplicationViewController*)[[ApplicationManager instance] currentRootViewController];

    for (WebViewController *controller in [root.allWebViewControllers allValues]) {
        PushPlugin *pushHandler = [controller getCommandInstance:@"PushPlugin"];
        [pushHandler didFailToRegisterForRemoteNotificationsWithError:error];
    }
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    NSLog(@"didReceiveNotification");

    // Get application state for iOS4.x+ devices, otherwise assume active
    UIApplicationState appState = UIApplicationStateActive;
    if ([application respondsToSelector:@selector(applicationState)]) {
        appState = application.applicationState;
    }

    if (appState == UIApplicationStateActive) {
        ApplicationViewController *root = (ApplicationViewController*)[[ApplicationManager instance] currentRootViewController];

        for (WebViewController *controller in [root.allWebViewControllers allValues]) {
            PushPlugin *pushHandler = [controller getCommandInstance:@"PushPlugin"];
            pushHandler.notificationMessage = userInfo;
            pushHandler.isInline = YES;
            [pushHandler notificationReceived];
        }
    } else {
        //save it for later
        self.launchNotification = userInfo;
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application {

    NSLog(@"active");

    //zero badge
    application.applicationIconBadgeNumber = 0;

    if(firstPush)
    {
        [self performSelector:@selector(callMainThread) withObject:nil afterDelay:5.0];
        firstPush=NO;
    }else{
        
        [self performSelector:@selector(callMainThread) withObject:nil];
    }
    
}


- (void)callMainThread{

    ApplicationViewController *root = (ApplicationViewController*)[[ApplicationManager instance] currentRootViewController];

    for (WebViewController *controller in [root.allWebViewControllers allValues]) {

        if (self.launchNotification) {
            PushPlugin *pushHandler = [controller getCommandInstance:@"PushPlugin"];

            pushHandler.notificationMessage = self.launchNotification;
            
            [pushHandler performSelectorOnMainThread:@selector(notificationReceived) withObject:pushHandler waitUntilDone:NO];
            pushHandler.isInline = NO;
        }
    }
    self.launchNotification = nil;
}

// The accessors use an Associative Reference since you can't define a iVar in a category
// http://developer.apple.com/library/ios/#documentation/cocoa/conceptual/objectivec/Chapters/ocAssociativeReferences.html
- (NSMutableArray *)launchNotification
{
   return objc_getAssociatedObject(self, &launchNotificationKey);
}

- (void)setLaunchNotification:(NSDictionary *)aDictionary
{
    objc_setAssociatedObject(self, &launchNotificationKey, aDictionary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)dealloc
{
    self.launchNotification	= nil; // clear the association and release the object
}

@end
