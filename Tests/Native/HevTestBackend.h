#ifndef INCY_HEV_TEST_BACKEND_H
#define INCY_HEV_TEST_BACKEND_H

// Only used by the isolated lifecycle tests, without an Apple SDK or a TUN.
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
typedef SRWLOCK pthread_mutex_t;
#define PTHREAD_MUTEX_INITIALIZER SRWLOCK_INIT
static inline int pthread_mutex_lock(pthread_mutex_t *lock) { AcquireSRWLockExclusive(lock); return 0; }
static inline int pthread_mutex_unlock(pthread_mutex_t *lock) { ReleaseSRWLockExclusive(lock); return 0; }
#else
#include <pthread.h>
#endif

int hev_config_init_from_str(const unsigned char *, unsigned int);
int hev_config_get_misc_connect_timeout(void);
int hev_config_get_misc_tcp_read_write_timeout(void);
int hev_config_get_misc_udp_read_write_timeout(void);
int hev_config_get_misc_udp_recv_buffer_size(void);
int hev_config_get_misc_log_level(void);
const char *hev_config_get_misc_log_file(void);
void hev_socks5_set_connect_timeout(int);
void hev_socks5_set_tcp_timeout(int);
void hev_socks5_set_udp_timeout(int);
void hev_socks5_set_udp_recv_buffer_size(int);
int hev_logger_init(int, const char *);
void hev_logger_fini(void);
int hev_socks5_logger_init(int, const char *);
void hev_socks5_logger_fini(void);
int hev_task_system_init(void);
void hev_task_system_fini(void);
void lwip_init(void);
void lwip_fini(void);
int hev_socks5_tunnel_init(int);
int hev_socks5_tunnel_run(void);
void hev_socks5_tunnel_fini(void);
void hev_socks5_tunnel_stop(void);
#endif
