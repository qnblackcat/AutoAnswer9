#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "prefs/AAPrefs.h"

// build with `make AA_DEBUG=1`, then filter Console.app by "AutoPickUp" to follow what the tweak decides
#ifndef AA_DEBUG
#define AA_DEBUG 0
#endif
#define AALog(fmt, ...) do { if (AA_DEBUG) NSLog(@"[AutoPickUp] " fmt, ##__VA_ARGS__); } while (0)

#define TUCallStatusActive 1
#define TUCallStatusRinging 4 // incoming call that is still ringing
#define TUCallStatusDisconnected 6

@interface TUCallProvider : NSObject
- (NSString *)bundleIdentifier;
- (NSString *)identifier;
- (BOOL)isTelephonyProvider;
- (BOOL)isFaceTimeProvider;
@end

@interface TUHandle : NSObject
- (NSString *)value;
@end

@interface TUCall : NSObject
- (int)status;
- (BOOL)isIncoming;
- (NSString *)callUUID;
- (TUCallProvider *)provider;
- (TUHandle *)handle;
- (NSString *)displayName;
- (NSString *)callerNameFromNetwork;
- (BOOL)isVideo;
@end

@interface TUAnswerRequest : NSObject
- (instancetype)initWithCall:(TUCall *)call;
- (void)setDowngradeToAudio:(BOOL)downgradeToAudio;
@end

@interface TURoute : NSObject
- (BOOL)isSpeaker;
- (BOOL)isReceiver;
@end

@interface TURouteController : NSObject
- (NSArray<TURoute *> *)routes;
- (TURoute *)pickedRoute;
- (void)pickRoute:(TURoute *)route;
@end

extern NSString *const TUCallCenterCallStatusChangedNotification;
extern NSString *const TUCallCenterVideoCallStatusChangedNotification;

@interface TUCallCenter : NSObject
+ (instancetype)sharedInstance;
- (TUCall *)incomingCall;
- (TUCall *)incomingVideoCall;
- (void)answerCall:(TUCall *)call;
- (void)answerWithRequest:(TUAnswerRequest *)request;
- (TURouteController *)routeController;
- (NSArray<TUCall *> *)currentCalls;
- (NSArray<TUCall *> *)currentAudioAndVideoCalls;
@end

static BOOL enabled;
static BOOL volumeButtonsAnswer;
static double delay;
static AAVideoMode videoMode;
static BOOL useSpeaker;
static BOOL keepHeadphones;
static NSDictionary *prefs;
static NSMutableSet *scheduledCalls;

