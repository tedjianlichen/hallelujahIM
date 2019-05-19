#import "marisa.h"
#import <Cocoa/Cocoa.h>
#import <InputMethodKit/InputMethodKit.h>

#import "GCDWebServer.h"
#import "GCDWebServerDataRequest.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerURLEncodedFormRequest.h"

#import "Dictionary.h"
#import "Word.h"

const NSString *kConnectionName = @"Hallelujah_1_Connection";
IMKServer *server;
IMKCandidates *sharedCandidates;
marisa::Trie trie;
NSDictionary *wordsWithFrequencyAndTranslation;
NSDictionary *substitutions;
NSDictionary *pinyinDict;
NSUserDefaults *preference;

NSDictionary *deserializeJSON(NSString *path) {
    NSInputStream *inputStream = [[NSInputStream alloc] initWithFileAtPath:path];
    [inputStream open];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithStream:inputStream options:nil error:nil];

    [inputStream close];
    return dict;
}

NSDictionary *getWordsWithFrequencyAndTranslation() {
    NSDate *start = [NSDate date];
    NSMutableDictionary* words = [[NSMutableDictionary alloc] init];
    NSString *dictPath = [[NSBundle mainBundle] pathForResource:@"dictionary" ofType:@"bin"];
    NSData *data = [[NSFileManager defaultManager] contentsAtPath:dictPath];
    Dictionary* dict = [Dictionary getRootAs:data];
    NSTimeInterval timeInterval = [start timeIntervalSinceNow];
    NSLog(@"time to parse binary data: %f", timeInterval);//0.009632s very fast

    NSDate *start2 = [NSDate date];
//    Word* word = [dict entries][0];
//    NSLog(@"word key:%@, translation:%@, ipa:%@, frequency:%lld", [word key], [word translation], [word ipa], [word frequency]);
    for(Word* word in [dict entries]) {
        [words setObject: word forKey: [word key]];
    }
    NSTimeInterval timeInterval2 = [start2 timeIntervalSinceNow];
    NSLog(@"time to convert list to dict: %f", timeInterval2);//0.304043s slow

    return [words copy];
}

NSDictionary *getPinyinData() {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"cedict" ofType:@"json"];
    return deserializeJSON(path);
}

NSDictionary *getUserDefinedSubstitutions() {
    NSString *path = [NSString stringWithFormat:@"%@%@", NSHomeDirectory(), @"/.you_expand_me.json"];
    return deserializeJSON(path);
}

void initPreference() {
    preference = [NSUserDefaults standardUserDefaults];
    if ([preference objectForKey:@"showTranslation"] == nil) {
        [preference setBool:YES forKey:@"showTranslation"];
    }
}

NSDictionary *getDictionaryRepresentationOfPreference() {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    BOOL showTranslation = [preference boolForKey:@"showTranslation"];
    [dict setObject:[NSNumber numberWithBool:showTranslation] forKey:@"showTranslation"];
    return dict;
}

void startHttpServer() {
    initPreference();

    GCDWebServer *webServer = [[GCDWebServer alloc] init];
    [webServer addGETHandlerForBasePath:@"/"
                          directoryPath:[NSString stringWithFormat:@"%@/%@", [[NSBundle mainBundle] resourcePath], @"web"]
                          indexFilename:nil
                               cacheAge:3600
                     allowRangeRequests:YES];

    [webServer addHandlerForMethod:@"GET"
                              path:@"/preference"
                      requestClass:[GCDWebServerRequest class]
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
                          return [GCDWebServerDataResponse responseWithJSONObject:getDictionaryRepresentationOfPreference()];
                      }];

    [webServer addHandlerForMethod:@"POST"
                              path:@"/preference"
                      requestClass:[GCDWebServerURLEncodedFormRequest class]
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
                          NSDictionary *data = [(GCDWebServerDataRequest *)request jsonObject];
                          bool showTranslation = [[data objectForKey:@"showTranslation"] boolValue];
                          [preference setBool:showTranslation forKey:@"showTranslation"];
                          return [GCDWebServerDataResponse responseWithJSONObject:data];
                      }];
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    [options setObject:@62718 forKey:GCDWebServerOption_Port];
    [options setObject:@YES forKey:GCDWebServerOption_BindToLocalhost];

    [webServer startWithOptions:options error:nil];
}

int main(int argc, char *argv[]) {
    NSString *identifier;

    identifier = [[NSBundle mainBundle] bundleIdentifier];
    server = [[IMKServer alloc] initWithName:(NSString *)kConnectionName bundleIdentifier:[[NSBundle mainBundle] bundleIdentifier]];

    sharedCandidates = [[IMKCandidates alloc] initWithServer:server panelType:kIMKSingleColumnScrollingCandidatePanel];

    if (!sharedCandidates) {
        NSLog(@"Fatal error: Cannot initialize shared candidate panel with connection %@.", kConnectionName);
        return -1;
    }

    NSString *path = [[NSBundle mainBundle] pathForResource:@"google_227800_words" ofType:@"bin"];
    const char *path2 = [path cStringUsingEncoding:[NSString defaultCStringEncoding]];
    trie.load(path2);

    wordsWithFrequencyAndTranslation = getWordsWithFrequencyAndTranslation();
    substitutions = getUserDefinedSubstitutions();
    pinyinDict = getPinyinData();

    [[NSBundle mainBundle] loadNibNamed:@"MainMenu" owner:[NSApplication sharedApplication] topLevelObjects:nil];

    [[NSBundle mainBundle] loadNibNamed:@"PreferencesMenu" owner:[NSApplication sharedApplication] topLevelObjects:nil];

    startHttpServer();

    [[NSApplication sharedApplication] run];
    return 0;
}
