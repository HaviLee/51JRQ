//
//  AppDelegate.m
//  51JRQ
//
//  Created by HaviLee on 2017/2/23.
//  Copyright © 2017年 HaviLee. All rights reserved.
//

#import "AppDelegate.h"
#import "HiInitData.h"
#import "HiThirdPartService.h"
#import "AppDelegate+EaseMob.h"
#import "ChatMessageHelper.h"
@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    [self initWithApplication:application launchingWithOptions:launchOptions];
    #pragma mark 设置tabbar
    _tabBarControllerConfig = [[CYLTabBarControllerConfig alloc] init];
    self.window.rootViewController = _tabBarControllerConfig.tabBarController;
    self.window.backgroundColor = [UIColor whiteColor];
    #pragma mark 测试数据
    [[EMClient sharedClient]loginWithUsername:@"liwe" password:@"123456" completion:^(NSString *aUsername, EMError *aError) {
        if (!aError) {
            DeBugLog(@"登录成功");
                //设置是否自动登录
            [[EMClient sharedClient].options setIsAutoLogin:YES];
                //获取数据库中数据
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [[EMClient sharedClient] migrateDatabaseToLatestSDK];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[ChatMessageHelper shareHelper] asyncGroupFromServer];
                    [[ChatMessageHelper shareHelper] asyncConversationFromDB];
                    [[ChatMessageHelper shareHelper] asyncPushOptions];
                        //发送自动登陆状态通知
                    [[NSNotificationCenter defaultCenter] postNotificationName:KNOTIFICATION_LOGINCHANGE object:@([[EMClient sharedClient] isLoggedIn])];
                });
            });
        }else{
            [EMAlertView showAlertWithTitle:@"登录失败" message:@"充实" completionBlock:nil cancelButtonTitle:nil otherButtonTitles:nil];
        }
    }];
    [self.window makeKeyAndVisible];
    return YES;
}


- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
}


- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    [[EMClient sharedClient] applicationDidEnterBackground:application];
}


- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    [[EMClient sharedClient] applicationWillEnterForeground:application];
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}


- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    // Saves changes in the application's managed object context before the application terminates.
    [self saveContext];
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken{
    [[EMClient sharedClient] bindDeviceToken:deviceToken];
}


#pragma mark - Core Data stack

@synthesize persistentContainer = _persistentContainer;

- (NSPersistentContainer *)persistentContainer {
    // The persistent container for the application. This implementation creates and returns a container, having loaded the store for the application to it.
    @synchronized (self) {
        if (_persistentContainer == nil) {
            _persistentContainer = [[NSPersistentContainer alloc] initWithName:@"_1JRQ"];
            [_persistentContainer loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *storeDescription, NSError *error) {
                if (error != nil) {
                    // Replace this implementation with code to handle the error appropriately.
                    // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                    
                    /*
                     Typical reasons for an error here include:
                     * The parent directory does not exist, cannot be created, or disallows writing.
                     * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                     * The device is out of space.
                     * The store could not be migrated to the current model version.
                     Check the error message to determine what the actual problem was.
                    */
                    NSLog(@"Unresolved error %@, %@", error, error.userInfo);
                    abort();
                }
            }];
        }
    }
    
    return _persistentContainer;
}

#pragma mark - Core Data Saving support

- (void)saveContext {
    NSManagedObjectContext *context = self.persistentContainer.viewContext;
    NSError *error = nil;
    if ([context hasChanges] && ![context save:&error]) {
        // Replace this implementation with code to handle the error appropriately.
        // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
        NSLog(@"Unresolved error %@, %@", error, error.userInfo);
        abort();
    }
}

@end
