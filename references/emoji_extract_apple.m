#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static id send_id(id target, SEL sel) {
    return ((id (*)(id, SEL))objc_msgSend)(target, sel);
}

static id send_id_id(id target, SEL sel, id arg) {
    return ((id (*)(id, SEL, id))objc_msgSend)(target, sel, arg);
}

static id send_id_integer(id target, SEL sel, NSInteger arg) {
    return ((id (*)(id, SEL, NSInteger))objc_msgSend)(target, sel, arg);
}

static NSInteger send_integer_integer(id target, SEL sel, NSInteger arg) {
    return ((NSInteger (*)(id, SEL, NSInteger))objc_msgSend)(target, sel, arg);
}

static id emf_category_for_ui_name(Class emfEmojiCategoryClass, NSString *uiName) {
    id byIdentifier = send_id_id(
        (id)emfEmojiCategoryClass,
        sel_registerName("categoryWithIdentifier:"),
        uiName
    );
    if (byIdentifier) {
        return byIdentifier;
    }

    if ([uiName isEqualToString:@"UIKeyboardEmojiCategoryPeople"]) {
        return send_id((id)emfEmojiCategoryClass, sel_registerName("PeopleEmoji"));
    }
    if ([uiName isEqualToString:@"UIKeyboardEmojiCategoryNature"]) {
        return send_id((id)emfEmojiCategoryClass, sel_registerName("NatureEmoji"));
    }
    if ([uiName isEqualToString:@"UIKeyboardEmojiCategoryFoodAndDrink"]) {
        return send_id((id)emfEmojiCategoryClass, sel_registerName("FoodAndDrinkEmoji"));
    }
    if ([uiName isEqualToString:@"UIKeyboardEmojiCategoryActivity"]) {
        return send_id((id)emfEmojiCategoryClass, sel_registerName("ActivityEmoji"));
    }
    if ([uiName isEqualToString:@"UIKeyboardEmojiCategoryTravelAndPlaces"]) {
        return send_id((id)emfEmojiCategoryClass, sel_registerName("TravelAndPlacesEmoji"));
    }
    if ([uiName isEqualToString:@"UIKeyboardEmojiCategoryObjects"]) {
        return send_id((id)emfEmojiCategoryClass, sel_registerName("ObjectsEmoji"));
    }
    if ([uiName isEqualToString:@"UIKeyboardEmojiCategorySymbols"]) {
        return send_id((id)emfEmojiCategoryClass, sel_registerName("SymbolsEmoji"));
    }
    if ([uiName isEqualToString:@"UIKeyboardEmojiCategoryFlags"]) {
        return send_id((id)emfEmojiCategoryClass, sel_registerName("FlagsEmoji"));
    }
    if ([uiName isEqualToString:@"UIKeyboardEmojiCategoryRecent"]) {
        return send_id((id)emfEmojiCategoryClass, sel_registerName("PrepopulatedEmoji"));
    }
    if ([uiName isEqualToString:@"UIKeyboardEmojiCategoryCelebration"]) {
        return send_id((id)emfEmojiCategoryClass, sel_registerName("CelebrationEmoji"));
    }
    return nil;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *locale = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"ja";

        void *h1 = dlopen("/System/Library/PrivateFrameworks/EmojiFoundation.framework/EmojiFoundation", RTLD_NOW);
        void *h2 = dlopen("/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore", RTLD_NOW);
        if (!h1 || !h2) {
            fprintf(stderr, "failed to load frameworks\n");
            return 1;
        }

        Class emfEmojiLocaleDataClass = NSClassFromString(@"EMFEmojiLocaleData");
        Class emfEmojiCategoryClass = NSClassFromString(@"EMFEmojiCategory");
        Class uiKeyboardEmojiCategoryClass = NSClassFromString(@"UIKeyboardEmojiCategory");
        if (!emfEmojiLocaleDataClass || !emfEmojiCategoryClass || !uiKeyboardEmojiCategoryClass) {
            fprintf(stderr, "required classes are unavailable\n");
            return 2;
        }

        id localeData = send_id_id(
            (id)emfEmojiLocaleDataClass,
            sel_registerName("emojiLocaleDataWithLocaleIdentifier:"),
            locale
        );
        if (!localeData) {
            fprintf(stderr, "failed to create EMFEmojiLocaleData for %s\n", locale.UTF8String);
            return 3;
        }

        NSArray<NSNumber *> *allowedIndexes = send_id((id)uiKeyboardEmojiCategoryClass, sel_registerName("allowedCategoryIndexes"));
        if (![allowedIndexes isKindOfClass:[NSArray class]]) {
            allowedIndexes = @[];
        }

        NSMutableArray<NSDictionary *> *results = [NSMutableArray array];
        for (NSNumber *idxNum in allowedIndexes) {
            NSInteger idx = idxNum.integerValue;
            NSInteger type = idx;
            NSString *uiName = send_id_integer(
                (id)uiKeyboardEmojiCategoryClass,
                sel_registerName("emojiCategoryStringForCategoryType:"),
                type
            ) ?: @"";
            NSString *displayName = send_id_integer(
                (id)uiKeyboardEmojiCategoryClass,
                sel_registerName("displayName:"),
                type
            ) ?: @"";

            id cat = emf_category_for_ui_name(emfEmojiCategoryClass, uiName);
            NSArray *tokens = cat
                ? (send_id_id(cat, sel_registerName("emojiTokensForLocaleData:"), localeData) ?: @[])
                : @[];

            NSMutableArray<NSString *> *emojis = [NSMutableArray arrayWithCapacity:[tokens count]];
            for (id token in tokens) {
                NSString *s = send_id(token, sel_registerName("string"));
                if (s.length > 0) {
                    [emojis addObject:s];
                }
            }

            NSString *identifier = cat ? (send_id(cat, sel_registerName("identifier")) ?: @"") : @"";

            NSDictionary *entry = @{
                @"allowedIndex": @(idx),
                @"categoryType": @(type),
                @"uiCategoryName": uiName,
                @"uiDisplayName": displayName,
                @"emfIdentifier": identifier,
                @"emojiCount": @(emojis.count),
                @"emojis": emojis
            };
            [results addObject:entry];
        }

        NSDictionary *payload = @{
            @"locale": locale,
            @"allowedCategoryIndexes": allowedIndexes,
            @"categories": results
        };

        NSError *err = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:(NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys) error:&err];
        if (!json) {
            fprintf(stderr, "json encode error: %s\n", err.localizedDescription.UTF8String);
            return 4;
        }

        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
    }

    return 0;
}
