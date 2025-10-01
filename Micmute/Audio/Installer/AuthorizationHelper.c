#include "AuthorizationHelper.h"

#include <errno.h>
#include <stdio.h>
#include <sys/wait.h>
#include <unistd.h>

OSStatus ExecuteCommandWithPrivileges(AuthorizationRef authorization,
                                      const char *path,
                                      char * const arguments[],
                                      int *terminationStatus) {
    FILE *pipe = NULL;
    OSStatus status = AuthorizationExecuteWithPrivileges(authorization,
                                                         path,
                                                         kAuthorizationFlagExtendRights | kAuthorizationFlagInteractionAllowed,
                                                         arguments,
                                                         &pipe);
    if (status != errAuthorizationSuccess) {
        return status;
    }

    if (pipe != NULL) {
        fclose(pipe);
    }

    int waitStatus = 0;
    pid_t result;
    do {
        result = wait(&waitStatus);
    } while (result == -1 && errno == EINTR);

    if (terminationStatus != NULL) {
        if (result == -1) {
            *terminationStatus = -1;
        } else if (WIFEXITED(waitStatus)) {
            *terminationStatus = WEXITSTATUS(waitStatus);
        } else if (WIFSIGNALED(waitStatus)) {
            *terminationStatus = -WTERMSIG(waitStatus);
        } else {
            *terminationStatus = waitStatus;
        }
    }

    return errAuthorizationSuccess;
}
