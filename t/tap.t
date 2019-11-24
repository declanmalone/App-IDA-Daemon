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

my $dst = App::IDA::Daemon::StringSink
    ->new($tap, "read", "close", \$output);

# Start the chain
$src -> start;
Mojo::IOLoop -> start;

isnt ($tapped, "", "Tapped data not empty?");
isnt ($output, "", "Output data not empty?");
is ($tapped, $output, "Tapped data same as chain output?");


done_testing;
