---
title: Coming from macOS
description: A first week with a tiling window manager, one step at a time.
---

On a normal Mac you place every window yourself. A tiling window manager does it for you: each
new window takes a place next to the others, and when one closes the rest fill the space. It
takes a few days to get used to. You do not need to learn it all at once, and the mouse keeps
working the whole time.

The keys below are mango's defaults. **Hyper K** (⌃⌥⌘K) lists every key and lets you search for
one by what it does, so when you forget a key, search for "float" or "tag".

## 1. Let it place your windows

Open three or four windows and watch them line up. The default layout, tile, puts one large window
on the left and stacks the others on the right.

Try:

- **⌘ N** goes to the next layout. Press it a few times.
- **Hyper L** shows the layouts as icons. Pick one with the arrows and Return.
- **The menu bar item** has the same layouts, plus gaps and borders, to change with the mouse.

## 2. Move around with the keys

| Keys | Does |
|---|---|
| ⌥ ← ↑ → ↓ | focus the window in that direction |
| ⌘ ⇧ ← ↑ → ↓ | move the window that way |
| ⌥ Q | close the window |

Holding ⌘ and dragging moves a window with the mouse. Right-drag resizes it.

## 3. Tags

Tags are like desktops that are always there. Every screen has nine, and each tag keeps its own
layout. Put your mail on one, your editor on another.

| Keys | Does |
|---|---|
| ⌃ 1–9 | go to a tag |
| ⌥ 1–9 | send the window to a tag |
| ⌃ ← / → | the previous or next tag that has windows |

They do not use macOS Spaces, so you can leave Spaces as they are.

## 4. When a window should not be tiled

Some windows are better left alone: a calculator, a settings window, a video.

| Keys | Does |
|---|---|
| ⌥ \ | float the window, or tile it again |
| ⌥ A | maximize |
| ⌥ F | fullscreen |
| ⌘ O | keep it on top |
| ⌘ G | show it on every tag |

Dialogs open floating by themselves.

## 5. Put things away

The scratchpad is a place to put windows you need now and then, such as a terminal or notes.

| Keys | Does |
|---|---|
| ⌘ I | send the window to the scratchpad |
| ⌥ Z | show or hide the scratchpad |
| ⌘ ⇧ I | take the window back |

## 6. Find a window

- **⌥ Tab** puts a letter on every window. Press the letter to go there.
- **Swipe up with four fingers** for the overview: all your windows, side by side.
- **Hyper K** also lists your open windows. Type part of a title.

## 7. Move the keys to Hyper

After a while you will notice that some of mango's keys are also Mac shortcuts: ⌘ ← no longer goes
to the start of a line, ⌥ with a letter no longer types a character, and ⌘ M quits Mango Chutney.

The fix is a Hyper key: one key that means ⌃⌥⌘ held together. With
`xkb_rules_options=caps:hyper` Caps Lock becomes Hyper, and mango's keys can move there, out of the
way of your apps. If you chose macOS's keys on the first start, this is already done. Otherwise the
[guide](../guide.md#the-hyper-key) explains how.

## Next

- [Coming from AeroSpace](from-aerospace) has a list of things to try once the basics feel
  normal.
- [mango's documentation](https://mangowm.github.io/docs) describes every layout and option.
