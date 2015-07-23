//
//  CComment.m
//  CComment
//
//  Created by flexih on 14-1-16.
//  Copyright (c) 2014 flexih. All rights reserved.
//

#import "CComment.h"
#import "Xcode.h"
#import "Config.h"

static CComment *sharedPlugin;

@interface CComment ()

@property (nonatomic, strong) NSBundle *bundle;

@end

@implementation CComment

+ (void)pluginDidLoad:(NSBundle *)plugin
{
    static id sharedPlugin = nil;
    static dispatch_once_t onceToken;
    NSString *currentApplicationName = [[NSBundle mainBundle] infoDictionary][@"CFBundleName"];
    if ([currentApplicationName isEqual:@"Xcode"]) {
        dispatch_once(&onceToken, ^{
            sharedPlugin = [[self alloc] initWithBundle:plugin];
        });
    }
}

- (id)initWithBundle:(NSBundle *)plugin
{
    if (self = [super init]) {
        self.bundle = plugin;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidFinishLaunching:)
                                                     name:NSApplicationDidFinishLaunchingNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [self setupMenuItem];
}

- (void)setupMenuItem
{
    NSMenuItem *menuItem = [[NSApp mainMenu] itemWithTitle:KEY_BINDING_MENU_NAME];
    if (menuItem) {
        [[menuItem submenu] addItem:[NSMenuItem separatorItem]];
        NSMenuItem *actionMenuItem = [[NSMenuItem alloc] initWithTitle:MENU_ITEM_TITLE action:@selector(doMenuAction) keyEquivalent:@""];
        [actionMenuItem setTarget:self];
        [actionMenuItem setKeyEquivalent:@"/"];
        [actionMenuItem setKeyEquivalentModifierMask:NSCommandKeyMask];
        [[menuItem submenu] addItem:actionMenuItem];
    }
}

- (void)doMenuAction
{
    NSTextView *textView = [Xcode textView];
    NSArray *ranges = [textView selectedRanges];
    
    NSRange range = [[ranges firstObject] rangeValue];
    NSString *commented = [self commentString:textView.textStorage.string range:&range];
    if (commented != nil) {
        [Xcode replaceCharactersInRange:range withString:commented];
    }
}

- (NSString *)commentString:(NSString *)source range:(NSRange *)prange
{
    if (prange->length == 0) {
        return [self singleLine:source range:prange];
    } else {
        return [self multiLine:source range:prange];
    }
}

- (NSString *)singleLine:(NSString *)source range:(NSRange *)prange
{
    NSRange range = *prange;
    NSUInteger length = source.length;
    NSRange preRange = {0, range.location};
    NSRange sufRange = {range.location, length - range.location};
    
    NSCharacterSet *newline = [NSCharacterSet newlineCharacterSet];
    
    sufRange = [source rangeOfCharacterFromSet:newline options:0 range:sufRange];
    preRange = [source rangeOfCharacterFromSet:newline options:NSBackwardsSearch range:preRange];
    
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
    
    if (preRange.length > 0) {
        NSUInteger location = preRange.location + preRange.length;
        
        while (location < length && [whitespace characterIsMember:[source characterAtIndex:location]]) {
            location++;
        }
        
        range.location = location;
    }
    
    if (sufRange.length > 0) {
        NSUInteger location = sufRange.location;
        
        while (location > 0 && [whitespace characterIsMember:[source characterAtIndex:location]]) {
            location--;
        }
        
        range.length = location - range.location;
        
    } else {
        sufRange.location = length;
        range.length = sufRange.location - range.location;
    }
    
    *prange = range;
    
    NSString *value = [source substringWithRange:range];
    NSInteger result = [self isCommentedSingleLine:&value];
    
    if (result > 0) {
        return value;
    } else if (result == 0 || result == -2) {
        return nil;
    } else {
        return [NSString stringWithFormat:@"//%@", value];
    }
}

- (NSString *)multiLine:(NSString *)source range:(NSRange *)prange
{
    NSRange range = *prange;
    NSString *value = [source substringWithRange:range];
    
    NSCharacterSet *whitespaceNewLine = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    
    NSUInteger i = 0, j = range.length - 1;
    
    while (j > 0 && [whitespaceNewLine characterIsMember:[value characterAtIndex:j]]) {
        j--;
    }
    
    while (i < j + 1 && [whitespaceNewLine characterIsMember:[value characterAtIndex:i]]) {
        i++;
    }
    
    range.location += i;
    range.length = j - i + 1;

    if (range.length == 0) {
        return nil;
    }
    
    if (!NSEqualRanges(range, *prange)) {
        value = [source substringWithRange:range];
        *prange = range;
    }
    
    NSInteger result = [self isCommented:&value];
    
    if (result > 0) {
        return value;
    } else if (result == 0 || result == -2) {
        return nil;
    } else {
        return [NSString stringWithFormat:@"/*\n%@\n*/", value];
    }
}

/**
 @return 
 1 comment found
 0 comment found more than once, do not handle
 -2 half comment found, like / * or * /(no blank), do no handle
 -1 no comment found
 */

- (NSInteger)isCommented:(NSString **)pvalue
{
    NSString *value = *pvalue;
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"/\\*[\\s\\S]*\\*/" options:0 error:nil];
    NSArray *results = [expression matchesInString:value options:0 range:NSMakeRange(0, value.length)];
    
    if (results.count > 0) {
        if (results.count == 1) {
            NSRange r = ((NSTextCheckingResult *)results[0]).range;
            value = [value mutableCopy];
            [(NSMutableString *)value deleteCharactersInRange:NSMakeRange(r.location + r.length - 2, 2)];
            [(NSMutableString *)value deleteCharactersInRange:NSMakeRange(r.location, 2)];
            
            /**
             *  如果收尾包含一个换行符，删除该换行符，主要目的和加注释的地方配对 \n%@\n
             */
            if ([value hasSuffix:@"\n"]) {
                
                //[(NSMutableString *)value deleteCharactersInRange:NSMakeRange(r.location, )];
                value = [value substringToIndex:value.length - 1];
            }
            if ([value hasPrefix:@"\n"]) {
                
                value = [value substringFromIndex:1];
            }
            *pvalue = [value copy];
            return 1;
        } else {
            return 0;
        }
    }
    
    if ([self isHalfCommented:value]) {
        return -2;
    }
    
    return -1;
}

- (NSInteger) isCommentedSingleLine:(NSString **) pvalue {
    
    NSString *value = *pvalue;
    if ([value hasPrefix:@"//"]) {
        
        *pvalue = [[value substringFromIndex:2] copy];
        return 1;
    }
    else {
        
        return -1;
    }
}

- (BOOL)isHalfCommented:(NSString *)value
{
    ///TODO:extend detection for /**/, /*,*/
    for (NSUInteger i = 0; i < value.length; i++) {
        if ([value characterAtIndex:i] == '*') {
            if (i > 0 && [value characterAtIndex:i - 1] == '/') {
                return YES;
            }
            
            if (i + 1 < value.length && [value characterAtIndex:i + 1] == '/') {
                return YES;
            }
        }
    }
    
    return NO;
}

@end
