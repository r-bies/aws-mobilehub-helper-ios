//
//  AWSFacebookSignInProvider.m
//
// Copyright 2016 Amazon.com, Inc. or its affiliates (Amazon). All Rights Reserved.
//
// Code generated by AWS Mobile Hub. Amazon gives unlimited permission to
// copy, distribute and modify it.
//
#import "AWSFacebookSignInProvider.h"
#import "AWSIdentityManager.h"
#import <FBSDKCoreKit/FBSDKCoreKit.h>
#import <FBSDKLoginKit/FBSDKLoginKit.h>

NSString *const AWSFacebookSignInProviderKey = @"Facebook";
static NSString *const AWSFacebookSignInProviderUserNameKey = @"Facebook.userName";
static NSString *const AWSFacebookSignInProviderImageURLKey = @"Facebook.imageURL";
static NSTimeInterval const AWSFacebookSignInProviderTokenRefreshBuffer = 10 * 60;

typedef void (^AWSIdentityManagerCompletionBlock)(id result, NSError *error);

@interface AWSIdentityManager()

- (void)completeLogin;

@end

@interface AWSFacebookSignInProvider()

@property (strong, nonatomic) FBSDKLoginManager *facebookLogin;

@property (strong, nonatomic) NSString *userName;
@property (strong, nonatomic) NSURL *imageURL;
@property (assign, nonatomic) FBSDKLoginBehavior savedLoginBehavior;
@property (strong, nonatomic) NSArray *requestedPermissions;
@property (strong, nonatomic) UIViewController *signInViewController;
@property (atomic, copy) AWSIdentityManagerCompletionBlock completionHandler;

@end

@implementation AWSFacebookSignInProvider

+ (instancetype)sharedInstance {
    static AWSFacebookSignInProvider *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[AWSFacebookSignInProvider alloc] init];
    });
    
    return _sharedInstance;
}

- (instancetype)init {
    Class fbSDKLoginManager = NSClassFromString(@"FBSDKLoginManager");
    if (fbSDKLoginManager) {
        if (self = [super init]) {
            _requestedPermissions = nil;
            _signInViewController = nil;
            if (NSClassFromString(@"SFSafariViewController")) {
                _savedLoginBehavior = FBSDKLoginBehaviorNative;
            } else {
                _savedLoginBehavior = FBSDKLoginBehaviorWeb;
            }
            return self;
        }
    }
    return nil;
}

- (void) createFBSDKLoginManager {
    self.facebookLogin = [FBSDKLoginManager new];
    self.facebookLogin.loginBehavior = self.savedLoginBehavior;
}

#pragma mark - MobileHub user interface

- (void)setLoginBehavior:(NSUInteger)loginBehavior {
    // FBSDKLoginBehavior enum values 0 thru 3
    // FBSDK v4.13.1
    if (loginBehavior > 3) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@", @"Failed to set Facebook login behavior with provided login behavior."];
        return;
    }
    
    if (self.facebookLogin) {
        self.facebookLogin.loginBehavior = loginBehavior;
    } else {
        self.savedLoginBehavior = loginBehavior;
    }
}

- (void)setPermissions:(NSArray *)requestedPermissions {
    self.requestedPermissions = requestedPermissions;
}

- (void)setViewControllerForFacebookSignIn:(UIViewController *)signInViewController {
    self.signInViewController = signInViewController;
}

#pragma mark - AWSIdentityProvider

- (NSString *)identityProviderName {
    return AWSIdentityProviderFacebook;
}

- (AWSTask<NSString *> *)token {
    FBSDKAccessToken *token = [FBSDKAccessToken currentAccessToken];
    NSString *tokenString = token.tokenString;
    NSDate *idTokenExpirationDate = token.expirationDate;
    
    if (tokenString
        // If the cached token expires within 10 min, tries refreshing a token.
        && [idTokenExpirationDate compare:[NSDate dateWithTimeIntervalSinceNow:AWSFacebookSignInProviderTokenRefreshBuffer]] == NSOrderedDescending) {
        return [AWSTask taskWithResult:tokenString];
    }
    
    AWSTaskCompletionSource *taskCompletionSource = [AWSTaskCompletionSource taskCompletionSource];
    [FBSDKLoginManager renewSystemCredentials:^(ACAccountCredentialRenewResult result, NSError *error) {
        if (result == ACAccountCredentialRenewResultRenewed) {
            FBSDKAccessToken *token = [FBSDKAccessToken currentAccessToken];
            NSString *tokenString = token.tokenString;
            taskCompletionSource.result = tokenString;
        } else {
            taskCompletionSource.error = error;
        }
    }];
    return taskCompletionSource.task;
}

#pragma mark -

