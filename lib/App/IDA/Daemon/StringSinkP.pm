package App::IDA::Daemon::StringSinkP;
use Mojo::Base 'Mojo::EventEmitter';

use warnings;

use Mojo::Promise;
use Mojo::IOLoop;

# The //= operator first appeared in Perl version 5.10
use v5.10;

# A simple string sink to go at the end of a processing pipeline

sub new {
    my ($class, $ioloop, $upstream, $port, $bytes, $strref) = @_;

    die "Upstream undefined or can't read_p()\n" 
	unless defined($upstream) and $upstream->can("read_p");

    # setting to Mojo::IOLoop->new wasn't working (start would have to
    # explicitly start it instead of just setting running.
    $ioloop //= "Mojo::IOLoop";

    # we can leave these as undef, but it's nicer to set them
    # explicitly in case upstream wants to use them in errors or
    # warnings.
    $port   //= 0;
    $bytes  //= 0;

    # Make strref optional (caller can always get the value from the
    # finished event or by calling our to_string method after that)
    $strref //= \""; 		# \"" ref_to_string;
    die "ref(\$strref) ne 'SCALAR'\n" if "SCALAR" ne ref $strref;

    bless {
	ioloop   => $ioloop,
	upstream => $upstream,
	port     => $port,
	bytes    => $bytes,
	strref   => $strref,
	running  => 0,
	promise  => undef,
    }, $class;
}

sub stop { $_[0]->{running} = 0 }
sub start {
    my $self = shift;
    return if $self->{running}++;
    $self->{ioloop}->next_tick(sub { $self->_thunk });
}

sub _thunk {
    my $self = shift;

    warn "In thunk";
    return unless $self->{running};
    warn "We are running";    

    $self->{promise} =
    $self->{upstream}->read_p($self->{port}, $self->{bytes})
	->then(
	sub {
	    my ($data, $eof) = @_;
	    # We're not getting any data here... why?
	    warn "StringSinkP::_thunk got data $data\n";
	    ${$self->{strref}} .= $data;
	    if ($eof) {
		$self->emit(finished => $self->to_string());
	    } else {
		$self->{ioloop}->next_tick(sub { $self->_thunk });
	    }
	},
	sub {
	    $self->emit(error => $_[0]);
	});
    die unless ref($self->{promise});
}

sub to_string { ${$_[0]->{strref}} }

1;

__END__

=head1 SYNOPSIS

=head2 DESCRIPTION

This class implements a free-running asynchronous Sink loop that comes
at the end of a promise-based processing pipeline. It makes repeated
C<read_p()> requests to the upstream object and stores the returned
stream in a string.

Unlike the related C<*SourceP> and C<*FilterP> modules ("P" for
"Promise"), this module does not implement a read_p method. As with
other Sinks, this module:

=over

=item * takes an explicit event loop parameter, which it uses to schedule itself

=item * implements start/stop methods (defaults to being in the "stopped" state)

=item * takes an optional C<$bytes> parameter, corresponding to the number of bytes requested in each C<read_p()> call to upstream

=item * does not return a promise

=item * instead, raises "finished" or "error" events upon successful completion or an error condition

=back

The processing pipeline implemented with this set of Sources, Filters
and Sinks implement a "pull" model. That is to say, the final Sink in
the chain initiates a request for data, and the upstream element
returns a promise that will eventually fulfil that request. Such
requests continue upstream until a Source eventually supplies data
(eg, from an open socket, file, string, etc.).

This "pull" model contrasts with a "push" model based on free-running
Sources raising events that are subscribed to by the I<downstream>
processing element.

The "push" model is easy to implement, but suffers from what I call
the "Firehose" problem. That is, if some Source is able to produce
data faster than the downstream processing element can consume it,
then any unconsumed data must be buffered, potentially leading to
program memory being consumed.

By contrast, the pull model has lazy evaluation, with Sources (and
Filters) only producing new data when it is requested by a downstream
element.