static void LoadPrefs(void) {
	CFPreferencesAppSynchronize(AA_DOMAIN);
	CFArrayRef keys = CFPreferencesCopyKeyList(AA_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	prefs = keys ? (__bridge_transfer NSDictionary *)CFPreferencesCopyMultiple(keys, AA_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) : @{};
	if (keys) CFRelease(keys);

	enabled = prefs[@"Enabled"] ? [prefs[@"Enabled"] boolValue] : YES;
	delay = prefs[@"Delay"] ? AANormalizedDelay(prefs[@"Delay"]) : AA_DEFAULT_DELAY;
	videoMode = (AAVideoMode)[prefs[@"VideoCalls"] integerValue];
	useSpeaker = [prefs[@"Speaker"] boolValue];
	keepHeadphones = prefs[@"KeepHeadphones"] ? [prefs[@"KeepHeadphones"] boolValue] : YES;
	volumeButtonsAnswer = [prefs[@"VolumeButtonsAnswer"] boolValue];
}

// the Settings switch key for the app that owns this call
static NSString *KeyForCall(TUCall *call) {
	TUCallProvider *provider = [call provider];
	if ([provider respondsToSelector:@selector(isTelephonyProvider)] && [provider isTelephonyProvider]) return @"Phone";
	if ([provider respondsToSelector:@selector(isFaceTimeProvider)] && [provider isFaceTimeProvider]) return @"FaceTime";

	NSString *bundleID = [provider respondsToSelector:@selector(bundleIdentifier)] ? [provider bundleIdentifier] : nil;
	if (!bundleID) bundleID = [provider identifier];

	// WhatsApp Business shares the WhatsApp switch
	if ([bundleID isEqualToString:@"net.whatsapp.WhatsAppSMB"]) return @"net.whatsapp.WhatsApp";
	return bundleID;
}

static NSString *DigitsOnly(NSString *string) {
	return [[string componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
}

// +84 901 234 567 and 0901234567 are the same number, so compare the last 9 digits
static BOOL NumbersMatch(NSString *a, NSString *b) {
	NSString *digitsA = DigitsOnly(a), *digitsB = DigitsOnly(b);
	NSUInteger length = MIN(9, MIN(digitsA.length, digitsB.length));
	if (length < 6) return NO;
	return [[digitsA substringFromIndex:digitsA.length - length] isEqualToString:[digitsB substringFromIndex:digitsB.length - length]];
}

// makes names typed in Settings comparable with what the app reports:
// - drops invisible characters like the bidi marks Zalo wraps names in ("\u202aBố\u202c")
// - uses one encoding for accents, "ố" can be one character or "o" + combining marks
// - turns any whitespace (e.g. non-breaking spaces) into single regular spaces
static NSString *CleanName(NSString *name) {
	name = [[name componentsSeparatedByCharactersInSet:[NSCharacterSet controlCharacterSet]] componentsJoinedByString:@""];
	name = [name precomposedStringWithCanonicalMapping];
	NSArray *words = [name componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	words = [words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
	return [words componentsJoinedByString:@" "];
}

// "Bố" -> "B\u1ed1", to see invisible or differently encoded characters in the log
static NSString *DebugString(NSString *string) {
	if (!string) return @"(nil)";
	NSMutableString *result = [NSMutableString string];
	for (NSUInteger i = 0; i < string.length; i++) {
		unichar c = [string characterAtIndex:i];
		if (c >= 0x20 && c < 0x7f) [result appendFormat:@"%C", c];
		else [result appendFormat:@"\\u%04x", c];
	}
	return result;
}

// case sensitive, so "Nguyễn Văn A" does not match "nguyễn văn a"
static BOOL NamesMatch(NSString *a, NSString *b) {
	a = CleanName(a);
	b = CleanName(b);
	return a.length && [a isEqualToString:b];
}

static BOOL CallMatchesContacts(TUCall *call, NSArray *contacts) {
	if (!contacts.count) return NO;

	// Zalo and most VoIP apps report a name instead of a phone number,
	// so compare against what the incoming call screen shows
	NSString *handle = [[call handle] value];
	NSMutableArray *names = [NSMutableArray array];
	if (handle) [names addObject:handle];
	if ([call respondsToSelector:@selector(callerNameFromNetwork)] && [call callerNameFromNetwork]) [names addObject:[call callerNameFromNetwork]];
	if ([call respondsToSelector:@selector(displayName)] && [call displayName]) [names addObject:[call displayName]];

	for (NSString *name in names) AALog(@"  call name: \"%@\" -> \"%@\"", DebugString(name), DebugString(CleanName(name)));

	for (NSDictionary *contact in contacts) {
		NSString *type = contact[@"type"], *value = contact[@"value"];
		if (![type isEqualToString:@"contact"]) AALog(@"  list %@: \"%@\" -> \"%@\"", type, DebugString(value), DebugString(CleanName(value)));
		if ([type isEqualToString:@"contact"]) {
			// picked from Contacts: every phone number / email of that contact
			for (NSString *contactHandle in contact[@"handles"]) {
				if (handle && (NumbersMatch(handle, contactHandle) || [handle caseInsensitiveCompare:contactHandle] == NSOrderedSame)) return YES;
			}
		} else if ([type isEqualToString:@"number"]) {
			// FaceTime handles can also be an email
			if (handle && (NumbersMatch(handle, value) || NamesMatch(handle, value))) return YES;
		} else {
			for (NSString *name in names) {
				if (NamesMatch(name, value)) return YES;
			}
		}
	}
	return NO;
}

static BOOL IsVideoCall(TUCall *call) {
	return [call respondsToSelector:@selector(isVideo)] && [call isVideo];
}

static BOOL AudioOnlyAnswerSupported(void) {
	return [%c(TUAnswerRequest) instancesRespondToSelector:@selector(setDowngradeToAudio:)]
		&& [%c(TUCallCenter) instancesRespondToSelector:@selector(answerWithRequest:)];
}

static void AnswerCall(TUCall *call) {
	TUCallCenter *center = [%c(TUCallCenter) sharedInstance];
	if (IsVideoCall(call) && videoMode == AAVideoModeAudioOnly && AudioOnlyAnswerSupported()) {
		AALog(@"answering as audio only");
		TUAnswerRequest *request = [[%c(TUAnswerRequest) alloc] initWithCall:call];
		[request setDowngradeToAudio:YES];
		[center answerWithRequest:request];
	} else {
		AALog(@"answering");
		[center answerCall:call];
	}
}

static BOOL ShouldAnswerCall(TUCall *call) {
	if (!enabled || !call || ![call isIncoming] || [call status] != TUCallStatusRinging) return NO;

	NSString *key = KeyForCall(call);
	if (!key) return NO;

	if (IsVideoCall(call)) {
		if (videoMode == AAVideoModeDontAnswer) return NO;
		// audio only needs TUAnswerRequest, leave the call ringing rather than turning on the camera
		if (videoMode == AAVideoModeAudioOnly && !AudioOnlyAnswerSupported()) return NO;
	}

	// mode per app: 0 off (default), 1 everyone except excluded, 2 only allowed contacts
	switch ([prefs[key] integerValue]) {
		case 1:
			return !CallMatchesContacts(call, prefs[[key stringByAppendingString:@"-Excluded"]]);
		case 2:
			return CallMatchesContacts(call, prefs[[key stringByAppendingString:@"-Allowed"]]);
		default:
			return NO;
	}
}

// returns NO while the call isn't connected yet / the speaker route isn't available
static BOOL PickSpeakerRoute(void) {
	TUCallCenter *center = [%c(TUCallCenter) sharedInstance];
	TURouteController *routeController = [center respondsToSelector:@selector(routeController)] ? [center routeController] : nil;
	TURoute *picked = [routeController pickedRoute];
	if ([picked isSpeaker]) return YES;

	// anything that is neither the speaker nor the earpiece is a headphone, headset or car
	if (keepHeadphones && picked && ![picked isReceiver]) return YES;

	for (TURoute *route in [routeController routes]) {
		if ([route isSpeaker]) {
			[routeController pickRoute:route];
			return YES;
		}
	}
	return NO;
}

// audio routes only show up once the answered call is connected, so retry for a few seconds
static void SwitchToSpeaker(TUCall *call, int attemptsLeft) {
	if (attemptsLeft <= 0 || [call status] == TUCallStatusDisconnected) return;
	if ([call status] == TUCallStatusActive && PickSpeakerRoute()) return;

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		SwitchToSpeaker(call, attemptsLeft - 1);
	});
}

// FaceTime video calls are tracked separately from audio calls
static TUCall *IncomingCall(void) {
	TUCallCenter *center = [%c(TUCallCenter) sharedInstance];
	TUCall *call = [center incomingCall];
	if (!call && [center respondsToSelector:@selector(incomingVideoCall)]) call = [center incomingVideoCall];
	return call;
}

static void ScheduleAnswerForIncomingCall(void) {
	TUCall *call = IncomingCall();
	if (!call) return;

	BOOL video = IsVideoCall(call);
	if (![scheduledCalls containsObject:[call callUUID]]) {
		AALog(@"incoming call: app=%@ status=%d video=%d handle=%@ name=%@", KeyForCall(call), [call status], video, [[call handle] value], [call respondsToSelector:@selector(displayName)] ? [call displayName] : nil);
	}
	if (!ShouldAnswerCall(call)) {
		NSString *key = KeyForCall(call);
		AALog(@"not answering (enabled=%d incoming=%d mode=%@ videoMode=%ld excluded=%d allowed=%d)", enabled, [call isIncoming], prefs[key], (long)videoMode,
			CallMatchesContacts(call, prefs[[key stringByAppendingString:@"-Excluded"]]), CallMatchesContacts(call, prefs[[key stringByAppendingString:@"-Allowed"]]));
		AALog(@"excluded list: %@", prefs[[key stringByAppendingString:@"-Excluded"]]);
		return;
	}

	// status changes fire many times per call, only schedule once
	NSString *identifier = [call callUUID];
	if ([scheduledCalls containsObject:identifier]) return;
	[scheduledCalls addObject:identifier];
	AALog(@"answering in %g s", delay);

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[scheduledCalls removeObject:identifier];

		// caller may have hung up, the user already answered / declined, or settings changed meanwhile
		TUCall *current = IncomingCall();
		if (![[current callUUID] isEqualToString:identifier] || !ShouldAnswerCall(current)) {
			AALog(@"call ended or settings changed, not answering");
			return;
		}

		AnswerCall(current);
		if (useSpeaker) SwitchToSpeaker(current, 10);
	});
}

// a call that is already connected or on hold, besides the ringing one
static BOOL HasOtherCall(TUCall *incoming) {
	TUCallCenter *center = [%c(TUCallCenter) sharedInstance];
	NSArray *calls = [center respondsToSelector:@selector(currentAudioAndVideoCalls)] ? [center currentAudioAndVideoCalls] : [center currentCalls];
	for (TUCall *call in calls) {
		if (![[call callUUID] isEqualToString:[incoming callUUID]] && [call status] != TUCallStatusDisconnected) return YES;
	}
	return NO;
}

// the ringing call a volume button press should answer, for any app regardless of its Auto Answer mode.
// None while already on a call, the buttons change the call volume there
static TUCall *CallToAnswerWithVolumeButton(void) {
	if (!enabled || !volumeButtonsAnswer) return nil;
	TUCall *call = IncomingCall();
	if (!call || ![call isIncoming] || [call status] != TUCallStatusRinging || HasOtherCall(call)) return nil;
	return call;
}

// index 0 volume up, 1 volume down: the press answered a call, so its release is kept from iOS too
static BOOL volumePressAnswered[2];

// returns NO when iOS shouldn't see this press / release
static BOOL HandleVolumePress(int button, id recognizer) {
	// iOS 14 may pass something other than a gesture recognizer, then every call is a new press
	UIGestureRecognizerState state = [recognizer respondsToSelector:@selector(state)] ? [(UIGestureRecognizer *)recognizer state] : UIGestureRecognizerStateBegan;

	if (state == UIGestureRecognizerStateBegan) {
		volumePressAnswered[button] = NO;
		TUCall *call = CallToAnswerWithVolumeButton();
		if (!call) return YES;

		AALog(@"volume %@ pressed, answering %@", button == 0 ? @"up" : @"down", KeyForCall(call));
		volumePressAnswered[button] = YES;
		AnswerCall(call);
		if (useSpeaker) SwitchToSpeaker(call, 10);
		return NO;
	}

	if (state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled || state == UIGestureRecognizerStateFailed) {
		BOOL answered = volumePressAnswered[button];
		volumePressAnswered[button] = NO;
		return !answered;
	}

	return !volumePressAnswered[button];
}

// a volume press while ringing normally silences the ringer, answer instead
%hook SBVolumeHardwareButton
- (void)volumeIncreasePress:(id)recognizer {
	if (HandleVolumePress(0, recognizer)) %orig;
}
- (void)volumeDecreasePress:(id)recognizer {
	if (HandleVolumePress(1, recognizer)) %orig;
}
%end

static void PrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
	LoadPrefs();
}

%ctor {
	scheduledCalls = [NSMutableSet set];
	LoadPrefs();
	%init;

	// settings apply immediately, no respring needed
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PrefsChanged, AA_PREFS_CHANGED_NOTIFICATION, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

	for (NSString *name in @[TUCallCenterCallStatusChangedNotification, TUCallCenterVideoCallStatusChangedNotification]) {
		[[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
			ScheduleAnswerForIncomingCall();
		}];
	}
}
