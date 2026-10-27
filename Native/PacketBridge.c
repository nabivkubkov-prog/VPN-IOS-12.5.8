#include "include/IncyNative.h"
#include <sys/socket.h>
#include <sys/uio.h>
#include <fcntl.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <errno.h>

int incy_socket_pair(int *fds) {
    if (socketpair(AF_UNIX, SOCK_DGRAM, 0, fds) != 0) return -1;
    int buffer = 262144;
    for (int i = 0; i < 2; ++i) {
        fcntl(fds[i], F_SETFL, fcntl(fds[i], F_GETFL) | O_NONBLOCK);
        setsockopt(fds[i], SOL_SOCKET, SO_SNDBUF, &buffer, sizeof(buffer));
        setsockopt(fds[i], SOL_SOCKET, SO_RCVBUF, &buffer, sizeof(buffer));
    }
    return 0;
}

int incy_send_packet(int fd, const void *packet, size_t size, int family) {
    uint32_t prefix = htonl((uint32_t)family);
    struct iovec vector[2] = {{&prefix, sizeof(prefix)}, {(void *)packet, size}};
    ssize_t n = writev(fd, vector, 2);
    return n == (ssize_t)(size + sizeof(prefix)) ? 0 : -1;
}

int incy_receive_packet(int fd, void *packet, size_t capacity, int *family) {
    uint32_t prefix = 0;
    struct iovec vector[2] = {{&prefix, sizeof(prefix)}, {packet, capacity}};
    ssize_t n = readv(fd, vector, 2);
    if (n <= (ssize_t)sizeof(prefix)) return -1;
    *family = (int)ntohl(prefix);
    if (*family != AF_INET && *family != AF_INET6) return -1;
    return (int)(n - sizeof(prefix));
}