- (BOOL)isLoggedIn {
    BOOL loggedIn = [FBSDKAccessToken currentAccessToken] != nil;
    return [self isCachedLoginFlagSet] && loggedIn;
}

- (NSString *)userName {
    return [[NSUserDefaults standardUserDefaults] objectForKey:AWSFacebookSignInProviderUserNameKey];
}

- (void)setUserName:(NSString *)userName {
    [[NSUserDefaults standardUserDefaults] setObject:userName
                                              forKey:AWSFacebookSignInProviderUserNameKey];
}

- (NSURL *)imageURL {
    return [NSURL URLWithString:[[NSUserDefaults standardUserDefaults] objectForKey:AWSFacebookSignInProviderImageURLKey]];
}

- (void)setImageURL:(NSURL *)imageURL {
    [[NSUserDefaults standardUserDefaults] setObject:imageURL.absoluteString
                                              forKey:AWSFacebookSignInProviderImageURLKey];
}

- (void)setCachedLoginFlag {
    [[NSUserDefaults standardUserDefaults] setObject:@"YES"
                                              forKey:AWSFacebookSignInProviderKey];
}

- (BOOL)isCachedLoginFlagSet {
    return [[NSUserDefaults standardUserDefaults] objectForKey:AWSFacebookSignInProviderKey] != nil;
}

- (void)clearCachedLoginFlag {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:AWSFacebookSignInProviderKey];
}

- (void)clearUserName {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:AWSFacebookSignInProviderUserNameKey];
}

- (void)clearImageURL {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:AWSFacebookSignInProviderImageURLKey];
}

- (void)reloadSession {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:AWSFacebookSignInProviderKey]
        && [FBSDKAccessToken currentAccessToken]) {
        [FBSDKAccessToken refreshCurrentAccessToken:^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
            if (error) {
                AWSLogError(@"'refreshCurrentAccessToken' failed: %@", error);
            } else {
                [self completeLogin];
            }
        }];
    }
}

- (void)completeLogin {
    [self setCachedLoginFlag];
    [[AWSIdentityManager defaultIdentityManager] completeLogin];
    
    FBSDKGraphRequest *requestForImageUrl = [[FBSDKGraphRequest alloc] initWithGraphPath:@"me"
                                                                              parameters:@{@"fields" : @"picture.type(large)"}];
    [requestForImageUrl startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection,
                                                     NSDictionary *result,
                                                     NSError *queryError) {
        self.imageURL = [NSURL URLWithString:result[@"picture"][@"data"][@"url"]];
    }];
    
    FBSDKGraphRequest *requestForName = [[FBSDKGraphRequest alloc] initWithGraphPath:@"me"
                                                                          parameters:nil];
    [requestForName startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection,
                                                 NSDictionary *result,
                                                 NSError *queryError) {
        self.userName = result[@"name"];
    }];
}

- (void)login:(AWSIdentityManagerCompletionBlock) completionHandler {
    self.completionHandler = completionHandler;
    
    if ([FBSDKAccessToken currentAccessToken]) {
        [self completeLogin];
        return;
    }
    
    if (!self.facebookLogin)
        [self createFBSDKLoginManager];
    
    [self.facebookLogin logInWithReadPermissions:self.requestedPermissions
                              fromViewController:self.signInViewController
                                         handler:^(FBSDKLoginManagerLoginResult *result, NSError *error) {
                                             if (error) {
                                                 self.completionHandler(result, error);
                                             } else if (result.isCancelled) {
                                                 // Login canceled, allow completionhandler to know about it
                                                 NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
                                                 userInfo[@"message"] = @"User Cancelled Login";
                                                 NSError *resultError = [NSError errorWithDomain:FBSDKLoginErrorDomain code:FBSDKLoginUnknownErrorCode userInfo:userInfo];
                                                 self.completionHandler(result,resultError);
                                             } else {
                                                 [self completeLogin];
                                             }
                                         }];
}

- (void)clearLoginInformation {
    [self clearCachedLoginFlag];
    [self clearUserName];
    [self clearImageURL];
}

- (void)logout {
    
    if (!self.facebookLogin) {
        [self createFBSDKLoginManager];
    }
    [self clearLoginInformation];
    [self.facebookLogin logOut];
}

- (BOOL)interceptApplication:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    return [[FBSDKApplicationDelegate sharedInstance] application:application
                                    didFinishLaunchingWithOptions:launchOptions];
}

- (BOOL)interceptApplication:(UIApplication *)application
                     openURL:(NSURL *)url
           sourceApplication:(NSString *)sourceApplication
                  annotation:(id)annotation {
    if ([[FBSDKApplicationDelegate sharedInstance] application:application
                                                       openURL:url
                                             sourceApplication:sourceApplication
                                                    annotation:annotation]) {
        return YES;
    }
    
    return NO;
}

@end
