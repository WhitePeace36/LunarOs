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
#   linux-lunar-v3 on CPUs with x86-64-v3 (AVX2), else linux-lunar,
#   + linux-lts (all with headers, for DKMS drivers)
#   intel-ucode or amd-ucode

import os
import re
import shutil
import subprocess

import libcalamares

FALLBACK_KERNELS = ["linux-lts", "linux-lts-headers"]
# CPU flags x86-64-v3 needs (psABI levels v2 + v3; lzcnt is "abm" in cpuinfo)
X86_64_V3_FLAGS = {"cx16", "lahf_lm", "popcnt", "sse4_1", "sse4_2", "ssse3",
                   "avx", "avx2", "bmi1", "bmi2", "f16c", "fma", "abm", "movbe", "xsave"}
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


def _has_x86_64_v3():
    """True if this CPU (and the OS, for AVX state) supports x86-64-v3.
    glibc's loader runs the exact psABI check; /proc/cpuinfo is the fallback."""
    try:
        out = subprocess.run(["/usr/lib/ld-linux-x86-64.so.2", "--help"],
                             capture_output=True, text=True, timeout=10).stdout
        for line in out.splitlines():
            line = line.strip()
            if line.split(" ", 1)[0] == "x86-64-v3":
                return "supported" in line
    except (OSError, subprocess.SubprocessError) as e:
        libcalamares.utils.warning("pacstrap: ld.so --help failed: {!s}".format(e))
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.startswith("flags"):
                    return X86_64_V3_FLAGS <= set(line.split(":", 1)[1].split())
    except OSError as e:
        libcalamares.utils.warning("pacstrap: can't read /proc/cpuinfo: {!s}".format(e))
    return False


def _kernels():
    lunar = "linux-lunar-v3" if _has_x86_64_v3() else "linux-lunar"
    libcalamares.utils.debug("pacstrap: kernel {!s}".format(lunar))
    return [lunar, lunar + "-headers"] + FALLBACK_KERNELS


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
    packages += _kernels()

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
                "and the log in /home/liveuser/lunar-install.log.".format(rc))

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
