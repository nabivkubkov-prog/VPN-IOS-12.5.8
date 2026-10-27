#ifndef INCY_NATIVE_H
#define INCY_NATIVE_H
#include <stddef.h>
#include <stdint.h>
char *IncyXrayStart(char *config);
void IncyXrayStop(void);
void IncyXrayFree(char *value);
typedef void (*IncyTunnelReadyCallback)(void *context);
// Prepare before dispatching the worker so an immediate stop is remembered.
int incy_tunnel_prepare(void);
// Blocks until stopped; calls ready only after the packet engine initializes.
int incy_tunnel_run(const unsigned char *config, unsigned int length, int fd,
                    IncyTunnelReadyCallback ready, void *context);
void incy_tunnel_stop(void);
int incy_socket_pair(int *fds);
int incy_send_packet(int fd, const void *packet, size_t size, int family);
int incy_receive_packet(int fd, void *packet, size_t capacity, int *family);
#endif

