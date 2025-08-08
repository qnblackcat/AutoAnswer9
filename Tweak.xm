// Tested on iOS 10.3.3
// Facetime Audio works, Facetime Video doesn't

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@interface TUCallCenter
+ (id)sharedInstance;
- (id)incomingCall;
- (void)answerCall:(id)arg1;
@end

@interface TUVideoProxyCallManager
- (void)_postVideoNotificationName:(id)arg1 forCall:(id)arg2 userInfo:(id)arg3;
@end

%hook TUCall
- (void)_handleStatusChange {
	%orig;

	id incomingCall = [[%c(TUCallCenter) sharedInstance] incomingCall];
	if (incomingCall) {

		// regular calls
		// 15 secs delay before answering FaceTime audio call
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			[[%c(TUCallCenter) sharedInstance] answerCall:incomingCall];
		});
	}
}
%end

%hook TUVideoProxyCall
- (void)updateWithCall:(id)arg1 {
	%orig;

	// facetime calls
	// 15 secs delay before answering FaceTime audio call
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[[%c(TUCallCenter) sharedInstance] answerCall:arg1];
	});
}
%end
