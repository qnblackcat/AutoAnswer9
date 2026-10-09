#import <UIKit/UIKit.h>
#import <ContactsUI/ContactsUI.h>
#import <Preferences/PSSpecifier.h>
#import "APUAppListController.h"
#import "AAPrefs.h"

@interface APUAppListController () <CNContactPickerDelegate>
@end

@implementation APUAppListController

- (NSString *)appKey {
	return [self.specifier propertyForKey:@"appKey"];
}

- (BOOL)isFaceTime {
	return [[self appKey] isEqualToString:@"FaceTime"];
}

// only Telephony and FaceTime calls carry a number / email that can be matched to a contact
- (BOOL)supportsContactPicker {
	return [[self appKey] isEqualToString:@"Phone"] || [self isFaceTime];
}

- (AAMode)mode {
	return AAGetMode([self appKey]);
}

// the contact list of the current mode
- (NSArray *)contacts {
	return AAGetPref(AAContactsKey([self appKey], [self mode])) ?: @[];
}

- (void)setContacts:(NSArray *)contacts {
	AASetPref(AAContactsKey([self appKey], [self mode]), contacts);
	[self reloadSpecifiers];
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		self.title = self.specifier.name;
		NSMutableArray *specifiers = [NSMutableArray array];

		[specifiers addObject:[PSSpecifier groupSpecifierWithName:@"📞 Auto Answer"]];
		NSArray *modeNames = @[@"Off", @"Everyone", @"Only Specific Contacts"];
		for (NSUInteger mode = 0; mode < modeNames.count; mode++) {
			PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:modeNames[mode] target:self set:nil get:nil detail:nil cell:PSListItemCell edit:nil];
			[spec setProperty:@(mode) forKey:@"mode"];
			[specifiers addObject:spec];
		}

		AAMode mode = [self mode];
		if (mode != AAModeOff && [self isFaceTime]) {
			PSSpecifier *videoGroup = [PSSpecifier groupSpecifierWithName:@"🎥 Video Calls"];
			[videoGroup setProperty:@"Audio Only answers with your camera off." forKey:@"footerText"];
			[specifiers addObject:videoGroup];

			NSArray *videoModeNames = @[@"Don't Answer", @"Audio Only", @"Answer"];
			for (NSUInteger videoMode = 0; videoMode < videoModeNames.count; videoMode++) {
				PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:videoModeNames[videoMode] target:self set:nil get:nil detail:nil cell:PSListItemCell edit:nil];
				[spec setProperty:@(videoMode) forKey:@"videoMode"];
				[specifiers addObject:spec];
			}
		}

		if (mode != AAModeOff) {
			PSSpecifier *contactsGroup = [PSSpecifier groupSpecifierWithName:mode == AAModeOnlyContacts ? @"⭐️ Only These Contacts" : @"🙅 Except These Contacts"];
			if (![self supportsContactPicker]) {
				[contactsGroup setProperty:@"Depending on the app, Phone Number or Caller Name may not work. If one doesn't, use the other, or add both." forKey:@"footerText"];
			}
			[specifiers addObject:contactsGroup];

			NSArray *contacts = [self contacts];
			for (NSUInteger i = 0; i < contacts.count; i++) {
				PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:contacts[i][@"name"] ?: contacts[i][@"value"] target:self set:nil get:@selector(contactType:) detail:nil cell:PSTitleValueCell edit:nil];
				[spec setProperty:@(i) forKey:@"contactIndex"];
				[specifiers addObject:spec];
			}

			PSSpecifier *add = [PSSpecifier preferenceSpecifierNamed:@"➕ Add Contact..." target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
			add.buttonAction = @selector(addContact:);
			[specifiers addObject:add];
		}

		_specifiers = specifiers;
	}

	return _specifiers;
}

- (NSString *)contactType:(PSSpecifier *)specifier {
	NSDictionary *contact = [self contacts][[[specifier propertyForKey:@"contactIndex"] unsignedIntegerValue]];
	if ([contact[@"type"] isEqualToString:@"contact"]) {
		NSArray *handles = contact[@"handles"];
		return handles.count == 1 ? handles.firstObject : [NSString stringWithFormat:@"%lu numbers", (unsigned long)handles.count];
	}
	return [contact[@"type"] isEqualToString:@"number"] ? @"Phone Number" : @"Caller Name";
}

