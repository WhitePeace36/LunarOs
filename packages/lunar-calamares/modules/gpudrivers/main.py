#!/usr/bin/env python3
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Lunar: installs the graphics drivers picked on the "Graphics" page
# (packagechooser_gpu: "auto" or "mesa") by running lunar-gpu-setup, from
# lunar-settings, inside the new system. Part of Lunar's installer.

import subprocess
import time

import libcalamares

_last_progress = 0


def pretty_name():
    return "Installing graphics drivers"


def _log(line):
    global _last_progress
    libcalamares.utils.debug("gpudrivers: " + line.rstrip())
    if time.time() - _last_progress > 0.5:
        libcalamares.job.setprogress(0)
        _last_progress = time.time()


def run():
    root = libcalamares.globalstorage.value("rootMountPoint")
    choice = libcalamares.globalstorage.value("packagechooser_gpu") or "auto"
    if choice not in ("auto", "mesa"):
        libcalamares.utils.warning("Unknown graphics choice {!s}, using auto".format(choice))
        choice = "auto"
    libcalamares.utils.debug("gpudrivers: choice {!s}".format(choice))

    command = ["arch-chroot", root, "/usr/bin/lunar-gpu-setup", "--choice", choice]
    proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            universal_newlines=True, bufsize=1)
    for line in proc.stdout:
        if line.strip():
            _log(line)
    proc.wait()

    if proc.returncode != 0:
        # Not fatal: Plasma pulls in Mesa anyway, so the system still starts
        # (on NVIDIA with nouveau). The driver can be installed after boot.
        libcalamares.utils.warning(
            "gpudrivers: lunar-gpu-setup failed (exit code {!s}); run "
            "'sudo lunar-gpu-setup' after the first boot".format(proc.returncode))
    return None
