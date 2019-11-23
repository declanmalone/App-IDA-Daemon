# Building certs for running tests

The following test certs should be installed in certs/test:

ca_cert.pem
: A self-signed CA cert
ca_key.pem
: CA private key (signs all other certs)
server_cert.pem
: Server cert, signed by our CA (server's FQDN)
server_key.pem
: Server private key
client_cert.pem
: Client cert ('localhost.lan', authorised to log in)
client_key.pem
: Client private key
other_cert.pem
: Sample cert that we haven't authorised to log in
other_key.pem
: Private key for same

The remainder of this document shows how to create these, or other CAs
or certs/keys.

## Create Certificate Authority

A Certificate Authority (CA) is a trusted public/private key pair that
signs certificates for web servers, mostly. It can also be used to
sign client certificates for mutual SSL authentication between a web
server and a client.

Run the following to remove any existing CA and build a new one:

    cd certs/build              # get to this directory
    rm -rf CA                   # remove any old CA files
    vi ca.conf                  # peruse options
    ./build_ca.sh -nodes        # create new CA without passphrase
    cp CA/CA_self_signed_cert.pem ../test/ca_cert.pem

The `-nodes` option to `build_ca.sh` doesn't protect the new CA with a
passphrase. This is fine for creating certs for testing, but if you're
using the script to make certs that you will deploy on the web, you
should not use this option.

## Set up host names/aliases in /etc/hosts

A web cert is issued for a particular *host name* (called the "common
name" in SSL jargon). This should be a fully-qualified domain name
(FQDN), eg `localhost.lan` instead of just `localhost`.

You may need to update your /etc/hosts or DNS server so that your
hosts include fully-qualified names/aliases. For example:

    127.0.0.1       localhost localhost.lan

If you're using a local hosts file, you can also make up new aliases
for your local host. That way you can create separate certs for each
alias. For example, you could write:

    127.0.0.2       authserver authserver.lan
    127.0.0.3       developer developer.lan

If you want to access these from remote sites, you will have to update
the hosts/DNS across all those sites. You must list the actual IP
address of the host you want to connect to, eg:

    192.168.2.86    authserver.lan developer.lan

These steps can be done after creating certs if you wish, since the
scripts here don't do any DNS lookups to make sure that the host name
is valid.

## Create server credentials for your server

This sets up a signed cert for a server named `authserver.lan` and
installs it in the right place in the test directory.

    ./new_host.sh -nodes authserver.lan    # or your real hostname
    cp authserver.lan/signed_cert.pem ../test/server_cert.pem
    cp authserver.lan/private_key.pem ../test/server_key.pem

## Create credentials for authorised and unauthorised clients

Some test scripts perform an authorisation check after the client and
server have authenticated each others' certs. They do this by checking
the host name of the certificate.

Here we create an authorised client cert:

    ./new_host.sh -nodes localhost.lan
    cp localhost.lan/signed_cert.pem ../test/client_cert.pem
    cp localhost.lan/private_key.pem ../test/client_key.pem
 
And here is an unauthorised one (the host name does not matter, and
there is no need to make a DNS/hosts entry for it):

    ./new_host.sh -nodes unauthorised.net
    cp unauthorised.net/signed_cert.pem ../test/other_cert.pem
    cp unauthorised.net/private_key.pem ../test/other_key.pem

## Complete!

All the test scripts should now have all they need for secure HTTPS
network communication.