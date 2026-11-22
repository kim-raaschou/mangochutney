/*
 * Not mango: what lets mango draw in the recorder. scenefx opens only DRM render nodes, and render
 * nodes may not make the dumb buffers Mesa draws into in software (kms_swrast). The recorder has
 * vkms, a primary node: this tells scenefx it is a render node. Nothing of mango's logic sees it.
 */
#include <xf86drm.h>

int drmGetNodeTypeFromFd(int fd) { return DRM_NODE_RENDER; }
