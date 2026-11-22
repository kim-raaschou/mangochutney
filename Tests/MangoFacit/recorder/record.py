#!/usr/bin/env python3
"""Records what mango does in each scenario: its answer to `mmsg get` after each `check`.

    record.py /scenarios/tile.mango ...      one mango per scenario, facit to /facit/<name>.json
    record.py /configs/errors.conf ...       `mango -c <file> -p`, facit to /facit/configs/<file>.json

A scenario is a few lines, run top to bottom:

    config new_is_master=0        a line of mango's config (before mango starts)
    monitors 2                    two outputs side by side (before mango starts; one when not given)
    open a [dialog]               a window titled a (facit-client)
    close a                       the window goes (its client is killed)
    dispatch focusstack,next      as `mmsg dispatch focusstack,next`
    dispatch @b killclient        aimed at the window titled b: `mmsg dispatch killclient client,<its id>`
    key super+shift+j             keys of a virtual keyboard: down in order, then up the other way
    keydown super / keyup super   one key down or up, held across the steps between
    pointer 500,300               the virtual pointer to 500,300 in the layout
    move -400,500                 the pointer moved by -400,500 (kept off the layout's edges: no clamping)
    click left                    a button down and up; `button left down` / `button left up` alone
    scroll down                   one notch of the wheel (up, down, left, right)
    check                         mango's state now goes in the facit
    get all-tags                  mango's answer to `mmsg get all-tags` goes in the facit (`@b` names a client)
    ours b.height 352             not recorded: where our answer differs on purpose (read by the tests)

The recording waits for mango to settle after each step: it asks again till two answers agree.
That is a poll, here in the recorder only; the tests that read the facit wait for nothing.
"""
import json, os, re, subprocess, sys, time

def screens(n):
    return [{"name": f"HEADLESS-{i + 1}", "x": 1920 * i, "y": 0, "width": 1920, "height": 1080} for i in range(n)]


def base_config(n):
    rules = [f"monitor_rule=name:{s['name']},x:{s['x']},y:{s['y']},width:{s['width']},height:{s['height']},refresh:60"
             for s in screens(n)]
    return rules + ["animations=0"]
# What a test compares: mango's state, not its bookkeeping (pid, ids) or what macOS has not (xwayland).
CLIENT_FIELDS = ["title", "monitor", "tags", "x", "y", "width", "height", "is_focused", "is_visible",
                 "is_floating", "is_fullscreen", "is_fakefullscreen", "is_maximized", "is_minimized",
                 "is_global", "is_unglobal", "is_overlay", "is_urgent", "is_scratchpad",
                 "is_namedscratchpad", "is_group", "is_group_focus", "scroller_proportion"]
MONITOR_FIELDS = ["name", "active", "x", "y", "width", "height", "layout_symbol", "layout_index",
                  "tag_num", "tags", "active_tags", "active_client", "hide_clients", "keymode"]


