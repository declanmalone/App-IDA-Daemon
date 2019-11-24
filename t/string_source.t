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
my $ut_class = "App::IDA::Daemon::StringSource";
use_ok($ut_class);


my $stream = App::IDA::Daemon::StringSource
    ->new("Mojo::IOLoop", "My String", 3);

my ($output, $callbacks, $got_close) = ("", 0, 0);
$stream->on(read => sub { ++$callbacks; $output .= $_[1] });
$stream->on(close => sub { $got_close++ });

# Expect the IO loop to exit when string is finished streaming
# (thus no need to set up promises or similar)
$stream->start;
Mojo::IOLoop->start;

is ($output, "My String", "Got back same output as input?");
is ($callbacks, 3, "read callback called 3 times?");
is ($got_close, 1, "Got a single close callback?");

# Test omitting to start the stream (IOLoop should still exit)
$stream = App::IDA::Daemon::StringSource
    ->new("Mojo::IOLoop", "My String", 3);

($output, $callbacks, $got_close) = ("", 0, 0);
$stream->on(read => sub { ++$callbacks; $output .= $_[1] });
$stream->on(close => sub { $got_close++ });

Mojo::IOLoop->start;

is ($output, "", "Expect no output if stream wasn't started");
is ($callbacks, 0, "Expect no read callback if stream wasn't started");
is ($got_close, 0, "Expect no close callback if stream wasn't started");

# Expect that if we start the stream now, the event loop will
# start triggering it (omit constructor)
$stream->start;
Mojo::IOLoop->start;

is ($output, "My String", "Got back same output as input?");
is ($callbacks, 3, "read callback called 3 times?");
is ($got_close, 1, "Got a single close callback?");

# Now make sure that once() works
$stream = App::IDA::Daemon::StringSource
    ->new("Mojo::IOLoop", "My String", 3);

($output, $callbacks, $got_close) = ("", 0, 0);
$stream->once(read => 
	      sub {
		  ++$callbacks; $output .= $_[1];
		  # turn off the firehose
		  $stream->stop;
	      });
$stream->on(close => sub { $got_close++ });

$stream->start;
Mojo::IOLoop->start;

is ($output, "My ", "Got first 3 bytes of input?");
is ($callbacks, 1, "read callback called just once?");
is ($got_close, 0, "Got zero close callbacks?");

# Reinstate an "on" subscriber and make sure that we didn't miss any
# of the stream:
$stream->on(read => sub { ++$callbacks; $output .= $_[1] });
$stream->start;
Mojo::IOLoop->start;

is ($output, "My String", "stop/start on stream OK?");
is ($callbacks, 3, "Totalled 3 read callbacks?");
is ($got_close, 1, "Got final close callback?");

# make sure that no matter how many starts we make, that spurious
# messages won't be sent so long as we finish with a $stream->stop
#
$stream = App::IDA::Daemon::StringSource
    ->new("Mojo::IOLoop", "My String", 3);

($output, $callbacks, $got_close) = ("", 0, 0);
$stream->on(read => sub { ++$callbacks; $output .= $_[1] });
$stream->on(close => sub { $got_close++ });

# flick the light switch really quickly...
$stream->stop;
$stream->start;
$stream->start;
$stream->start;
$stream->stop;
$stream->start;
$stream->stop;

Mojo::IOLoop->start;
is ($output, "", "Expect no output since stream stopped");
is ($callbacks, 0, "Expect no read callbacks since stream stopped");
is ($got_close, 0, "Expect no close callback since stream stopped");

# Do the same again
$stream->stop;
Mojo::IOLoop->start;
is ($output, "", "Expect no output since stream stopped");
is ($callbacks, 0, "Expect no read callbacks since stream stopped");
is ($got_close, 0, "Expect no close callback since stream stopped");

# Now start and make sure that the repeated stop/start was OK.
$stream->start;
Mojo::IOLoop->start;

is ($output, "My String", "repeated stop/start on stream OK?");
is ($callbacks, 3, "Totalled 3 read callbacks?");
is ($got_close, 1, "Got final close callback?");

# Final word on stop/start
#
# I expect repeated stops/starts that finish with a start to mess up
# the one-tick behaviour of the class (you'll get multiple 'read'
# events in the same event loop tick, and maybe not even in the right
# order), so:
#
# a) don't do that ("that" = calling start multiple times); and
# b) I'm not going to test it because I don't intend to fix it

# Conformance testing?
#
# I could try the above to make sure that this class behaves the same
# as Mojo::IOLoop::Stream, but I don't think it's necessary to do
# exhaustive conformance testing.

# I will test the "once" behaviour of Mojo::IOLoop::Stream, though:
open my $fh, "<", $0 or die "Can't open this script for reading\n";
my $script = Mojo::IOLoop::Stream->new($fh);

($output, $callbacks, $got_close) = ("", 0, 0);
$script->on(close => sub { $got_close++ });
$script->start;
Mojo::IOLoop->start;

# if we got close, it means that $script->start ran through reading
# the file even if it didn't have a read subscriber. So that would
# match the "once" behaviour of my script.
is ($got_close, 1, "Mojo::IOLoop::Stream also runs without read subscribers");

done_testing;
