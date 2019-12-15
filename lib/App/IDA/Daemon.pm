package App::IDA::Daemon;

our $VERSION = '0.01';

use v5.10;

use Mojo::Base 'Mojolicious';

use Mojo::IOLoop::Server;
use IO::Socket::SSL;

# This method will run once at server start
sub startup {
  my $self = shift;
  my $app = $self->app;

  # Find our commands
  push @{$self->commands->namespaces}, 'App::IDA::Daemon::Command';

  # Load configuration from hash returned by config file
  my $config = $self->plugin('Config' => { 
      file => "ida-daemon.conf"} );

  # Configure the application
  $self->secrets($config->{secrets});
  $self->{secure} = $config->{proto} // "" eq "https" ? 1 : 0;
  $self->{auth_mode} = $config->{auth_mode} // "server";

  # Router
  my $r = $self->routes;

  # Callback to debug SSL verify
  IO::Socket::SSL::set_defaults(
      callback => sub {
	  # say "Disposition: $_[0]";
	  # say "Cert store (C):<<$_[1]>>";
	  # say "Issuer/Owner:<<$_[2]>>";
	  say "Errors?: $_[3]";
	  say $_[0] ? "Accepting cert" : "Not accepting cert";
	  return  $_[0];
      });

  # SSL Mutual Authentication (requires a whitelist of auth'd cn's)
  $config->{auth_cns} = {} unless exists $config->{auth_cns};
  $r->add_condition(ssl_auth => sub {
      my ($route, $c, $captures, $num) = @_;

      my $id     = $c->tx->connection;
      my $handle = Mojo::IOLoop->stream($id)->handle;
      my $authorised_cns = $app->config->{auth_cns};

      if (ref $handle ne 'IO::Socket::SSL') {
          # Not SSL connection
          # if we get here, chances are that server hasn't
          # defined its web identity (cert, key).

          my $type = ref $handle;
          $c->render(text => "ref = $type (not IO::Socket::SSL)");
      } else {
          my $cn = $handle->peer_certificate('commonName');
          unless (defined $cn) {
              $c->render(status => 403, text => 'No client cert received');
          } elsif (exists $authorised_cns->{$cn}) {
              $c->stash(authorised => $cn);
              return 1;
              $c->render(text => 'Welcome! commonName matched!');
          } else {
              $c->render(status => 403, text => "You're not on the list, $cn!");
          }
      }
      return undef;
  });

  # Normal route to controller
  #  $r->get('/')->to('example#welcome');

  $app->{transactions}={};

  # Index page includes a simple JavaScript WebSocket client
  my $index =  $r->get('/')->to(template => 'index');
  $index->over('ssl_auth') if $self->{auth_mode} eq "mutual";

  # WebSocket service 
  my $sha = $r->websocket('/sha' => sub {
      my $c = shift;

      # Opened
      $c->app->log->debug('WebSocket opened');

      # Increase inactivity timeout for connection a bit
      $c->inactivity_timeout(300);

      # Incoming message
      $c->on(message => sub {
	  my ($c, $msg) = @_;
	  $c->app->log->debug("Got message $msg\n");

	  # Receiver side
	  if ($msg =~ /^RECEIVE (.*)$/) {
	      $msg = $1;
	      
	      if (exists($app->{transactions}->{$msg})) {
		  my $port = $app->{transactions}->{$msg}->{port};
		  $c->send("$msg: already running on port $port");
		  return;
	      }

	      my $server = Mojo::IOLoop::Server->new;
	      $server->on(accept => sub {
		  my ($server,$handle) = @_;
		  $c->app->log->debug("accepted connection");
		  $server->stop;	# only accept one connection
		  my $sum = Digest::SHA->new("sha1");
		  my $stream = Mojo::IOLoop::Stream->new($handle);
		  $stream->on(read => sub {
		      my ($stream,$data) = @_;
		      my $size = length($data);
		      $c->app->log->debug("read $size bytes");
		      $sum->add($data);
			      });
		  $stream->on(close => sub {
		      $c->app->log->debug("closing connection");
		      my $hex = $sum->hexdigest;
		      $c->send("$msg: $hex");
		      delete $app->{transactions}->{$msg};
			      });
		  $app->{transactions}->{$msg}->{stream}=$stream;
		  $stream->start;
			  });
	      $server->listen(port => 0);
	      my $port = $server->port;
	      $app->{transactions}->{$msg}->{port}=$port;
	      $app->{transactions}->{$msg}->{server}=$server;
	      $server->start;
	      
	      $c->send("Port $port ready to receive $msg");

	      # Sender side
	  } elsif ($msg =~ /^SEND (\d+) (.*)$/) {

	      my ($port, $file) = ($1,$2);
	      # Only allow sending of file in current directory
	      if ($file =~ m|^\./[^/]+$|) {
		  if (!open my $fh, "<", "$file") {
		      $c->send("No such file '$file'");
		  } else {
		      # IOLoop::Stream can read from a file, but not
		      # write to one!
		      my $client = Mojo::IOLoop::Client->new;
		      $app->{transactions}->{$file}->{client} = $client;
		      $client->on(connect => sub {
			  my ($client, $handle) = @_;
			  $c->app->log->debug("Sender connected to receiver");
			  my $istream = Mojo::IOLoop::Stream->new($fh);
			  my $ostream = Mojo::IOLoop::Stream->new($handle);
			  $app->{transactions}->{$file}->{istream} = $istream;
			  $app->{transactions}->{$file}->{ostream} = $ostream;
			  $ostream->start;
			  $istream->on(read => sub {
			      my ($istream,$data) = @_;
			      my $size = length($data);
			      $c->app->log->debug("sent $size bytes");
			      $ostream->write($data);
				       });
			  $istream->on(close => sub {
			      $ostream->close_gracefully;
				       });
			  $istream->start;
				  });
		      $client->on(error => sub {
			  my ($client, $err) = @_;
			  $c->send("Sender: Error connecting: $err");
				  });
		      $client->connect(address => 'localhost',
				       port => $port);
		      $client->reactor->start unless $client->reactor->is_running;
		      $c->send("Sender finished");
		  }
	      } else {
		  $c->send("Invalid filename '$file'");
	      }

	  } else {
	      $c->send("Invalid command!");
	  }
	     }
      );

      # Closed
      $c->on(finish => sub {
	  my ($c, $code, $reason) = @_;
	  $c->app->log->debug("WebSocket closed with status $code");
	     });
			  });

  $sha->over('ssl_auth') if $self->{auth_mode} eq "mutual";


}

