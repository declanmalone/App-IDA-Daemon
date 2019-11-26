#!/usr/bin/env perl              # -*- perl -*-

use Mojo::Base -strict;

use FindBin qw($Bin);

use lib "$Bin/../lib";
use lib "$Bin/../lib/App/Cluster/Ida";

use Test::More;
use Test::Mojo;

use Mojo::Server::Daemon;

use v5.20;
use feature 'signatures';
no warnings 'experimental::signatures';
use Carp;

use Socket;

# Test mutual SSL authentication and allowed clients

# Most of the testing of the daemon (in other test scripts) won't use
# SSL mutual authentication since we can achieve security by telling
# the daemon to listen on a private unix domain socket instead.
#
# However, I still need to test that mutual SSL authentication is
# actually working correctly, so all tests related to that are stored
# here.
#
# I also test connecting to the / http(s) route. This route may not
# actually have any functionality for a while (or ever) since the main
# way to control the daemon will be via the websocket interface. In
# any event, I'll also test to make sure that the https interface is
# secure, too.

# The following test certs should be installed in certs/test:
#
# ca_cert.pem      A self-signed CA cert
# ca_key.pem       CA private key (signs all other certs)
# server_cert.pem  Server cert, signed by our CA ('authserver.lan')
# server_key.pem   Server private key
# client_cert.pem  Client cert ('localhost.lan', authorised to log in)
# client_key.pem   Client private key
# other_cert.pem   Sample cert that we haven't authorised to log in
# other_key.pem    Private key for same
#
# If these are missing or have expired, use the tools in certs/build
# to create new ones. Instructions are included in test_certs.md

my $ca =     "$Bin/../certs/test/ca_cert.pem";
my $s_cert = "$Bin/../certs/test/server_cert.pem";
my $s_key  = "$Bin/../certs/test/server_key.pem";
my $c_cert = "$Bin/../certs/test/client_cert.pem";
my $c_key  = "$Bin/../certs/test/client_key.pem";
my $o_cert = "$Bin/../certs/test/other_cert.pem";
my $o_key  = "$Bin/../certs/test/other_key.pem";

# Bail on testing if host aliases aren't set up
my $skipping = 0;
for my $hostname ("localhost.lan", "authserver.lan") {
    print "Checking $hostname: ";
    my $packed_ip = gethostbyname($hostname);
    if (defined($packed_ip)) {
	print inet_ntoa($packed_ip) . "\n"
    } else {
	print "Not found\n";
	++$skipping;
    }
}
if ($skipping) {
    warn <<"HELP";

One or more hostnames were not set up; skipping tests.
Please ensure that the following aliases for 'localhost'
are set up in /etc/hosts so that we can use the test
certs:

127.0.0.1 localhost.lan
127.0.0.2 authserver.lan

HELP
    plan skip_all => 'Need localhost aliases to test web certs';
    exit;
}

#
# This is a rewrite of a previous version of this test script.
# Previously, I was creating the test app object with:
#
# my $t = Test::Mojo->new('App::IDA::Daemon', $app_options);
#
# I was also making calls to set the default behaviour of SSL sockets,
# eg:
#
# IO::Socket::SSL::set_defaults( 
#   SSL_ca_file => $ca_file,    # set up trusted CA
#   mode => SSL_VERIFY_PEER,    # mutual authentication
# );
#
# However, when testing, these calls apply to both the program being
# tested and the test script, since they are both in the same process.
#
# I'm rewriting to use a cleaner way of doing this:
#
# * server has ca=.../ca_cert and verify=1 options
# * create server with Mojo::Server::Daemon->new()
#
# In this way, the server (the app being tested) and the client (ua in
# the test script) have separate SSL socket options, even though
# they're running in the same process/event loop.
#
# However, Test::Mojo->new lets us pass a config to the application,
# and I want to keep this feature. I do that when building the app,
# before passing it to Mojo::Server::Daemon->new()

# build_server is based on Test::Mojo->new() but:
#
# * creates a Mojo::Server::Daemon, with parameters
# * reads server listen parameters as a hash
# * only supports build_app (full Mojolicious app), not load_app
#

# break out conversion of server listen opts to string
sub listen_string ($hash) {
    my @keys = keys %$hash;
    die "missing required {listen}->{rendez} option"
        unless my $rendez = $hash->{rendez};
    my $listen_string = "$rendez?" . join '&', map {
        $_ eq 'rendez' ? () : ("$_=$hash->{$_}")
    } @keys;
    $listen_string;
}
sub build_server ($sopts, $appname, $opts) {
    my $listen = $sopts->{listen};
    my $server;
    if (ref $listen eq 'HASH') {
        my %splice_opts = (     # don't clobber original sopts
             %$sopts,
             # only handles a single listen string
             listen => [ listen_string($listen) ],
        );
        $server = Mojo::Server::Daemon->new(%splice_opts);
    } else {
        # don't attempt conversion otherwise
        $server = Mojo::Server::Daemon->new($sopts);
    };

    # make a config structure
    my @args = ();
    @args = ( config => { config_override => 1, %$opts } ) 
        if ref $opts eq 'HASH';
    $server->build_app($appname, @args) or die;
    $server->start;
    return $server;
}

# Test out build_server
my $app;
eval { $app = build_server ({listen => {}}, 'App::IDA::Daemon') };
croak "build_server: requires rendez?" unless $@;
croak "build_server: listen string?" unless
    listen_string({
        rendez => 'https://*:9001', verify => 1, })
    eq "https://*:9001?verify=1";

