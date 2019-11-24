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

 my $stream = App::IDA::Daemon::StringSource
  ->new("Mojo::IOLoop", "My String", 3);

 my $output = "";
 $stream->on(read => sub { $output .= $_[1] });

 $stream->start;
 Mojo::IOLoop->start;

=head1 DESCRIPTION

Mojo::IOLoop::Stream objects only handle "streaming" file handles, so
it doesn't work (fully) with regular files. Nor does it with the kind
of file handle created as follows:

 # read from a string via a perl file handle
 my $string = "I'm not a file, but to many I look like one";
 open my $fh, "<", \$string;

This module implements the same kind of "treat a string as a stream"
idea in a way that should be compatible with Mojo::IOLoop::Stream.

