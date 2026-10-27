#include "../../Native/include/IncyNative.h"
#include "HevTestBackend.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <time.h>

#define CHECK(value) do { if (!(value)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #value); return 1; } } while (0)

static int fail_stage, cancel_in_config, stop_in_fini, wait_for_stop, pause_in_fini;
static int config_calls, tunnel_init_calls, run_calls, tunnel_fini_calls;
static int logger_fini_calls, socks_logger_fini_calls, task_fini_calls, lwip_fini_calls;
static atomic_int ready_calls, stop_calls, initialized, invalid_stops, finishing;
static int worker_result;

static void sleep_ms(int milliseconds) {
#ifdef _WIN32
    Sleep((DWORD)milliseconds);
#else
    struct timespec delay = { milliseconds / 1000, (milliseconds % 1000) * 1000000L };
    nanosleep(&delay, NULL);
#endif
}

static void reset_backend(void) {
    fail_stage = cancel_in_config = stop_in_fini = wait_for_stop = pause_in_fini = 0;
    config_calls = tunnel_init_calls = run_calls = tunnel_fini_calls = 0;
    logger_fini_calls = socks_logger_fini_calls = task_fini_calls = lwip_fini_calls = 0;
    atomic_store(&ready_calls, 0); atomic_store(&stop_calls, 0);
    atomic_store(&initialized, 0); atomic_store(&invalid_stops, 0); atomic_store(&finishing, 0);
}

int hev_config_init_from_str(const unsigned char *config, unsigned int length) {
    (void)config; (void)length; ++config_calls;
    if (cancel_in_config) incy_tunnel_stop();
    return fail_stage == 1 ? -1 : 0;
}
int hev_config_get_misc_connect_timeout(void) { return 8000; }
int hev_config_get_misc_tcp_read_write_timeout(void) { return 120000; }
int hev_config_get_misc_udp_read_write_timeout(void) { return 30000; }
int hev_config_get_misc_udp_recv_buffer_size(void) { return 32768; }
int hev_config_get_misc_log_level(void) { return 3; }
const char *hev_config_get_misc_log_file(void) { return NULL; }
void hev_socks5_set_connect_timeout(int value) { (void)value; }
void hev_socks5_set_tcp_timeout(int value) { (void)value; }
void hev_socks5_set_udp_timeout(int value) { (void)value; }
void hev_socks5_set_udp_recv_buffer_size(int value) { (void)value; }
int hev_logger_init(int level, const char *file) { (void)level; (void)file; return fail_stage == 2 ? -1 : 0; }
void hev_logger_fini(void) { ++logger_fini_calls; }
int hev_socks5_logger_init(int level, const char *file) { (void)level; (void)file; return fail_stage == 3 ? -1 : 0; }
void hev_socks5_logger_fini(void) { ++socks_logger_fini_calls; }
int hev_task_system_init(void) { return fail_stage == 4 ? -1 : 0; }
void hev_task_system_fini(void) { ++task_fini_calls; }
void lwip_init(void) {}
void lwip_fini(void) { ++lwip_fini_calls; }
int hev_socks5_tunnel_init(int fd) {
    (void)fd; ++tunnel_init_calls;
    if (fail_stage == 5) return -1;
    atomic_store(&initialized, 1); return 0;
}
int hev_socks5_tunnel_run(void) {
    ++run_calls;
    if (wait_for_stop) {
        for (int i = 0; i < 200 && atomic_load(&stop_calls) == 0; ++i) sleep_ms(10);
        if (atomic_load(&stop_calls) == 0) return -9;
    }
    return 0;
}
void hev_socks5_tunnel_fini(void) {
    ++tunnel_fini_calls; atomic_store(&initialized, 0); atomic_store(&finishing, 1);
    if (stop_in_fini) incy_tunnel_stop();
    if (pause_in_fini) sleep_ms(80);
}
void hev_socks5_tunnel_stop(void) {
    if (!atomic_load(&initialized)) atomic_fetch_add(&invalid_stops, 1);
    atomic_fetch_add(&stop_calls, 1);
}

static void ready(void *context) {
    if (!atomic_load(&initialized)) abort();
    atomic_fetch_add(&ready_calls, 1);
    if (context) { incy_tunnel_stop(); incy_tunnel_stop(); }
}
static int run_bridge(void *context) {
    static const unsigned char config[] = "fixture";
    return incy_tunnel_run(config, sizeof(config) - 1, 7, ready, context);
}

