#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>
#import "APURootListController.h"
#import "APUAppListController.h"
#import "AAPrefs.h"

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)applicationIsInstalled:(NSString *)bundleID;
@end

@interface UIImage (Private)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleID format:(int)format scale:(CGFloat)scale;
@end

@implementation APURootListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];

		// Keep Headphones only matters when the speaker is used
		if (![AAGetPref(@"Speaker") boolValue]) {
			[specifiers removeObject:[self specifierForID:@"KeepHeadphones" in:specifiers]];
		} else {
			[[self specifierForID:@"SpeakerGroup" in:specifiers] setProperty:@"Switch calls answered by AutoPickUp (automatically or with the volume buttons) to the speaker. If Keep Headphones is on, calls stay on connected Bluetooth or wired headphones." forKey:@"footerText"];
		}

		[specifiers addObject:[PSSpecifier groupSpecifierWithName:@"📱 Apps"]];

		LSApplicationWorkspace *workspace = [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
		for (NSDictionary *app in AAApps()) {
			// only list apps that are installed
			if ([workspace respondsToSelector:@selector(applicationIsInstalled:)] && ![workspace applicationIsInstalled:app[@"bundleID"]]) continue;

			PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:app[@"name"] target:self set:nil get:@selector(appState:) detail:[APUAppListController class] cell:PSLinkListCell edit:nil];
			spec.identifier = app[@"key"];
			[spec setProperty:app[@"key"] forKey:@"appKey"];

			UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:app[@"bundleID"] format:0 scale:[UIScreen mainScreen].scale];
			if (icon) [spec setProperty:icon forKey:@"iconImage"];

			[specifiers addObject:spec];
		}

		PSSpecifier *sourceGroup = [PSSpecifier groupSpecifierWithName:@"💻 Source Code"];
		[sourceGroup setProperty:@"© 2026 Qn (Đạt Nguyễn)" forKey:@"footerText"];
		[specifiers addObject:sourceGroup];
		PSSpecifier *source = [PSSpecifier preferenceSpecifierNamed:@"GitHub" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
		source.buttonAction = @selector(openSourceCode:);
		[specifiers addObject:source];

		_specifiers = specifiers;
	}

	return _specifiers;
}

- (PSSpecifier *)specifierForID:(NSString *)identifier in:(NSArray *)specifiers {
	for (PSSpecifier *specifier in specifiers) {
		if ([specifier.identifier isEqualToString:identifier]) return specifier;
	}
	return nil;
}

- (void)setDelay:(id)value specifier:(PSSpecifier *)specifier {
	// save and show the value the tweak will actually use
	[self setPreferenceValue:[NSString stringWithFormat:@"%g", AANormalizedDelay(value)] specifier:specifier];

	dispatch_async(dispatch_get_main_queue(), ^{
		UITableViewCell *cell = [self.table cellForRowAtIndexPath:[self indexPathForSpecifier:specifier]];
		UITextField *textField = [cell respondsToSelector:@selector(textField)] ? [cell performSelector:@selector(textField)] : nil;
		if (!textField.isEditing) [self reloadSpecifier:specifier];
	});
}

- (void)setSpeaker:(id)value specifier:(PSSpecifier *)specifier {
	[self setPreferenceValue:value specifier:specifier];
	// show / hide Keep Headphones
	[self reloadSpecifiers];
}

- (void)openSourceCode:(PSSpecifier *)specifier {
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/qnblackcat/AutoPickUp/tree/master"] options:@{} completionHandler:nil];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	// refresh each app's mode after coming back from its page
	[self reloadSpecifiers];
}

// set the mode text ourselves, link cells don't reliably show their getter's value
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
	if ([specifier propertyForKey:@"appKey"]) cell.detailTextLabel.text = [self appState:specifier];
	return cell;
}

- (NSString *)appState:(PSSpecifier *)specifier {
	NSString *appKey = [specifier propertyForKey:@"appKey"];
	switch (AAGetMode(appKey)) {
		case AAModeEveryone:
			return @"Everyone";
		case AAModeOnlyContacts: {
			NSUInteger count = [AAGetPref(AAContactsKey(appKey, AAModeOnlyContacts)) count];
			return [NSString stringWithFormat:@"Only %lu Contact%@", (unsigned long)count, count == 1 ? @"" : @"s"];
		}
		default:
			return @"Off";
	}
}

@end
