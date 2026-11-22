/*
 * A window for the recordings: an xdg toplevel with the title and app_id it is given, which takes
 * whatever size mango configures (800x600 when mango leaves it to the client). Its first size is
 * its own, 800x600, whatever mango asks: as a macOS app opens with its own size, and as our mango's
 * tests map a window (mango's client_negotiate_initial_size has no part in the port).
 *
 *   facit-client <title> [<w>x<h>] [dialog]
 *
 * "dialog" gives it a fixed size (min = max = its size, 400x300 unless given), which mango floats
 * (client_is_float_type). It runs till it is killed, or till mango closes it. A line on stdin is a
 * request of the app's own, sent to mango:
 *
 *   minimize        xdg_toplevel set_minimized
 *   title <title>   xdg_toplevel set_title
 *   token           xdg_activation_v1: a token for its own surface, with the serial of the last time
 *                   it had the keyboard, printed on stdout (as the app the user is in hands one on)
 *   activate <tok>  xdg_activation_v1 activate with a token another app gave it
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <poll.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"
#include "xdg-activation-v1-client-protocol.h"

static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *wm_base;
static struct wl_surface *surface;
static struct xdg_toplevel *toplevel;
static struct xdg_activation_v1 *activation;
static struct wl_seat *seat;
static uint32_t focus_serial;
static int pending_w, pending_h, running = 1, dialog, configured, own_w, own_h;

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
	int w = pending_w > 0 && !first ? pending_w : own_w;
	int h = pending_h > 0 && !first ? pending_h : own_h;
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
	} else if (strcmp(iface, xdg_activation_v1_interface.name) == 0)
		activation = wl_registry_bind(r, name, &xdg_activation_v1_interface, 1);
	else if (strcmp(iface, wl_seat_interface.name) == 0)
		seat = wl_registry_bind(r, name, &wl_seat_interface, 1);
}

/* The keyboard only for the serial of its last enter. */
static void kb_keymap(void *d, struct wl_keyboard *k, uint32_t f, int32_t fd, uint32_t size) { close(fd); }
static void kb_enter(void *d, struct wl_keyboard *k, uint32_t serial, struct wl_surface *s, struct wl_array *keys) {
	focus_serial = serial;
}
static void kb_leave(void *d, struct wl_keyboard *k, uint32_t serial, struct wl_surface *s) {}
static void kb_key(void *d, struct wl_keyboard *k, uint32_t serial, uint32_t t, uint32_t key, uint32_t state) {}
static void kb_mods(void *d, struct wl_keyboard *k, uint32_t serial, uint32_t a, uint32_t b, uint32_t c, uint32_t g) {}
static const struct wl_keyboard_listener keyboard_listener = {kb_keymap, kb_enter, kb_leave, kb_key, kb_mods};

/* The keyboard once the seat has one (a virtual keyboard: headless mango has none of its own). */
static struct wl_keyboard *keyboard;
static void seat_caps(void *d, struct wl_seat *s, uint32_t caps) {
	if (caps & WL_SEAT_CAPABILITY_KEYBOARD && !keyboard) {
		keyboard = wl_seat_get_keyboard(s);
		wl_keyboard_add_listener(keyboard, &keyboard_listener, NULL);
	}
}
static const struct wl_seat_listener seat_listener = {.capabilities = seat_caps};

static void token_done(void *data, struct xdg_activation_token_v1 *token, const char *name) {
	printf("%s\n", name);
	fflush(stdout);
	xdg_activation_token_v1_destroy(token);
}
static const struct xdg_activation_token_v1_listener token_listener = {.done = token_done};

/* A request of the app's own, a line of stdin. */
static void request(const char *line) {
	if (strncmp(line, "minimize", 8) == 0) {
		xdg_toplevel_set_minimized(toplevel);
	} else if (strncmp(line, "title ", 6) == 0) {
		char title[128];
		if (sscanf(line + 6, "%127s", title) == 1) xdg_toplevel_set_title(toplevel, title);
	} else if (strncmp(line, "activate ", 9) == 0 && activation) {
		char name[256];
		if (sscanf(line + 9, "%255s", name) == 1) xdg_activation_v1_activate(activation, name, surface);
	} else if (strncmp(line, "token", 5) == 0 && activation) {
		struct xdg_activation_token_v1 *token = xdg_activation_v1_get_activation_token(activation);
		xdg_activation_token_v1_add_listener(token, &token_listener, NULL);
		xdg_activation_token_v1_set_surface(token, surface);
		if (seat) xdg_activation_token_v1_set_serial(token, focus_serial, seat);
		xdg_activation_token_v1_commit(token);
	}
}
static void global_remove(void *data, struct wl_registry *r, uint32_t name) {}
static const struct wl_registry_listener registry_listener = {.global = global, .global_remove = global_remove};

int main(int argc, char **argv) {
	if (argc < 2) return 2;
	for (int i = 2; i < argc; i++) {
		if (strcmp(argv[i], "dialog") == 0) dialog = 1;
		else sscanf(argv[i], "%dx%d", &own_w, &own_h);
	}
	if (!own_w || !own_h) { own_w = dialog ? 400 : 800; own_h = dialog ? 300 : 600; }
	struct wl_display *display = wl_display_connect(NULL);
	if (!display) return 1;
	struct wl_registry *registry = wl_display_get_registry(display);
	wl_registry_add_listener(registry, &registry_listener, NULL);
	wl_display_roundtrip(display);

	if (seat) wl_seat_add_listener(seat, &seat_listener, NULL);
	surface = wl_compositor_create_surface(compositor);
	struct xdg_surface *xs = xdg_wm_base_get_xdg_surface(wm_base, surface);
	xdg_surface_add_listener(xs, &surface_listener, NULL);
	toplevel = xdg_surface_get_toplevel(xs);
	xdg_toplevel_add_listener(toplevel, &toplevel_listener, NULL);
	xdg_toplevel_set_title(toplevel, argv[1]);
	xdg_toplevel_set_app_id(toplevel, argv[1]);
	if (dialog) {
		xdg_toplevel_set_min_size(toplevel, own_w, own_h);
		xdg_toplevel_set_max_size(toplevel, own_w, own_h);
	}
	wl_surface_commit(surface);

	struct pollfd fds[2] = {{.fd = wl_display_get_fd(display), .events = POLLIN}, {.fd = 0, .events = POLLIN}};
	char line[256];
	while (running) {
		wl_display_flush(display);
		if (poll(fds, 2, -1) < 0) break;
		if (fds[0].revents & POLLIN && wl_display_dispatch(display) == -1) break;
		if (fds[1].revents & POLLIN) {
			if (!fgets(line, sizeof line, stdin)) { fds[1].fd = -1; continue; }
			request(line);
		}
		wl_display_dispatch_pending(display);
	}
	return 0;
}
