#!/usr/bin/env python3
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Lunar installer: installs the base system with Arch's pacstrap into the
# mounted target, from Arch's repositories and the [lunar] repository.
#
# Configuration (pacstrap.conf):
#   pacmanConf       pacman.conf used for the install and copied to the target
#   basePackages     packages for every installation
#   postInstallFiles files copied from the live system into the target
#
# Added from the installer's choices and the hardware:
#   linux-lunar + linux-lts (with headers, for DKMS drivers)
#   intel-ucode or amd-ucode

import os
import re
import shutil
import subprocess

import libcalamares

KERNELS = ["linux-lunar", "linux-lunar-headers", "linux-lts", "linux-lts-headers"]
_progress_re = re.compile(r"\((\s*\d+)/(\s*\d+)\)")


def pretty_name():
    return "Installing the base system"


def _microcode():
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.startswith("vendor_id"):
                    return "intel-ucode" if "GenuineIntel" in line else "amd-ucode"
    except OSError as e:
        libcalamares.utils.warning("pacstrap: can't read /proc/cpuinfo: {!s}".format(e))
    return None


def _run(command):
    """Run a command on the live system, log its output, map pacman's
    (n/total) counters to the progress bar."""
    libcalamares.utils.debug("pacstrap: running {!s}".format(" ".join(command)))
    proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            universal_newlines=True, bufsize=1)
    for line in proc.stdout:
        line = line.rstrip()
        if not line:
            continue
        libcalamares.utils.debug("pacstrap: " + line)
        m = _progress_re.search(line)
        if m and "installing" in line:
            done, total = int(m.group(1)), int(m.group(2))
            if total > 0:
                libcalamares.job.setprogress(min(0.95, done / total))
    proc.wait()
    return proc.returncode


def run():
    conf = libcalamares.job.configuration
    root = libcalamares.globalstorage.value("rootMountPoint")
    if not root:
        return ("No target mounted", "The partition step did not mount a target system.")

    pacman_conf = conf.get("pacmanConf", "/usr/share/lunar-calamares/pacman.conf")
    packages = list(conf.get("basePackages", []))
    packages += KERNELS

    ucode = _microcode()
    if ucode:
        packages.append(ucode)

    # a reused EFI partition may still hold microcode images from another system
    for img in ("intel-ucode.img", "amd-ucode.img"):
        path = os.path.join(root, "boot", img)
        if os.path.isfile(path):
            os.remove(path)

    # -C: Lunar's repo setup; the live system's ranked mirrorlist and keyring
    # are copied into the target by pacstrap itself
    rc = _run(["pacstrap", "-C", pacman_conf, root] + packages)
    if rc != 0:
        return ("The base system could not be installed",
                "pacstrap failed (exit code {!s}). Check the internet connection "
                "and the log in /home/liveuser/.cache/calamares/session.log.".format(rc))

    shutil.copy2(pacman_conf, os.path.join(root, "etc", "pacman.conf"))
    # DNS for the remaining steps that download packages inside the target
    if os.path.exists("/etc/resolv.conf"):
        target_resolv = os.path.join(root, "etc", "resolv.conf")
        if os.path.islink(target_resolv):
            os.remove(target_resolv)
        shutil.copy2("/etc/resolv.conf", target_resolv)

    for item in conf.get("postInstallFiles", []):
        src, dst = item["from"], item["to"]
        target = os.path.join(root, dst.lstrip("/"))
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(src, target)
        libcalamares.utils.debug("pacstrap: copied {!s} -> {!s}".format(src, dst))

    libcalamares.job.setprogress(1.0)
    return None