def parse(path):
    config, steps, monitors = [], [], 1
    for n, raw in enumerate(open(path), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        word, _, rest = line.partition(" ")
        if word == "config":
            config.append(rest)
        elif word == "monitors":
            monitors = int(rest)
        elif word == "ours":
            pass
        elif word in ("open", "close", "dispatch", "check", "key", "keydown", "keyup", "pointer", "move", "click", "get",
                      "button", "scroll"):
            steps.append((n, word, rest))
        else:
            sys.exit(f"{path}:{n}: unknown step {word!r}")
    return config, steps, monitors


def mmsg(*args):
    out = subprocess.run(["/build/mango/build/mmsg", *args], capture_output=True, text=True, timeout=5)
    return out.stdout


def get(what):
    return json.loads(mmsg("get", what))


def settled():
    """mango's state once three answers in a row, 40 ms apart, agree (a closed client, a frame)."""
    seen = []
    for _ in range(150):
        time.sleep(0.04)
        seen.append((get("all-clients"), get("all-monitors"), get("cursorpos")))
        if len(seen) >= 3 and seen[-1] == seen[-2] == seen[-3]:
            return seen[-1]
    sys.exit("mango did not settle")


def snapshot(line):
    clients, monitors, cursor = settled()
    monitors = [{k: m.get(k) for k in MONITOR_FIELDS} for m in monitors["monitors"]]
    for m in monitors:   # its title: ids are mango's own
        m["active_client"] = m["active_client"]["title"]
    return {
        "after_line": line,
        "clients": [{k: c.get(k) for k in CLIENT_FIELDS} for c in clients["clients"]],
        "monitors": monitors,
        "cursor": {"x": cursor["x"], "y": cursor["y"]},
    }


def client_id(title):
    """mango's id of the window titled `title`."""
    ids = [c["id"] for c in get("all-clients")["clients"] if c["title"] == title]
    if not ids:
        sys.exit(f"no window titled {title!r}")
    return ids[0]


def target(rest):
    """`@b func,args` is mango's `func,args client,<id>`, with the id of the window titled b."""
    if not rest.startswith("@"):
        return rest
    title, _, rest = rest[1:].partition(" ")
    return f"{rest} client,{client_id(title)}"


class Input:
    """facit-input: mango's virtual keyboard and pointer, a command a line, each answered once mango has it."""
    def __init__(self, layout):
        self.layout = layout
        self.proc = subprocess.Popen(["/build/facit-input"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        self.answer()

    def answer(self):
        if self.proc.stdout.readline().strip() != "ok":
            sys.exit("facit-input failed")

    def send(self, *lines):
        for line in lines:
            self.proc.stdin.write(line + "\n")
            self.proc.stdin.flush()
            self.answer()

    def step(self, word, rest):
        if word == "key":
            keys = rest.split("+")
            self.send(*[f"keydown {k}" for k in keys], *[f"keyup {k}" for k in reversed(keys)])
        elif word in ("keydown", "keyup"):
            self.send(f"{word} {rest}")
        elif word == "pointer":
            x, y = rest.split(",")
            self.send(f"pointer {x} {y} {self.layout[0]} {self.layout[1]}")
        elif word == "move":
            dx, dy = rest.split(",")
            self.send(f"motion {dx} {dy}")
        elif word == "click":
            self.send(f"button {rest} down", f"button {rest} up")
        elif word == "button":
            self.send(f"button {rest}")
        elif word == "scroll":
            self.send(f"scroll {rest}")


def answer(value):
    """An mmsg answer without mango's bookkeeping (ids, pids, a foreign toplevel's random id)."""
    if isinstance(value, dict):
        return {k: answer(v) for k, v in value.items() if k not in ("id", "pid", "foreign_toplevel_id")}
    if isinstance(value, list):
        return [answer(v) for v in value]
    return value


def titles():
    return [c["title"] for c in get("all-clients")["clients"]]


def play(scenario, out):
    """Runs inside mango (mango -s): WAYLAND_DISPLAY and MANGO_INSTANCE_SIGNATURE are set."""
    _, steps, monitors = parse(scenario)
    # The order the backend gave the outputs in: mango puts each new one first in its list.
    given = [m["name"] for m in reversed(get("all-monitors")["monitors"])]
    # Where wlroots put the pointer at the start: the platform's, not mango's.
    start = get("cursorpos")
    windows, checks, keys, gets = {}, [], None, []
    layout = (sum(s["width"] for s in screens(monitors)), max(s["height"] for s in screens(monitors)))
    for n, word, rest in steps:
        if word == "open":
            title, *kind = rest.split()
            windows[title] = subprocess.Popen(["/build/facit-client", title, *kind])
            while title not in titles():
                time.sleep(0.01)
        elif word == "close":
            windows.pop(rest).kill()
            while rest in titles():
                time.sleep(0.01)
        elif word == "dispatch":
            mmsg("dispatch", target(rest))
        elif word == "check":
            checks.append(snapshot(n))
        elif word == "get":
            settled()
            words = [str(client_id(w[1:])) if w.startswith("@") else w for w in rest.split()]
            gets.append({"after_line": n, "answer": answer(json.loads(mmsg("get", *words)))})
        else:
            keys = keys or Input(layout)
            keys.step(word, rest)
        settled()
    json.dump({"mango": "0.18.5 (21f80a9)", "screens": sorted(screens(monitors), key=lambda s: given.index(s["name"])),
               "pointer": {"x": start["x"], "y": start["y"]}, "checks": checks, "gets": gets}, open(out, "w"), indent=1)
    if keys:
        keys.proc.kill()
    for w in windows.values():
        w.kill()
    mmsg("dispatch", "quit")


def check_config(path):
    """A config file of configs/: what `mango -c <file> -p` printed (its colours taken off) and its exit."""
    name = os.path.basename(path)
    run = subprocess.run(["/build/mango/build/mango", "-c", path, "-p"], capture_output=True, text=True, timeout=30)
    output = re.sub(r"\x1b\[[0-9;]*m", "", run.stderr)
    json.dump({"mango": "0.18.5 (21f80a9)", "exit": run.returncode, "output": output},
              open(f"/facit/configs/{name}.json", "w"), indent=1)
    print(f"{name}: exit {run.returncode}, {output.count('[ERROR]:')} errors, {output.count('[WARN]:')} warnings")


def record(scenario):
    name = os.path.splitext(os.path.basename(scenario))[0]
    config, _, monitors = parse(scenario)
    conf = f"/tmp/{name}.conf"
    open(conf, "w").write("\n".join(base_config(monitors) + config) + "\n")
    out = f"/facit/{name}.json"
    env = dict(os.environ, WLR_BACKENDS="headless", WLR_HEADLESS_OUTPUTS=str(monitors),
               XDG_RUNTIME_DIR="/tmp/xdg", WLR_LIBINPUT_NO_DEVICES="1",
               # scenefx draws with GLES: Mesa in software on vkms (drm-shim.c)
               WLR_RENDER_DRM_DEVICE="/dev/dri/card0", WLR_RENDERER_ALLOW_SOFTWARE="1",
               LD_PRELOAD="/tool/drm-shim.so")
    os.makedirs("/tmp/xdg", mode=0o700, exist_ok=True)
    if os.path.exists(out):
        os.remove(out)
    cmd = f"python3 {os.path.abspath(__file__)} --play {scenario} {out}"
    try:
        mango = subprocess.run(["/build/mango/build/mango", "-c", conf, "-s", cmd], env=env,
                               capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return print(f"{name}: TIMED OUT")
    if not os.path.exists(out):
        return print(f"{name}: NO FACIT\n{mango.stderr[-2000:]}")
    if "[ERROR]:" in mango.stderr:   # a config line mango refused: mangonag would move every window
        os.remove(out)
        return print(f"{name}: MANGO REFUSED THE CONFIG\n{mango.stderr[-2000:]}")
    print(f"{name}: {len(json.load(open(out))['checks'])} checks")


if __name__ == "__main__":
    if sys.argv[1] == "--play":
        play(sys.argv[2], sys.argv[3])
    else:
        for s in sys.argv[1:]:
            check_config(s) if s.endswith((".conf", ".toml")) else record(s)
