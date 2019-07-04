# OpenSourcePT80169A
This is the software needed to create an automated Book-scanner from a PageTurner Readable+ PT80169A.

It consists of two parts, the code for an Arduino controlling this device, and the software controlling the Arduino, the page turner, enabling auto-OCR etc.

# Installation

To install everything that's needed, run

sudo apt-get install ino

sudo bash ./software/install_perl_modules.sh

sudo perl ./software/control.pl

Please make sure, you're using the latest Version of tesseract (uninstall, if not 5.0 alpha or higher, and then run control.pl to install the latest version automatically).

# Wiring plans

As of now, there are no wiring plans except some information in the ./hardware/src/sketch.ino.

# Running the software

After installing everything, you can run the software with

perl ./software/control.pl --help

for seeing what options are available.

You can also run

perl ./software/control.pl --test

or, even better,

perl ./software/control.pl --test --debug

to test most components.

# How it looks like

https://www.youtube.com/watch?v=qbCuyI71ms4

There's a video of how this device looks like in action.

# License

The software is licensed under the WTFPL. So, practically, you can do anything you want with it.
