package App::IDA::Daemon::TapFilter;
use Mojo::Base 'Mojo::EventEmitter';

use warnings;

# Tap into a processing pipeline with arbitrary callback(s)

sub new {
    my ($class, $upstream, $read, $close,
	$read_callback, $close_callback, $opts) = @_;
    unless ($upstream->isa("Mojo::EventEmitter")) {
	warn "TapFilter needs a Mojo::EventEmitter as input\n";
	return undef;
    }
    $opts = {} unless defined $opts;
    my $self = bless {
	%$opts,			# don't override our variables
	upstream => $upstream,
	read     => $read,
	close    => $close,
    }, $class;

    if (defined $read_callback) {
	unless ("CODE" eq ref $read_callback) {
	    warn "read_callback must be a code reference\n";
	    return undef;
	}
	unless (defined $read) {
	    warn "got read callback but no read event name\n";
	    return undef;
	}
    } else {
	$read_callback = sub { shift; $self->emit(read => @_) };
    }
    if (defined $close_callback) {
	unless ("CODE" eq ref $close_callback) {
	    warn "close_callback must be a code reference\n";
	    return undef;
	}
	unless (defined $close) {
	    warn "got close callback but no close event name\n";
	    return undef;
	}
    } else {
	$close_callback = sub { shift; $self->emit(close => @_) };
    }

    $self->{read_callback} = $read_callback;
    $self->{close_callback} = $close_callback;

    # subscribe to upstream, but run callback/emit on self
    $upstream->on($read  => sub { shift; &$read_callback($self, @_) });
    $upstream->on($close => sub { shift; &$close_callback($self, @_) });
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

The read callback in use (a user-supplied one, or default one)

=item close_callback

The close callback in use (a user-supplied one, or default one)

=back

As well as accessing stored data during callbacks, you can also do
some initial configuration after calling the constructor, but before
starting any upstream sources.

=head1 SCENARIOS

