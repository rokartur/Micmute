#ifndef AuthorizationHelper_h
#define AuthorizationHelper_h

#include <Security/Security.h>

OSStatus ExecuteCommandWithPrivileges(AuthorizationRef authorization,
                                      const char *path,
                                      char * const arguments[],
                                      int *terminationStatus);

#endif /* AuthorizationHelper_h */
