#!/usr/env/perl

use Mojo::Base -strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Test::More;
use Test::Mojo;

use Mojo::Promise;
use Mojo::IOLoop;

# This file is deprecated.
#
# I'm refactoring the modules tested (*P.pm) here to inherit from
# App::IDA::Daemon::Link and use roles to encapsulate common
# behaviour.
#
# The functionality of the new classes should all be similar to the
# versions tested here, so I'll gradually move/port what's here over
# to roles.t

# -------------------------------------------------------------------

# Does high-level functionality testing on promise-based processing
# pipelines.
#
# The various promise-based Sources, Filters and Sinks don't have much
# in the way of callable methods, so there's not much unit testing we
# can do. I will do a little bit, such as verifying that any sample
# code included in the POD runs correctly.

# Unit Test App::IDA::Daemon::StringSourceP

use_ok("App::IDA::Daemon::StringSourceP");

my $lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit,
sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut
enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi
ut aliquip ex ea commodo consequat. Duis aute irure dolor in
reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla
pariatur. Excepteur sint occaecat cupidatat non proident, sunt in
culpa qui officia deserunt mollit anim id est laborum.\n";

my $sed = "Sed ut perspiciatis unde omnis iste natus error sit
voluptatem accusantium doloremque laudantium, totam rem aperiam, eaque
ipsa quae ab illo inventore veritatis et quasi architecto beatae vitae
dicta sunt explicabo. Nemo enim ipsam voluptatem quia voluptas sit
aspernatur aut odit aut fugit, sed quia consequuntur magni dolores eos
qui ratione voluptatem sequi nesciunt. Neque porro quisquam est, qui
dolorem ipsum quia dolor sit amet, consectetur, adipisci velit, sed
quia non numquam eius modi tempora incidunt ut labore et dolore magnam
aliquam quaerat voluptatem. Ut enim ad minima veniam, quis nostrum
exercitationem ullam corporis suscipit laboriosam, nisi ut aliquid ex
ea commodi consequatur? Quis autem vel eum iure reprehenderit qui in
ea voluptate velit esse quam nihil molestiae consequatur, vel illum
qui dolorem eum fugiat quo voluptas nulla pariatur?\n";



my $stream = App::IDA::Daemon::StringSourceP
    ->new("My String");

# read string 3 bytes at a time
my ($output,$data,$eof) = ("","",0);
until ($eof) {
    $stream->read_p(0,3)->then(
	sub {
	    ($data,$eof) = @_;
	    $output .= $data;
	})->catch(
	sub {
	    my $err = shift;
	    die "Stream died with error '$err'\n"; 
	})->wait;
}

is($output, "My String", "\$output eq 'My String'?");

# A few more unit tests that we can do
$stream = App::IDA::Daemon::StringSourceP
    ->new("My String");
my $got_err = "";
my $got_data = "";
$eof = 0;

$stream->read_p(1,3)->catch( sub { $got_err = shift })->wait;
ok($got_err, "Caught invalid port");

$stream->read_p(0,-1)->catch( sub { $got_err = shift })->wait;
ok($got_err, "Caught invalid bytes");

# Test explicit wait
$stream->read_p(0,1)->then( sub { ($got_data,$eof) = @_ })->wait;
is($got_data, "M", "Taking 1 byte with wait()?");
is($eof, 0, "Still no eof?");

# Test starting event looop
$stream->read_p(0,2)->then( sub { ($got_data,$eof) = @_ });
Mojo::IOLoop->start;
is($got_data, "y ", "Taking 2 bytes with IOLoop?");
is($eof, 0, "Still no eof?");

# Might be better splitting this out into explicit 0/undef tests
$stream->read_p()->then( sub { ($got_data,$eof) = @_ })->wait;
is($got_data, "String", "Taking rest of bytes from 'My String'?");
is($eof, 1, "Got eof?");

# Stream has ended, expect "", 1
$stream->read_p()->then( sub { ($got_data,$eof) = @_ })->wait;
is($got_data, "", "No data after eof?");
is($eof, 1, "eof still reported?");

# Test reading more bytes than are available
$stream->[0]="My String";	# alternative to new()
$stream->read_p(0,1000)->then( sub { ($got_data,$eof) = @_ })->wait;
is($got_data, "My String", "Asking for more bytes than available?");
is($eof, 1, " eof?");