static int test_cancel_before_worker_and_restart(void) {
    reset_backend();
    CHECK(incy_tunnel_prepare() == 0);
    CHECK(incy_tunnel_prepare() == -1);
    incy_tunnel_stop();
    CHECK(run_bridge(NULL) == -2);
    CHECK(config_calls == 0 && atomic_load(&ready_calls) == 0 && atomic_load(&stop_calls) == 0);
    CHECK(incy_tunnel_prepare() == 0);
    CHECK(run_bridge(NULL) == 0);
    CHECK(atomic_load(&ready_calls) == 1 && tunnel_fini_calls == 1);
    return 0;
}

static int test_cancel_during_initialization(void) {
    reset_backend(); cancel_in_config = 1;
    CHECK(incy_tunnel_prepare() == 0);
    CHECK(run_bridge(NULL) == -2);
    CHECK(run_calls == 0 && atomic_load(&ready_calls) == 0 && atomic_load(&stop_calls) == 0);
    CHECK(tunnel_fini_calls == 1 && lwip_fini_calls == 1 && task_fini_calls == 1);
    return 0;
}

static int test_failures_cleanup_and_restart(void) {
    for (int stage = 1; stage <= 5; ++stage) {
        reset_backend(); fail_stage = stage;
        CHECK(incy_tunnel_prepare() == 0);
        CHECK(run_bridge(NULL) == -1);
        CHECK(atomic_load(&ready_calls) == 0 && run_calls == 0);
        CHECK(logger_fini_calls == (stage >= 3));
        CHECK(socks_logger_fini_calls == (stage >= 4));
        CHECK(task_fini_calls == (stage >= 5) && lwip_fini_calls == (stage >= 5));
        reset_backend();
        CHECK(incy_tunnel_prepare() == 0);
        CHECK(run_bridge(NULL) == 0 && atomic_load(&ready_calls) == 1);
    }
    return 0;
}

static int test_stop_at_ready_is_idempotent(void) {
    reset_backend();
    CHECK(incy_tunnel_prepare() == 0);
    CHECK(run_bridge((void *)1) == 0);
    CHECK(atomic_load(&stop_calls) == 1 && atomic_load(&invalid_stops) == 0);
    incy_tunnel_stop();
    CHECK(atomic_load(&stop_calls) == 1);
    return 0;
}

static int test_stop_during_teardown_does_not_poison_restart(void) {
    reset_backend(); stop_in_fini = 1;
    CHECK(incy_tunnel_prepare() == 0);
    CHECK(run_bridge(NULL) == 0);
    CHECK(atomic_load(&stop_calls) == 0 && atomic_load(&invalid_stops) == 0);
    reset_backend();
    CHECK(incy_tunnel_prepare() == 0);
    CHECK(run_bridge(NULL) == 0 && atomic_load(&ready_calls) == 1);
    return 0;
}

#ifdef _WIN32
static DWORD WINAPI worker_entry(LPVOID unused) { (void)unused; worker_result = run_bridge(NULL); return 0; }
#else
static void *worker_entry(void *unused) { (void)unused; worker_result = run_bridge(NULL); return NULL; }
#endif

static int test_concurrent_stop_and_teardown(void) {
    reset_backend(); wait_for_stop = pause_in_fini = 1;
    CHECK(incy_tunnel_prepare() == 0);
#ifdef _WIN32
    HANDLE thread = CreateThread(NULL, 0, worker_entry, NULL, 0, NULL);
    CHECK(thread != NULL);
#else
    pthread_t thread;
    CHECK(pthread_create(&thread, NULL, worker_entry, NULL) == 0);
#endif
    for (int i = 0; i < 200 && atomic_load(&ready_calls) == 0; ++i) sleep_ms(10);
    CHECK(atomic_load(&ready_calls) == 1);
    incy_tunnel_stop();
    for (int i = 0; i < 100 && atomic_load(&finishing) == 0; ++i) sleep_ms(1);
    CHECK(atomic_load(&finishing) == 1);
    for (int i = 0; i < 100; ++i) incy_tunnel_stop();
#ifdef _WIN32
    CHECK(WaitForSingleObject(thread, 3000) == WAIT_OBJECT_0);
    CloseHandle(thread);
#else
    CHECK(pthread_join(thread, NULL) == 0);
#endif
    CHECK(worker_result == 0 && atomic_load(&stop_calls) == 1 && atomic_load(&invalid_stops) == 0);
    return 0;
}

int main(void) {
    if (test_cancel_before_worker_and_restart() || test_cancel_during_initialization() ||
        test_failures_cleanup_and_restart() || test_stop_at_ready_is_idempotent() ||
        test_stop_during_teardown_does_not_poison_restart() || test_concurrent_stop_and_teardown()) return 1;
    puts("Native lifecycle passed: cancellation, 5 startup failures, readiness, repeated stop, teardown and restart.");
    return 0;
}
