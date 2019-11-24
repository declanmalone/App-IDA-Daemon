package App::IDA::Daemon::StringSource;
use Mojo::Base 'Mojo::EventEmitter';

use warnings;

# A simple string source that emulates a Mojo::IOLoop::Stream object

sub new {
    my ($class, $ioloop, $string, $chunk) = @_;
    $chunk = length($string) unless defined $chunk;
    bless {
	ioloop => $ioloop,
	string => $string,
	chunk => $chunk,
	running => 0 }, $class;
}

sub close {
    my $self = shift;
    $self->{running} = 0;
    $self->emit("close");    
}
sub stop { $_[0]->{running} = 0 }

sub start {
    my $self = shift;
    $self->{running} = 1;
    $self->{ioloop}->next_tick(sub { $self->_do_chunk });
}

sub _do_chunk {
    my $self = shift;
    return unless $self->{running};
    # splice out the next chunk
    my $chunk = substr($self->{string}, 0, $self->{chunk},"");
    $self->emit("read" => $chunk) if $chunk ne "";

    # Queue up follow-on event or emit close. I'm using next_tick to
    # allow the caller a chance to stop us between event loop ticks,
    # and also so that it's easier to one-tick the event loop.
    warn "in _do_chunk, string is '$self->{string}'\n";
    if ($self->{string} ne "") {
	$self->{ioloop}->next_tick(sub { $self->_do_chunk });
    } else {
	$self->{running} = 0;
	$self->{ioloop}->next_tick(sub { $self->emit("close") });
    }
}

1;
__END__

=head1 SYNOPSIS

 use App::IDA::Daemon::StringSource;
 use Mojo::IOLoop;

 # Stream a string 3 characters at a time
 my $stream = App::IDA::Daemon::StringSource
  ->new("Mojo::IOLoop", "My String", 3);

 my $output = "";
 $stream->on(read => sub { $output .= $_[1] });

 $stream->start;
 Mojo::IOLoop->start;

=head1 DESCRIPTION

This module implements a "treat a string as a stream" idea in a way
that should be compatible with Mojo::IOLoop::Stream.

Mojo::IOLoop::Stream objects only handle "streaming" file handles
(fifos, sockets, pipes, etc.), so it doesn't work (fully) with regular
files. Nor does it work with the kind of file handle created as
follows:

 # read from a string via a perl file handle
 my $string = "I'm not a file, but to many I look like one";
 open my $fh, "<", \$string;

The natural use for this class is in test scripts where it's more
conventient to stream from string literals, without needing to set up
test files.

=head1 EVENTS EMITTED

This class derives from C<Mojo::EventEmitter>. Objects emit these
events just like a Mojo::IOLoop::Stream object would:

=over

=item read

More data from the string becomes available (once per event loop tick).

=item close

Emitted after string has been consumed (eof) or close() method called.

=back

=head1 METHODS

The following method calls are available:

=over

=item new($event_loop, $string, $chunk_size)

Hooks into the event loop ('C<Mojo::IOLoop>') to set up repeated
streaming of C<$chunk_size> bytes from C<$string>.

C<$chunk_size> can be undefined, in which case it defaults to the
length of the string.

=item start

Set state of the object to "running". You also need to have the event
loop running before any events will be emitted.

=item stop

Stops the object running. Useful in a C<once(read ...)>
callback to make sure you don't miss any read chunks.

=item close

Manually "close" the stream.

=back

