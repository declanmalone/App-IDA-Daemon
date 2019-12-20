#!/usr/bin/env perl              # -*- perl -*-

use Mojo::Base -strict;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Test::More;
use Test::Mojo;

use Mojo::IOLoop;
use Mojo::Promise;

use v5.20;
use Carp;

# Unit test class
my $ut_class = "App::IDA::Daemon::Link::StringSink";
use_ok($ut_class);

# Below tests will fail (they're from before the redesign)

done_testing; exit;

use App::IDA::Daemon::Link::StringSource;

# Set up a simple StringSource -> StringSink chain
my $instring = "This is an unsurpring string";
my $outstring = "Output already has some contents\n";
# save original outstring
my $orig_out = $outstring;

my $producer = App::IDA::Daemon::StringSource
    ->new("Mojo::IOLoop", $instring, 3);
my $consumer = App::IDA::Daemon::StringSink
    ->new($producer, "read", "close", \$outstring);

ok (ref($consumer), "$ut_class constructor OK?"); 

my $newvalue = "";
$producer->start;
$consumer->on(close => sub { $newvalue = $_[1] });

Mojo::IOLoop->start;

# There are several ways to read/check the returned string
is ($newvalue, $outstring, "In-place update matches close message?");
is ($outstring, "$orig_out$instring", "Original + instring matches output?");
is ($consumer->to_string, "$orig_out$instring", "to_string matches?");


done_testing;
