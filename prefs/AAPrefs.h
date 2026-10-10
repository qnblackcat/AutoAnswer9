#import <Foundation/Foundation.h>

#define AA_DOMAIN CFSTR("com.qn.autopickup")
#define AA_PREFS_CHANGED_NOTIFICATION CFSTR("com.qn.autopickup/ReloadPrefs")

#define AA_DEFAULT_DELAY 10.0
#define AA_MAX_DELAY 30.0

typedef NS_ENUM(NSInteger, AAVideoMode) {
	AAVideoModeDontAnswer,
	AAVideoModeAudioOnly,
	AAVideoModeAnswer,
};

// empty or not a number: the default, otherwise clamped to 0...30 seconds
static inline double AANormalizedDelay(id value) {
	NSString *string = [[[value description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
		stringByReplacingOccurrencesOfString:@"," withString:@"."]; // decimal comma on some keyboards
	NSScanner *scanner = [NSScanner scannerWithString:string ?: @""];
	double delay;
	if (![scanner scanDouble:&delay] || !scanner.isAtEnd || !isfinite(delay)) return AA_DEFAULT_DELAY;
	return MIN(MAX(delay, 0), AA_MAX_DELAY);
}

// every app that can be auto answered: Settings key, display name, bundle ID for the icon
static inline NSArray<NSDictionary *> *AAApps(void) {
	return @[
		@{@"key": @"Phone", @"name": @"Telephony", @"bundleID": @"com.apple.mobilephone"},
		@{@"key": @"FaceTime", @"name": @"FaceTime", @"bundleID": @"com.apple.facetime"},
		@{@"key": @"vn.com.vng.zingalo", @"name": @"Zalo", @"bundleID": @"vn.com.vng.zingalo"},
		@{@"key": @"net.whatsapp.WhatsApp", @"name": @"WhatsApp", @"bundleID": @"net.whatsapp.WhatsApp"},
		@{@"key": @"com.facebook.Messenger", @"name": @"Messenger", @"bundleID": @"com.facebook.Messenger"},
		@{@"key": @"ph.telegra.Telegraph", @"name": @"Telegram", @"bundleID": @"ph.telegra.Telegraph"},
		@{@"key": @"com.viber", @"name": @"Viber", @"bundleID": @"com.viber"},
		@{@"key": @"org.whispersystems.signal", @"name": @"Signal", @"bundleID": @"org.whispersystems.signal"},
		@{@"key": @"jp.naver.line", @"name": @"LINE", @"bundleID": @"jp.naver.line"},
	];
}

static inline id AAGetPref(NSString *key) {
	return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, AA_DOMAIN));
}

static inline void AASetPref(NSString *key, id value) {
	CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, AA_DOMAIN);
	CFPreferencesAppSynchronize(AA_DOMAIN);
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), AA_PREFS_CHANGED_NOTIFICATION, NULL, NULL, YES);
}

// stored under the app key itself
typedef NS_ENUM(NSInteger, AAMode) {
	AAModeOff,
	AAModeEveryone,     // every call except the excluded contacts
	AAModeOnlyContacts, // only calls from the allowed contacts
};

static inline AAMode AAGetMode(NSString *appKey) {
	return (AAMode)[AAGetPref(appKey) integerValue];
}

// each mode keeps its own contact list per app, stored as [{type: number|name, value: ...}]
static inline NSString *AAContactsKey(NSString *appKey, AAMode mode) {
	return [appKey stringByAppendingString:mode == AAModeOnlyContacts ? @"-Allowed" : @"-Excluded"];
}