my $app_options;


# This script will test four specific ways of setting up a server:
#
# 1. insecure http listening on a port
# 2. secure   http listening on a private unix domain socket
# 3. insecure https listening on a port with server-only authentication
# 4. secure   https listening on a port with mutual authentication

# 1. insecure http listening on a port
my ($t,$ua,$server,$ioloop,$port,$rendez);
$ioloop  = Mojo::IOLoop->singleton;
$port    = Mojo::IOLoop::Server->generate_port;
$rendez  = "http://authserver.lan:$port";
my @key_args = ();
my $verify = 0;
    
$app_options = {
    proto => "http",
    auth_mode => "none",
    auth_cns  => {  # ignored if not doing mutual auth
	"localhost.lan" => "yes"
    }
};
$server = build_server(
    {
        listen => {
            rendez => $rendez,
            verify => $verify,
	    @key_args,
        },
        ioloop => $ioloop,
    },
    'App::IDA::Daemon', $app_options);
$t = Test::Mojo->new;

say "GET $rendez/";
$t->ua(Mojo::UserAgent->new(
           ioloop => $ioloop,
           ca     => $ca,
       ));
$t->get_ok("$rendez/")->status_is(200)
    ->content_like(qr/Mojolicious/i);

$t->websocket_ok("$rendez/sha")->status_is(101);

#done_testing; exit;

# 2. secure   http listening on a private unix domain socket

unlink "/tmp/ida_daemon.sock" if -f "/tmp/ida_daemon.sock";
umask 077;      # make socket only accessible to us

$rendez  = "http+unix://%2Ftmp%2Fida_daemon.sock";
$app_options = {
    proto => "http",
    auth_mode => "none",
};
$server = build_server(
    {
        listen => {
            rendez => $rendez,
            verify => $verify,
	    @key_args,
        },
        ioloop => $ioloop,
    },
    'App::IDA::Daemon', $app_options);
$t = Test::Mojo->new;

say "GET $rendez/";
$t->ua(Mojo::UserAgent->new(
           ioloop => $ioloop,
           ca     => $ca,
       ));
$t->get_ok("$rendez/")->status_is(200)
    ->content_like(qr/Mojolicious/i);

$t->websocket_ok("$rendez/sha")->status_is(101);


# 3. insecure https listening on a port with server-only authentication
$port    = Mojo::IOLoop::Server->generate_port;
$rendez  = "https://authserver.lan:$port";
$app_options = {
    proto => "https",
    auth_mode => "server",
    auth_cns  => {  # ignored if not doing mutual auth
	"localhost.lan" => "yes"
    }
};
@key_args = (
    ca     => $ca,
    key    => $s_key,
    cert   => $s_cert,
);
$server = build_server(
    {
        listen => {
            rendez => $rendez,
            verify => $verify,
	    @key_args,
        },
        ioloop => $ioloop,
    },
    'App::IDA::Daemon', $app_options);
$t = Test::Mojo->new;

say "GET $rendez/";
$t->ua(Mojo::UserAgent->new(
           ioloop => $ioloop,
           ca     => $ca,
       ));
$t->get_ok("$rendez/")->status_is(200)
    ->content_like(qr/Mojolicious/i);

$t->websocket_ok("$rendez/sha")->status_is(101);

#done_testing; exit;

# 4. secure   https listening on a port with mutual authentication
$port    = Mojo::IOLoop::Server->generate_port;
$rendez  = "https://authserver.lan:$port";
$verify = 1;
$app_options = {
    proto => "https",
    auth_mode => "mutual",
    auth_cns  => {  # ignored if not doing mutual auth
	"localhost.lan" => "yes"
    }
};

# Test three sub-cases:
#
# 4a. client doesn't provide cert
# 4b. client provides unauthorised cert
# 4c. client provides authorised cert

# All three use the same server. Only ua setup is different.
$server = build_server(
    {
        listen => {
            rendez => $rendez,
            verify => $verify,
	    @key_args,
        },
        ioloop => $ioloop,
    },
    'App::IDA::Daemon', $app_options);
$t = Test::Mojo->new;

# 4a. client doesn't provide cert
$t->ua(Mojo::UserAgent->new(
           ioloop => $ioloop,
           ca     => $ca,
       ));
$t->get_ok("$rendez/")->status_is(403)->content_like(qr/no client cert/i);

# don't use websocket_ok because that implies a successful handshake
$t->get_ok("$rendez/sha")->status_is(403);

# 4b. client provides unauthorised cert
$t->ua(Mojo::UserAgent->new(
           ioloop => $ioloop,
           ca     => $ca,
	   key    => $o_key,
	   cert   => $o_cert,
       ));
$t->get_ok("$rendez/")->status_is(403)->content_like(qr/not on the list/i);

# don't use websocket_ok because that implies a successful handshake
$t->get_ok("$rendez/sha")->status_is(403);

# 4c. client provides authorised cert
$t->ua(Mojo::UserAgent->new(
           ioloop => $ioloop,
           ca     => $ca,
	   key    => $c_key,
	   cert   => $c_cert,
       ));
$t->get_ok("$rendez/")->status_is(200)->content_like(qr/Mojolicious/);

$t->websocket_ok("$rendez/sha")->status_is(101);


done_testing;
