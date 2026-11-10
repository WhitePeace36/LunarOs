/* Lunar installer slideshow (text only, no image assets needed).
 *
 *   SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick 2.15
import calamares.slideshow 1.0

Presentation
{
    id: presentation

    Timer {
        interval: 20000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    component LunarSlide: Slide {
        id: slide
        property string heading
        property string body
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: "#0d1626"
        }
        Image {
            id: moonLogo
            source: "logo.png"
            width: 120; height: 120
            fillMode: Image.PreserveAspectFit
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.10
        }
        Text {
            id: headingText
            text: slide.heading
            color: "#eaf4ff"
            font.pixelSize: 30
            font.bold: true
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: moonLogo.bottom
            anchors.topMargin: 24
        }
        Text {
            text: slide.body
            color: "#b8d6f5"
            font.pixelSize: 17
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            width: parent.width * 0.7
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: headingText.bottom
            anchors.topMargin: 18
        }
    }

    LunarSlide {
        heading: "Welcome to Lunar"
        body: "KDE Plasma on Arch Linux with the linux-lunar kernel, tuned for smooth frame times. Sit back while the system is installed."
    }
    LunarSlide {
        heading: "Elara + ananicy-cpp"
        body: "The Elara sched_ext scheduler gives games, audio and the desktop the CPU time they need, using the priorities ananicy-cpp assigns to every program."
    }
    LunarSlide {
        heading: "Tuned for desktops"
        body: "Lunar's kernel parameters, sysctl and memory settings favour low latency and smooth frame times. They all live in /usr/lib and can be overridden with your own files in /etc."
    }
    LunarSlide {
        heading: "Ready for games"
        body: "Steam, Lutris, ProtonUp-Qt and MangoHud are installed. NVIDIA cards get the newest driver that supports them on Wayland."
    }
    LunarSlide {
        heading: "Safe by default"
        body: "The firewall blocks incoming connections, except LocalSend for sharing files with your other devices. Printers on the network are found automatically."
    }

    function onActivate() { presentation.currentSlide = 0 }
    function onLeave() { }
}
