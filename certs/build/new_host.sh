#!/bin/bash

nodes=""			# don't use password on private key
if [ "x$1" == "x-nodes" ] ; then
    nodes="-nodes"
    shift
fi
host=$1

# We need to use existing CA to sign our cert
CA_CONF=./ca.conf
if [ ! -d ./CA ]; then
    echo "Error: ./CA dir is missing"
    echo "make sure that you are in the certs/build dir"
    echo "or run ./build_ca.sh [-nodes] to create a new CA"
    exit 1
fi

# host option required
if [ "x" == "x$host" ]; then
    echo "Usage: $0 [-nodes] fully-qualified-hostname"
    exit 1
fi

# Make sure that hostname is fully-qualified
nodots=`echo $host | sed -e 's/\.//g'`
if [ "$nodots" == "$host" ]; then
    echo "supplied hostname was not fully-qualified (eg, localhost.lan)"
    exit 1
fi

# Try not to clobber existing keys/conf files.
# 
HOST_CONF=./"$host".conf

if [ -d $host ]; then
    echo Directory "$host" already exists. Bailing
    exit 1
fi

if [ -f $HOST_CONF ] ; then
    echo "Existing file '$HOST_CONF' found. Bailing."
    exit 1
fi

echo Creating directory "$host"
echo "Generating '$HOST_CONF' from template"

mkdir "$host"
sed -e "s/FQDN_HOSTNAME/$host/" <host.template > "$HOST_CONF"

# The following generates:
# * private key
# * certificate signing request (includes public key)

echo If prompted, enter the new password for $host\'s key

export OPENSSL_CONF=$HOST_CONF
openssl req $nodes -out $host/csr.pem -newkey rsa:2048\
            -keyout $host/private_key.pem


# Now, use previous CA config to sign the cert

echo If prompted, enter the CA\'s passphrase!

export OPENSSL_CONF=$CA_CONF
#openssl ca -in ~/myCertificates/localhost/localhostCsr.pem -out ~/myCertificates/localhost/localhostCertificate.pem
openssl ca -in $host/csr.pem -out $host/signed_cert.pem
