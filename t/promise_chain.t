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

# Unit Test App::IDA::Daemon::StringSinkP

use_ok("App::IDA::Daemon::StringSinkP");

# Create a new package that converts a stream to upper case
package ToUpper;

use warnings;

sub new {
    bless { upstream => $_[1], buf => "" }, $_[0]
}

sub read_p {
    my $self = shift;
    my $bytes = shift // 4;

    my $promise = $self->{promise} = Mojo::Promise->new;
    $self->{upstream}->read_p($bytes)
	->then(
	sub {
	    my ($data, $eof) = @_;
	    $data =~ y/a-z/A-Z/;
	    $promise->resolve($data, $eof);
	    $promise = undef;
	    #warn "got here\n";
	},
	sub {
	    $promise->reject($_[0]);
	    $promise = undef;
	});
    $promise;
}
1;

package main;

# re-use old stream object, but give it new data

my $source = $stream;
my $lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit,
sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut
enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi
ut aliquip ex ea commodo consequat. Duis aute irure dolor in
reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla
pariatur. Excepteur sint occaecat cupidatat non proident, sunt in
culpa qui officia deserunt mollit anim id est laborum.\n";
$source->[0] = $lorem;

my $to_upper = ToUpper->new($source);

# leave most of the parameters undefined
my $sink = App::IDA::Daemon::StringSinkP->new(undef,$to_upper);

$sink->start;
Mojo::IOLoop->start;

is ($sink->to_string, uc $lorem, "string source -> to_upper -> string sink?");

done_testing; exit;
