#import "exploit/bad_query.h"
#import "exploit/mcm_bridge.h"
#import "kexploit/kexploit_opa334.h"
#import "kexploit/sandbox_escape.h"
#import "kexploit/kutils.h"
#import "helpers/AppIconHelper.h"
#import "helpers/DisplayIdentity.h"
#import "helpers/Stealth.h"

// AntiDetection runtime protection
int AD_isTampered(void);
void AD_applyEarlyProtections(void);
void AD_killProcess(void);

// Stealth (21-30)
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
