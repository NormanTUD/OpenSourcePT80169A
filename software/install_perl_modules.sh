#!/bin/bash

if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root" 
	exit 1
fi

apt-get -y install make build-essential libimage-magick-perl || exit 1

cpan -i Business::ISBN || exit 1
cpan -i String::ShellQuote || exit 1
cpan -i JSON::Parse || exit 1
cpan -i Device::SerialPort || exit 1
cpan -i Image::Size || exit 1
cpan -i Data::Compare || exit 1
