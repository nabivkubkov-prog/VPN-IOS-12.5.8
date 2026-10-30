#include <errno.h>
#include <stdatomic.h>
#include <string.h>
#include <os/log.h>
#include <hev-logger.h>
#include <hev-socks5-logger.h>

// Override the archive's file loggers. Only fixed stage names and errno leave
// this logger; HEV format arguments can contain endpoints or auth credentials.
// Info-level handshake failures were previously invisible with log-file:null.
static atomic_uint emitted[12];
static _Atomic(const char *) last_stage = "none";
static atomic_int last_errno;

const char *incy_hev_failure_stage(void) { return atomic_load(&last_stage); }
int incy_hev_failure_errno(void) { return atomic_load(&last_errno); }

static void record_failure(int level, const char *format) {
    if (level < HEV_LOGGER_INFO || !format) return;
    int error = errno;
    const char *stage = "packet-engine";
    unsigned int index = 11;
    if (strstr(format, "client resolve")) { stage = "loopback-resolve"; index = 0; }
    else if (strstr(format, "client socket")) { stage = "loopback-socket"; index = 1; }
    else if (strstr(format, "client bind")) { stage = "loopback-bind"; index = 2; }
    else if (strstr(format, "client connect")) { stage = "loopback-connect"; index = 3; }
    else if (strstr(format, "client write auth")) { stage = "socks-write-auth"; index = 4; }
    else if (strstr(format, "client read auth") || strstr(format, "client auth.")) { stage = "socks-read-auth"; index = 5; }
    else if (strstr(format, "client write request")) { stage = "socks-write-request"; index = 6; }
    else if (strstr(format, "client read response") || strstr(format, "client res.")) { stage = "socks-read-response"; index = 7; }
    else if (strstr(format, "client read addr") || strstr(format, "client set upstream")) { stage = "socks-read-address"; index = 8; }
    else if (strstr(format, "io timeout")) { stage = "socks-timeout"; index = 9; }
    else if (strstr(format, "session handshake")) { stage = "socks-handshake"; index = 10; }
    if (index < 10) { atomic_store(&last_stage, stage); atomic_store(&last_errno, error); }
    if (atomic_fetch_add(&emitted[index], 1) < 4) {
        os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT,
                         "INCY hev-stage=%{public}s errno=%d", stage, error);
    }
}

int hev_logger_init(HevLoggerLevel level, const char *path) {
    (void)level; (void)path;
    for (unsigned int i = 0; i < 12; ++i) atomic_store(&emitted[i], 0);
    atomic_store(&last_stage, "none"); atomic_store(&last_errno, 0);
    return 0;
}
void hev_logger_fini(void) {}
int hev_logger_enabled(HevLoggerLevel level) { return level >= HEV_LOGGER_INFO; }
void hev_logger_log(HevLoggerLevel level, const char *format, ...) { record_failure(level, format); }
int hev_socks5_logger_init(HevSocks5LoggerLevel level, const char *path) { (void)level; (void)path; return 0; }
void hev_socks5_logger_fini(void) {}
int hev_socks5_logger_enabled(HevSocks5LoggerLevel level) { return level >= HEV_SOCKS5_LOGGER_INFO; }
void hev_socks5_logger_log(HevSocks5LoggerLevel level, const char *format, ...) { record_failure(level, format); }
