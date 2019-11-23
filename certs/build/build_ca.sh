#!/bin/bash

# build_ca.sh [-nodes]
#
# Create a new CA in the ./CA directory
#
# Default to requiring a passphrase to access it.
#
#  -nodes : don't protect CA with a passphrase
#

export OPENSSL_CONF=./ca.conf

if [ -f $OPENSSL_CONF ] ; then
    echo "Config file found"
else
    echo "No config file found. Are you in the certs/build dir?";
    exit 1
fi

if [ -d ./CA ]; then
    echo "You already have a CA directory."
    echo "Bailing so as not to overwrite any keys"
    exit 1;
fi

echo "About to create a new CA"
nodes=
if [ "x-nodes" == "x$1" ]; then
    nodes="-nodes"
    echo "-nodes option passed, so no phassphrase will be used"
else
    echo "Enter a strong passphrase when prompted below"
fi

# Create required files
# These names should match up with those found in ./ca.conf
mkdir -m 0700 ./CA
mkdir -m 0700 ./CA/new_certs
touch ./CA/index.txt
echo "0001" > ./CA/serial

openssl req $nodes -x509 -out CA/CA_self_signed_cert.pem -newkey rsa:2048 -days 1400
