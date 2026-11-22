/*
 * Keys and pointer for the recordings: a virtual keyboard (zwp_virtual_keyboard_v1) and a virtual
 * pointer (zwlr_virtual_pointer_v1), as mango offers both to any client. It reads one command a
 * line on stdin and answers "ok" once mango has had it (a roundtrip):
 *
 *   keydown <keysym>          a key goes down (super, shift, ctrl, alt stand for their _L key)
 *   keyup <keysym>            and up
 *   pointer <x> <y> <w> <h>   the pointer to x,y in the layout of w x h (motion_absolute)
 *   motion <dx> <dy>          the pointer moved by dx,dy (motion)
 *   button <left|right|middle> <down|up>
 *   scroll <up|down|left|right>   one notch of a wheel
 *
 * The keymap is xkbcommon's default (us), as mango's own keyboard has it with no xkb_rules set.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <linux/input-event-codes.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include "virtual-keyboard-unstable-v1-client-protocol.h"
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *keyboard_manager;
static struct zwlr_virtual_pointer_manager_v1 *pointer_manager;
static struct zwp_virtual_keyboard_v1 *keyboard;
static struct zwlr_virtual_pointer_v1 *pointer;
static struct xkb_keymap *keymap;
static struct xkb_state *state;

static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface,
				   uint32_t version) {
	if (strcmp(interface, wl_seat_interface.name) == 0)
		seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
	else if (strcmp(interface, zwp_virtual_keyboard_manager_v1_interface.name) == 0)
		keyboard_manager = wl_registry_bind(registry, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
	else if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0)
		pointer_manager = wl_registry_bind(registry, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
}

static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {}

static const struct wl_registry_listener registry_listener = {global, global_remove};

static uint32_t now(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static const char *alias(const char *name) {
	if (strcasecmp(name, "super") == 0) return "Super_L";
	if (strcasecmp(name, "shift") == 0) return "Shift_L";
	if (strcasecmp(name, "ctrl") == 0) return "Control_L";
	if (strcasecmp(name, "alt") == 0) return "Alt_L";
	return name;
}

/* The evdev keycode of a keysym in the keymap (xkb keycode - 8), or -1. */
static int keycode(const char *name) {
	xkb_keysym_t sym = xkb_keysym_from_name(alias(name), XKB_KEYSYM_CASE_INSENSITIVE);
	if (sym == XKB_KEY_NoSymbol) return -1;
	for (xkb_keycode_t kc = xkb_keymap_min_keycode(keymap); kc <= xkb_keymap_max_keycode(keymap); kc++) {
		const xkb_keysym_t *syms;
		int n = xkb_keymap_key_get_syms_by_level(keymap, kc, 0, 0, &syms);
		for (int i = 0; i < n; i++)
			if (syms[i] == sym) return kc - 8;
	}
	return -1;
}

static void key(int code, int down) {
	zwp_virtual_keyboard_v1_key(keyboard, now(), code,
								down ? WL_KEYBOARD_KEY_STATE_PRESSED : WL_KEYBOARD_KEY_STATE_RELEASED);
	xkb_state_update_key(state, code + 8, down ? XKB_KEY_DOWN : XKB_KEY_UP);
	zwp_virtual_keyboard_v1_modifiers(keyboard, xkb_state_serialize_mods(state, XKB_STATE_MODS_DEPRESSED),
									  xkb_state_serialize_mods(state, XKB_STATE_MODS_LATCHED),
									  xkb_state_serialize_mods(state, XKB_STATE_MODS_LOCKED),
									  xkb_state_serialize_layout(state, XKB_STATE_LAYOUT_EFFECTIVE));
}

int main(void) {
	struct wl_display *display = wl_display_connect(NULL);
	if (!display) return 1;
	struct wl_registry *registry = wl_display_get_registry(display);
	wl_registry_add_listener(registry, &registry_listener, NULL);
	wl_display_roundtrip(display);
	if (!seat || !keyboard_manager || !pointer_manager) {
		fprintf(stderr, "facit-input: mango offers no virtual keyboard or pointer\n");
		return 1;
	}

	struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	keymap = xkb_keymap_new_from_names(context, NULL, XKB_KEYMAP_COMPILE_NO_FLAGS);
	state = xkb_state_new(keymap);
	char *text = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
	size_t size = strlen(text) + 1;
	int fd = memfd_create("keymap", MFD_CLOEXEC);
	if (fd < 0 || write(fd, text, size) != (ssize_t)size) return 1;

	keyboard = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(keyboard_manager, seat);
	zwp_virtual_keyboard_v1_keymap(keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, size);
	pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(pointer_manager, seat);
	wl_display_roundtrip(display);
	printf("ok\n");
	fflush(stdout);

	char line[256], word[32], a[64], b[64];
	unsigned x, y, w, h;
	while (fgets(line, sizeof line, stdin)) {
		if (sscanf(line, "%31s", word) != 1) continue;
		if (strcmp(word, "keydown") == 0 || strcmp(word, "keyup") == 0) {
			if (sscanf(line, "%*s %63s", a) != 1 || keycode(a) < 0) {
				fprintf(stderr, "facit-input: no key %s\n", a);
				return 1;
			}
			key(keycode(a), word[3] == 'd');
		} else if (strcmp(word, "pointer") == 0 && sscanf(line, "%*s %u %u %u %u", &x, &y, &w, &h) == 4) {
			zwlr_virtual_pointer_v1_motion_absolute(pointer, now(), x, y, w, h);
			zwlr_virtual_pointer_v1_frame(pointer);
		} else if (strcmp(word, "motion") == 0 && sscanf(line, "%*s %63s %63s", a, b) == 2) {
			zwlr_virtual_pointer_v1_motion(pointer, now(), wl_fixed_from_int(atoi(a)), wl_fixed_from_int(atoi(b)));
			zwlr_virtual_pointer_v1_frame(pointer);
		} else if (strcmp(word, "button") == 0 && sscanf(line, "%*s %63s %63s", a, b) == 2) {
			uint32_t button = strcmp(a, "right") == 0 ? BTN_RIGHT : strcmp(a, "middle") == 0 ? BTN_MIDDLE : BTN_LEFT;
			zwlr_virtual_pointer_v1_button(pointer, now(), button,
										   strcmp(b, "down") == 0 ? WL_POINTER_BUTTON_STATE_PRESSED
																  : WL_POINTER_BUTTON_STATE_RELEASED);
			zwlr_virtual_pointer_v1_frame(pointer);
		} else if (strcmp(word, "scroll") == 0 && sscanf(line, "%*s %63s", a) == 1) {
			int horizontal = strcmp(a, "left") == 0 || strcmp(a, "right") == 0;
			int sign = strcmp(a, "up") == 0 || strcmp(a, "left") == 0 ? -1 : 1;
			uint32_t axis = horizontal ? WL_POINTER_AXIS_HORIZONTAL_SCROLL : WL_POINTER_AXIS_VERTICAL_SCROLL;
			zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_WHEEL);
			zwlr_virtual_pointer_v1_axis_discrete(pointer, now(), axis, wl_fixed_from_int(15 * sign), sign);
			zwlr_virtual_pointer_v1_frame(pointer);
		} else {
			fprintf(stderr, "facit-input: %s", line);
			return 1;
		}
		wl_display_roundtrip(display);
		printf("ok\n");
		fflush(stdout);
	}
	return 0;
}