1;

=head1 NAME

App::IDA::Daemon - Network daemon for IDA-based distributed storage

=head1 VERSION

Version 0.01

=cut

=head1 SYNOPSIS

This app runs as a Mojolicious daemon and provides a secure
WebSocket-based interface for carrying out low-level operations needed
to implement a distributed, fault-tolerant file storage system using
Rabin's Information Dispersal Algorithm (IDA).

This application uses L<Crypt::IDA> to split files into a set of
redundant shares and combine shares to get back the original file. It
also uses L<Crypt::IDA::ShareFile> to implement a simple file format
for storing shares. Please consult those modules for information about
what the Information Dispersal Algorithm (IDA) is, and to get an idea
of how it is used here.

Once set up on a number of network hosts (which could be NAS boxes,
desktops, servers, Single-Board Computers, Internet servers, etc.),
the daemon listens for https/websocket connections and allows an
authorised client to send low-level commands related to:

=over

=item * splitting files (aka "replicas") into shares

=item * combining some number of shares to recover a replica

=item * storage/retrieval of shares on a local disk (aka "a silo")

=item * encrypted transfer of replicas/shares to other nodes in the network

=item * streaming upload/download of replicas

=item * basic file metadata, including SHA hashes

=back

This daemon is only concerned with carrying out split/combine
operations, shipment of shares and replicas across the network, and
for checking the integrity of stored data. It doesn't implement any
higher-level features that you would expect of a network-based file
storage system.

=head1 PROGRAM ORGANISATION

Broadly speaking, the program can be divided into the following
functional components:

=over

=item * web server interface

Implemented as a L<Mojolicious> application. Provides the
WebSocket interface.

This can be accessed via https/wss, in which case it uses mutual SSL
authentication to secure the connection, or over a local Unix domain
socket, in which case security is enforced by permissions on the
socket itself.

See L<App::IDA::Daemon> (this file).

=item * WebSocket/JSON command dispatcher

A Mojolicious Controller to handle dispatching JSON-based commands.

See L<App::IDA::Daemon::Controller::Dispatcher>.

=item * Asynchronous Stream Processing Pipelines

Provides a set of abstractions for building up arbitrary stream
processing pipelines that work with L<Mojo::IOLoop> and
L<Mojo::IOLoop::Stream>. These follow the Source-Filter-Sink pattern
and allow for asynchronous processing to happen concurrently with the
web server event loop.

See L<App::IDA::Daemon::Link> and L<App::IDA::Daemon::Chain> for more
details.

=item * A suite of "processing elements"

Subclasses of Link that do different kinds of processing on data
streams. For example:

=over

=item * Create one or more IDA shares from a file

=item * Combine shares to get back a file

=item * Calculate a SHA hash of a data stream

