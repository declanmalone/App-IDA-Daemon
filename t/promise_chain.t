#!/usr/env/perl

use Mojo::Base -strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Test::More;
use Test::Mojo;

use Mojo::Promise;

# Does high-level functionality testing on promise-based processing
# pipelines.
#
# The various promise-based Sources, Filters and Sinks don't have much
# in the way of callable methods, so there's not much unit testing we
# can do. I will do a little bit, such as verifying that any sample
# code included in the POD runs correctly.

# Unit Test App::IDA::Daemon::StringSourceP

use_ok("App::IDA::Daemon::StringSourceP");

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

$stream->read_p(0,1)->then( sub { ($got_data,$eof) = @_ })->wait;
is($got_data, "M", "Taking 1 byte from 'My String'?");
is($eof, 0, "Still no eof?");

# Might be better splitting this out into explicit 0/undef tests
$stream->read_p()->then( sub { ($got_data,$eof) = @_ })->wait;
is($got_data, "y String", "Taking rest of bytes from 'My String'?");
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



done_testing; exit;
