#include "include/IncyNative.h"

#ifdef INCY_HEV_TEST
#include "../Tests/Native/HevTestBackend.h"
#else
#include <pthread.h>
#include <lwip/init.h>
#include <hev-task-system.h>
#include <hev-socks5-misc.h>
#include <hev-socks5-logger.h>
#include "hev-config.h"
#include "hev-logger.h"
#include "hev-socks5-tunnel.h"
#endif

enum TunnelPhase { tunnel_idle, tunnel_starting, tunnel_running, tunnel_finishing };
static pthread_mutex_t lifecycle = PTHREAD_MUTEX_INITIALIZER;
static enum TunnelPhase phase = tunnel_idle;
static int stop_requested;
static int worker_entered;

int incy_tunnel_prepare(void) {
    pthread_mutex_lock(&lifecycle);
    if (phase != tunnel_idle) {
        pthread_mutex_unlock(&lifecycle);
        return -1;
    }
    phase = tunnel_starting;
    stop_requested = 0;
    worker_entered = 0;
    pthread_mutex_unlock(&lifecycle);
    return 0;
}

void incy_tunnel_stop(void) {
    pthread_mutex_lock(&lifecycle);
    if ((phase == tunnel_starting || phase == tunnel_running) && !stop_requested) {
        stop_requested = 1;
        // Calling HEV after its event descriptors close leaves a stop pending
        // for the next connection. Serialize this call with native teardown.
        if (phase == tunnel_running) hev_socks5_tunnel_stop();
    }
    pthread_mutex_unlock(&lifecycle);
}

int incy_tunnel_run(const unsigned char *config, unsigned int length, int fd,
                    IncyTunnelReadyCallback ready, void *context) {
    int result = -1;
    pthread_mutex_lock(&lifecycle);
    if (phase != tunnel_starting || worker_entered) {
        pthread_mutex_unlock(&lifecycle);
        return -1;
    }
    worker_entered = 1;
    int cancelled = stop_requested;
    pthread_mutex_unlock(&lifecycle);
    if (cancelled) { result = -2; goto finish; }
    if (!config || !length || fd < 0) goto finish;
    if (hev_config_init_from_str(config, length) < 0) goto finish;

    hev_socks5_set_connect_timeout(hev_config_get_misc_connect_timeout());
    hev_socks5_set_tcp_timeout(hev_config_get_misc_tcp_read_write_timeout());
    hev_socks5_set_udp_timeout(hev_config_get_misc_udp_read_write_timeout());
    hev_socks5_set_udp_recv_buffer_size(hev_config_get_misc_udp_recv_buffer_size());
    int log_level = hev_config_get_misc_log_level();
    const char *log_file = hev_config_get_misc_log_file();
    if (hev_logger_init(log_level, log_file) < 0) goto finish;
    if (hev_socks5_logger_init(log_level, log_file) < 0) goto free_logger;
    if (hev_task_system_init() < 0) goto free_socks_logger;
    lwip_init();
    if (hev_socks5_tunnel_init(fd) < 0) goto free_lwip;

    pthread_mutex_lock(&lifecycle);
    cancelled = stop_requested;
    phase = cancelled ? tunnel_finishing : tunnel_running;
    pthread_mutex_unlock(&lifecycle);
    if (cancelled) {
        result = -2;
    } else {
        // A stop between this callback and run is buffered by HEV's event fd.
        if (ready) ready(context);
        result = hev_socks5_tunnel_run();
        pthread_mutex_lock(&lifecycle);
        phase = tunnel_finishing;
        pthread_mutex_unlock(&lifecycle);
    }
    hev_socks5_tunnel_fini();
free_lwip:
    lwip_fini();
    hev_task_system_fini();
free_socks_logger:
    hev_socks5_logger_fini();
free_logger:
    hev_logger_fini();
finish:
    pthread_mutex_lock(&lifecycle);
    phase = tunnel_idle;
    pthread_mutex_unlock(&lifecycle);
    return result;
}
