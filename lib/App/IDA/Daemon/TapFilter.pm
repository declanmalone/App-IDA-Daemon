package App::IDA::Daemon::TapFilter;
use Mojo::Base 'Mojo::EventEmitter';

use warnings;

# Tap into a processing pipeline with an arbitrary callback

sub new {
    my ($class, $upstream, $read, $close, $callback) = @_;
    unless ($upstream->isa("Mojo::EventEmitter")) {
	warn "StringSink needs a Mojo::EventEmitter as input\n";
	return undef;
    }
    unless ("CODE" eq ref $callback) {
	warn "callback must be a code reference\n";
	return undef;
    }

    my $self = bless {
	upstream => $upstream,
	read     => $read,
	close    => $close,
	read_callback => $callback,
	close_callback => $callback,
    }, $class;

    # subscribe to upstream, but run callback/emit on self
    $upstream->on($read => sub { shift; &$callback($self, @_) });
    unless (defined($close)) {
	warn "TapFilter needs to subscribe to close or downstream will break\n";
	return undef;
    }
    $upstream->on($close => sub { $self->emit("close") });
    $self;
}

1;

=pod

=head1 NAME

TapFilter - Do arbitrary processing on a data stream

=head1 SYNOPSIS

 use App::IDA::Daemon::TapFilter;

 my $flip_case = sub {
   my ($self, $data) = @_;
   my $len = length($data);
   my $spaces = " " x $len;
   $data ^= $spaces;
   $self->{transformed} .= $data;
   $self->{bytes} += $len;
   $self->emit(read => $data);
 };

 my $report_bytes = sub {
   my $self = shift;
   my $bytes = $self->{bytes};
   $self->emit(close => "Transformed $bytes bytes of data\n");
 };

 # set up some upstream EventEmitter object(s)
 my $source = ...

 # set up the tap
 my $tap = App::IDA::Daemon::TapFilter
   ->new($source, "read", "close", $flip_case, $report_bytes);

 # subscribe to its close event and pull out stashed data
 $tap->on(close =>
   sub {
     my ($self, $message) = @_;
     print "Tap complete: $message\n";
     print "Transformed text: $self->{transformed}\n";
   });

 # set up downstream EventEmitter object(s)
 ...

 # start the stream
 $source -> start;
 Mojo::IOLoop -> start;

=head1 DESCRIPTION

This module works within a chain of other Source, Filter and Sink
classes. It lets you install arbitrary callbacks for when the upstream
source emits a 'read' or 'close' event.

Both callbacks are optional, in which case the default callbacks will
be used:

=over

=item on "read"

data passed in from the upstream object will be emitted as a "read"
event in the tap object.

=item on "close"

emit a "close" event, also passing on any data from the downstream
object that closed.

=back

Callbacks have access to the object itself (as the first parameter
passed to the callback), so the callbacks can use the object as a
stash for storing arbitrary data. The following values are stashed by
the object (a blessed hash) itself:

=over

=item upstream

The upstream EventEmitter object whose events we are subscribed to.

=item read

The name of the upstream "read" event to subscribe to.

=item close

The name of the upstream "close" event to subscribe to.

=item read_callback

The read callback passed to the constructor (undef for none).

=item close_callback

The close callback passed to the constructor (undef for none).

=back

As well as accessing stored data during callbacks, you can also do
some initial configuration after calling the constructor, but before
starting any upstream sources.

=head1 SCENARIOS

