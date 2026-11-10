#ifndef STEALTH_H
#define STEALTH_H

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void ST_applyEarlyStealth(void);
void ST_hideFromSpringBoard(void);
void ST_zeroStorageFootprint(void);
void ST_suppressPrivacyIndicators(void);
void ST_suppressLogging(void);
void ST_clearRecentAndSiri(void);
void ST_selfHideAfterExploit(void);
void ST_fullStealthPass(void);

int  ST_isDebuggerAttached(void);
int  ST_detectHooks(void);
void ST_denyAttach(void);

#ifdef __cplusplus
}
#endif

#endif