=item * Upload/Download on a socket connection

=item * Encrypt/Decrypt a stream

=back

=back


=head1 CONFIGURATION

All configuration is done via the C<ida-daemon.conf> configuration
file. A sample configuration file named C<sample-ida-daemon.conf> is
provided in the CPAN source distribution.

By default, the configuration file will be searched for in (TODO:where?).

Some tools are available in the C<certs/build> directory of the
distribution for creating (self-signed) public keys, private keys and
certificates required for TLS/SSL. Or you can provide your own or use
those provided by a commercial entity.

=head2 Configure node's TLS/SSL certificate

This is handled by the web server side of things, so refer to
Mojolicious documentation for configuring this, as well as other
server setup such as the port to listen on.

If you are using hypnotoad, then its configuration can be stored
within this app's configuration file. A sample stanza might look like:

    hypnotoad => {
        listen  => ['https://*:3443?' .
                    'ca=/home/mojo/certs/ca_cert.pem&' .
                    'key=/home/mojo/certs/key.pem&' .
                    'cert=/home/mojo/certs/cert.pem'],
        workers => 4
    },

where 'key' and 'cert' are the private and public SSL keys for this
node.

=head2 Configure for mutual TLS/SSL authentication/authorisation

If you are using hypnotoad or another Mojolicious-based server, your
server configuration should include C<verify=1> in order for the
server to check the client's credentials during the TLS
handshake. Also, if the issuer of the client's SSL credentials is not
known to the server (eg, if you are using self-signed certificates),
you will also need to add a C<ca=/path/to/ca.cert> option to add that
Certificate Authority to the list of known CAs.

=head1 INSTALLATION

If you don't intend to modify this code, but just use it as-is, simply
follow the configuration instructions above.

If you do want to tailor the code or add features, or if you want to
deploy it on a large number of hosts, you may wish to use the included
Git "push-to-deploy" script. This exploits git's hooks feature that
lets you run custom code when updates to a repository are pushed from
another repository, and the zero-downtime feature of Mojolicious's
hypnotoad server that lets it restart the app when a new version
becomes available.

Some initial setup is required before this can be used to push the
latest version of the app to a node. If you're deploying to many
nodes, these steps can all be scripted using whatever combination of
tools you like (eg, plain ssh, rsync, scp, NSF, sshfs, GRID::Machine,
IPC::PerlSSH, etc.).

=over

=item 1. Create your central git clone of the repo

This could be on your development machine or on some other machine
that you will use to manage deployment to all nodes.

 $ cd ~/src
 $ git clone https://github.com/declanmalone/App-IDA-Daemon

From here on, I will assume that you have ssh access from this machine
to all the nodes that will be set up.

=item 2. Set up git repo on the new node

On the new node, create a new bare git repo

 $ ssh mojo@mercury
 Welcome to mercury!
 $ git init --bare App-IDA-Daemon.git
 $ logout

On the central node, create a new git remote for the node:

 $ cd ~/src/App-IDA-Daemon
 $ git remote add mercury 'ssh://mojo@mercury:/home/mojo/App-IDA-Daemon.git'

Now push the repo across:

 $ git push --mirror mercury

=item 3. Create the install directory

Log back onto the new node:

 $ ssh mojo@mercury
 Welcome to mercury!
 $ cd /home/mojo
 $ mkdir App-IDA-Daemon     # default install location
 $ cd App-IDA-Daemon.git    # cd into bare repo
 $ GIT_WORK_TREE=../App-IDA-Daemon git checkout -f master

The last line simply checks out the source rather than creating a full
git clone.

=item 4. Create the configuration file for this node

 $ cd /home/mojo/App-IDA-Daemon
 $ vi app-ida-daemon.conf
 $ mkdir certs
 $ cp /location/of/certs/* certs

=item 4. Install push-to-deploy script

 $ cd /home/mojo
 $ cp ./App-IDA-Daemon/deploy/post-receive \
      ./App-IDA-Daemon.git/hooks

=back

All of the defaults mentioned above (user and directory names) are in
the C<deploy/post-receive> script, so you can change them there to
suit your setup.

After all of these steps have been done, whenever you check in a
change to the code and have tested it, you can call 'git push
<remote>'. This will push the changes to the given remote, and the
C<post-receive> script there will automatically check out the changes
and instruct a running hypnotoad server to do a zero-downtime
upgrade. Alternatively, if a server isn't already running, the script
will start a new one.

=head1 AUTHOR

Declan Malone, C<< <idablack at users.sourceforge.net> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2019 Declan Malone.

This program is released under the following license: perl,lgpl,artistic2


=cut

1; # End of App::IDA::Daemon