# Unit Test App::IDA::Daemon::StringSinkP

use_ok("App::IDA::Daemon::StringSinkP");

# Create a new package that converts a stream to upper case
package ToUpper;

use warnings;

sub new { bless { upstream => $_[1], buf => "" }, $_[0] }

sub read_p {
    my ($self, $port, $bytes) = @_;

    # fudge $bytes because downstream will pass us 0 and I'd prefer to
    # test finite chunk size instead of getting everything in a single
    # read_p.
    $bytes = 10;
    my $promise = Mojo::Promise->new;
    $self->{upstream}->read_p(0,$bytes)->then(
	sub {
	    my ($data, $eof) = @_;
	    $data =~ y/a-z/A-Z/;
	    $promise->resolve($data, $eof);
	},
	sub {
	    $promise->reject($_[0]);
	});
    $promise;
}
1;

package main;

my ($source,$filter,$sink);

# Test String Source -> String Sink (no transforming filter)

my $from_finished = "";
$source = App::IDA::Daemon::StringSourceP->new("$lorem");
$sink = App::IDA::Daemon::StringSinkP->new($source);
ok(ref($sink));
$sink->on(finished => sub {$from_finished = $_[1]});
$sink->start;
Mojo::IOLoop->start;

is ($from_finished, $lorem, "finished: string source -> string sink?");
ok ($sink->to_string eq $lorem, "to_string: string source -> string sink?");

# recreate source with longer data and use ToUpper module

$source = App::IDA::Daemon::StringSourceP->new("$lorem");

my $to_upper = ToUpper->new($source);

# leave most of the parameters undefined
$sink = App::IDA::Daemon::StringSinkP->new($to_upper);
ok(ref($sink));

# test getting transformed stream back via 'finished' event
$from_finished = "";
$sink->on(finished => sub {$from_finished = $_[1]});

$sink->start;
Mojo::IOLoop->start;
	  
is ($from_finished,  uc $lorem, "string source -> to_upper -> string sink?");
ok ($sink->to_string eq uc $lorem, "string source -> to_upper -> string sink?");

# Test "NullFilter", which just copies input to output.

my $control = 


done_testing; exit;

# Port remaining *P classes and tests from here

# Encrypt/Decrypt (tests ported from aes.t via EncryptFilterP)
use_ok("App::IDA::Daemon::Link::EncryptFilter");
use_ok("App::IDA::Daemon::Link::DecryptFilter");

done_testing; exit;

# and tap into the middle
use_ok("App::IDA::Daemon::TapFilterP");

my $message = $lorem;
my $key = "0123456789abcdef";   # 128-bit key (16 bytes) 

# warn "message is of size " . length($message) . "\n";
#
# The message is 446 bytes, so it's not an even multiple of 16 (the
# AES block size). If it /was/ a multiple of the block size, I would
# probably want to do another test to make sure that the algorithm
# handled partial blocks at the end of the message properly.
#
# As it is, though, since the message /does/ have a partial block at
# the end, I won't test the case where the message is a multiple of
# the AES block size.
# 

# set up our processing chain: string -> enc -> dec -> string

# Try out sending a byte at a time, since this may cause problems with
# the encryption/decryption routines themselves, since they work on
# blocks of data.

my $chunk_size = 1;

$source = App::IDA::Daemon::StringSourceP->new($message);

my $enc = App::IDA::Daemon::EncryptFilterP->new($source, $key);

ok (ref($enc), "new Encoder?");
# insert a tap that copies the data stream between enc/dec
my $tapped = '';
my $tap = App::IDA::Daemon::TapFilterP
    ->new($enc,
          sub {
              my $data = $_[1];
              $tapped .= $data;
              $_[0]->emit("read" => $data);
          });

# and wire decoder to be downstream of the tap
my $dec = App::IDA::Daemon::DecryptFilterP
    ->new($tap, $key);

ok (ref($dec), "new Decoder?");

$output = "";

$sink = App::IDA::Daemon::StringSinkP
    ->new($dec, 0, 0, \$output);
ok (ref($sink), "new Sink?");

# We don't actually have subscribe to close events here
$source->start;
Mojo::IOLoop->start;

is ($output, $message, "Input/Output messages match?");
isnt ($message, $tapped, "Encoder actually transformed data?");


done_testing; exit;
