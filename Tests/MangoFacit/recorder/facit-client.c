/*
 * A window for the recordings: an xdg toplevel with the title and app_id it is given, which takes
 * whatever size mango configures (800x600 when mango leaves it to the client). Its first size is
 * its own, 800x600, whatever mango asks: as a macOS app opens with its own size, and as our mango's
 * tests map a window (mango's client_negotiate_initial_size has no part in the port).
 *
 *   facit-client <title> [dialog]
 *
 * "dialog" gives it a fixed size (min = max = 400x300), which mango floats (client_is_float_type).
 * It runs till it is killed, or till mango closes it.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"

static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *wm_base;
static struct wl_surface *surface;
static struct xdg_toplevel *toplevel;
static int pending_w, pending_h, running = 1, dialog, configured;

static struct wl_buffer *make_buffer(int w, int h) {
	int stride = w * 4, size = stride * h;
	int fd = memfd_create("facit", MFD_CLOEXEC);
	if (fd < 0 || ftruncate(fd, size) < 0) exit(1);
	void *data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	memset(data, 0x80, size);
	munmap(data, size);
	struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
	struct wl_buffer *buf = wl_shm_pool_create_buffer(pool, 0, w, h, stride, WL_SHM_FORMAT_XRGB8888);
	wl_shm_pool_destroy(pool);
	close(fd);
	return buf;
}

static void buffer_release(void *data, struct wl_buffer *buf) { wl_buffer_destroy(buf); }
static const struct wl_buffer_listener buffer_listener = {.release = buffer_release};

static void surface_configure(void *data, struct xdg_surface *xs, uint32_t serial) {
	xdg_surface_ack_configure(xs, serial);
	int first = !configured++;
	int w = pending_w > 0 && !first ? pending_w : (dialog ? 400 : 800);
	int h = pending_h > 0 && !first ? pending_h : (dialog ? 300 : 600);
	struct wl_buffer *buf = make_buffer(w, h);
	wl_buffer_add_listener(buf, &buffer_listener, NULL);
	wl_surface_attach(surface, buf, 0, 0);
	wl_surface_damage_buffer(surface, 0, 0, w, h);
	wl_surface_commit(surface);
}
static const struct xdg_surface_listener surface_listener = {.configure = surface_configure};

static void toplevel_configure(void *data, struct xdg_toplevel *t, int32_t w, int32_t h, struct wl_array *states) {
	pending_w = w;
	pending_h = h;
}
static void toplevel_close(void *data, struct xdg_toplevel *t) { running = 0; }
static void toplevel_bounds(void *data, struct xdg_toplevel *t, int32_t w, int32_t h) {}
static void toplevel_caps(void *data, struct xdg_toplevel *t, struct wl_array *caps) {}
static const struct xdg_toplevel_listener toplevel_listener = {
	.configure = toplevel_configure, .close = toplevel_close,
	.configure_bounds = toplevel_bounds, .wm_capabilities = toplevel_caps};

static void ping(void *data, struct xdg_wm_base *b, uint32_t serial) { xdg_wm_base_pong(b, serial); }
static const struct xdg_wm_base_listener wm_base_listener = {.ping = ping};

static void global(void *data, struct wl_registry *r, uint32_t name, const char *iface, uint32_t version) {
	if (strcmp(iface, wl_compositor_interface.name) == 0)
		compositor = wl_registry_bind(r, name, &wl_compositor_interface, 4);
	else if (strcmp(iface, wl_shm_interface.name) == 0)
		shm = wl_registry_bind(r, name, &wl_shm_interface, 1);
	else if (strcmp(iface, xdg_wm_base_interface.name) == 0) {
		wm_base = wl_registry_bind(r, name, &xdg_wm_base_interface, 4);
		xdg_wm_base_add_listener(wm_base, &wm_base_listener, NULL);
	}
}
static void global_remove(void *data, struct wl_registry *r, uint32_t name) {}
static const struct wl_registry_listener registry_listener = {.global = global, .global_remove = global_remove};

int main(int argc, char **argv) {
	if (argc < 2) return 2;
	dialog = argc > 2 && strcmp(argv[2], "dialog") == 0;
	struct wl_display *display = wl_display_connect(NULL);
	if (!display) return 1;
	struct wl_registry *registry = wl_display_get_registry(display);
	wl_registry_add_listener(registry, &registry_listener, NULL);
	wl_display_roundtrip(display);

	surface = wl_compositor_create_surface(compositor);
	struct xdg_surface *xs = xdg_wm_base_get_xdg_surface(wm_base, surface);
	xdg_surface_add_listener(xs, &surface_listener, NULL);
	toplevel = xdg_surface_get_toplevel(xs);
	xdg_toplevel_add_listener(toplevel, &toplevel_listener, NULL);
	xdg_toplevel_set_title(toplevel, argv[1]);
	xdg_toplevel_set_app_id(toplevel, argv[1]);
	if (dialog) {
		xdg_toplevel_set_min_size(toplevel, 400, 300);
		xdg_toplevel_set_max_size(toplevel, 400, 300);
	}
	wl_surface_commit(surface);

	while (running && wl_display_dispatch(display) != -1) {}
	return 0;
}
