#!/usr/bin/env perl              # -*- perl -*-

use Mojo::Base -strict;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Test::More;
use Test::Mojo;

use Mojo::Promise;

use v5.20;
use Carp;

# Unit test class
my $ut_class = "App::IDA::Daemon::TapFilter";
use_ok($ut_class);

use App::IDA::Daemon::StringSource;
use App::IDA::Daemon::StringSink;

my $message = "Sending this";
my $output  = "";
my $tapped  = "";

# Simple source string -> tap -> sink string pipeline
# The tap simply copies data as it passes

my $src = App::IDA::Daemon::StringSource
    ->new("Mojo::IOLoop", $message, 2);
ok (ref($src), "new StringSource?");

my $cb = sub {
    my ($self, $data) = @_;
    $tapped .= $data;
    $self->emit(read => $data);
};

my $tap = App::IDA::Daemon::TapFilter
    ->new($src, "read", "close", $cb);
ok (ref($tap), "new TapFilter?");

# See if default close callback worked
my $got_close_callback = 0;
my $close_called_from = undef;
my @close_args;
$tap->on(close => 
	 sub {
	     $close_called_from = shift;
	     ++$got_close_callback;
	     @close_args = @_;
	 });

my $dst = App::IDA::Daemon::StringSink
    ->new($tap, "read", "close", \$output);

# Start the chain
$src -> start;
Mojo::IOLoop -> start;

# Test that our read callback worked
isnt ($tapped, "", "Tapped data not empty?");
isnt ($output, "", "Output data not empty?");
is ($tapped, $output, "Tapped data same as chain output?");

# Testing default close callback
is ($got_close_callback, 1, "Default close callback raised?");
is_deeply (\@close_args, [], "Default close callback args are ()?");
is ($tap, $close_called_from, "Close came from TapFilter?");

#
# Test default callbacks (should relay data downstream)
#
# chain: source -> tap (custom) -> tap (default) -> tap (check)
#
$message = "Sending this";
$output  = "";
$tapped  = "";

# Simple source string -> tap -> sink string pipeline
# The tap simply copies data as it passes

$src = App::IDA::Daemon::StringSource
    ->new("Mojo::IOLoop", $message, 2);
ok (ref($src), "new StringSource?");

# custom read callback, just the same as before
my $read_cb = sub {
    my ($self, $data) = @_;
    $tapped .= $data;
    $self->emit(read => $data);
};

# new close callback that passes message
my $close_cb = sub {
    my $self = shift;
    # the baton should reach the end of the chain
    $self->emit(close => "baton");
};

my $tap1 = App::IDA::Daemon::TapFilter
    ->new($src, "read", "close", $read_cb, $close_cb);
ok (ref($tap1), "new (custom) TapFilter?");
my $tap2 = App::IDA::Daemon::TapFilter
    ->new($tap1, "read", "close");
ok (ref($tap2), "new (default) TapFilter?");

# will use tap3 to save output (like string sink did)
# and check if we got the baton
my $got_baton = 0;
$output = "";
$close_called_from = undef;
$got_close_callback = 0;
my $tap3 = App::IDA::Daemon::TapFilter
    ->new($tap2, "read", "close",
	  sub {
	      my ($self, $data) = @_;
	      $output .= $data;
	  },
	  sub {
	      my ($self, $data) = @_;
	      $got_close_callback++;
	      $close_called_from = $self;
	      $got_baton++ if $data eq "baton";
	  });
ok (ref($tap3), "new (check) TapFilter?");

# Start the chain
$src -> start;
Mojo::IOLoop -> start;

isnt ($output, "", "Output data not empty?");
is ($tapped, $output, "Tapped data same as chain output?");

is ($got_close_callback, 1, "Default close callback raised?");
is ($tap3, $close_called_from, "Close came from tap3?");

ok ($got_close_callback, "Got close callback in tap3?");
ok ($got_baton, "Got baton in tap3");



done_testing;