- (void)addContact:(PSSpecifier *)specifier {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Add Contact" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	if ([self supportsContactPicker]) {
		[sheet addAction:[UIAlertAction actionWithTitle:@"Choose from Contacts" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			[self presentContactPicker];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:@"Phone Number" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[self promptForContactOfType:@"number"];
	}]];
	// Telephony and FaceTime calls only carry a number / email, there is no caller name to match
	if (![self supportsContactPicker]) {
		[sheet addAction:[UIAlertAction actionWithTitle:@"Caller Name" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			[self promptForContactOfType:@"name"];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

	// iPad needs an anchor for action sheets
	UITableViewCell *cell = [self.table cellForRowAtIndexPath:[self indexPathForSpecifier:specifier]];
	sheet.popoverPresentationController.sourceView = cell ?: self.view;
	sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;

	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)promptForContactOfType:(NSString *)type {
	BOOL number = [type isEqualToString:@"number"];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:number ? @"Phone Number" : @"Caller Name"
		message:number ? nil : @"Must match the name shown on the incoming call screen exactly (case sensitive)."
		preferredStyle:UIAlertControllerStyleAlert];

	[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
		textField.placeholder = number ? @"0901 234 567" : @"Name";
		textField.keyboardType = number ? UIKeyboardTypePhonePad : UIKeyboardTypeDefault;
		textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		NSString *value = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (!value.length) return;

		[self setContacts:[[self contacts] arrayByAddingObject:@{@"type": type, @"value": value}]];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Contact picker

- (void)presentContactPicker {
	CNContactPickerViewController *picker = [CNContactPickerViewController new];
	picker.delegate = self;

	// FaceTime can also ring from an email address
	BOOL faceTime = [self isFaceTime];
	picker.displayedPropertyKeys = faceTime ? @[CNContactPhoneNumbersKey, CNContactEmailAddressesKey] : @[CNContactPhoneNumbersKey];
	picker.predicateForEnablingContact = [NSPredicate predicateWithFormat:faceTime ? @"phoneNumbers.@count > 0 OR emailAddresses.@count > 0" : @"phoneNumbers.@count > 0"];

	[self presentViewController:picker animated:YES completion:nil];
}

// picking a contact adds all of its numbers (and emails for FaceTime) as one entry
- (void)contactPicker:(CNContactPickerViewController *)picker didSelectContact:(CNContact *)contact {
	NSMutableArray *handles = [NSMutableArray array];
	for (CNLabeledValue<CNPhoneNumber *> *number in contact.phoneNumbers) [handles addObject:number.value.stringValue];
	if ([self isFaceTime]) {
		for (CNLabeledValue<NSString *> *email in contact.emailAddresses) [handles addObject:email.value];
	}
	if (!handles.count) return;

	NSString *name = [CNContactFormatter stringFromContact:contact style:CNContactFormatterStyleFullName] ?: handles.firstObject;
	[self setContacts:[[self contacts] arrayByAddingObject:@{@"type": @"contact", @"name": name, @"handles": handles}]];
}

#pragma mark - Mode checkmarks

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
	NSNumber *mode = [specifier propertyForKey:@"mode"];
	NSNumber *videoMode = [specifier propertyForKey:@"videoMode"];
	if (mode) cell.accessoryType = mode.integerValue == [self mode] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	if (videoMode) cell.accessoryType = videoMode.integerValue == [AAGetPref(@"VideoCalls") integerValue] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
	NSNumber *mode = [specifier propertyForKey:@"mode"];
	NSNumber *videoMode = [specifier propertyForKey:@"videoMode"];
	if (!mode && !videoMode) {
		[super tableView:tableView didSelectRowAtIndexPath:indexPath];
		return;
	}

	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (mode) {
		if (mode.integerValue == [self mode]) return;
		AASetPref([self appKey], mode);
	} else {
		AASetPref(@"VideoCalls", videoMode);
	}
	// move the checkmark, and show the contact list of the new mode
	[self reloadSpecifiers];
}

#pragma mark - Swipe to delete contacts

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return [[self specifierAtIndexPath:indexPath] propertyForKey:@"contactIndex"] != nil;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
	return [self tableView:tableView canEditRowAtIndexPath:indexPath] ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	NSNumber *index = [[self specifierAtIndexPath:indexPath] propertyForKey:@"contactIndex"];
	if (editingStyle != UITableViewCellEditingStyleDelete || !index) return;

	NSMutableArray *contacts = [[self contacts] mutableCopy];
	[contacts removeObjectAtIndex:index.unsignedIntegerValue];
	[self setContacts:contacts];
}

@end
