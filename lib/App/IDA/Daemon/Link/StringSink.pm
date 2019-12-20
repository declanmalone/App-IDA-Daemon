package App::IDA::Daemon::Link::StringSink;

use v5.10;

# Need Mojo::Base here to get 'has' feature
use Mojo::Base 'App::IDA::Daemon::Link';


use Role::Tiny::With;

# The Sink role provides the basic processing pattern, but it
# delegates the actual internal stream provision to
# InternalStringSink. (both must be composed at once)

with
    'App::IDA::Daemon::Link::Role::Sink',
    'App::IDA::Daemon::Link::Role::InternalStringSink';

use Mojo::Promise;
use Mojo::IOLoop;

# In my original implementation of a processing pipeline using on-read
# and on-close events my StringSource class allowed passing a "chunk"
# argument to the constructor. That object would then parcel out the
# string in chunks of that many bytes.
#
# In the redesigned code, it's Sinks that are in control of how much
# data should be produced. I want an equivalent kind of parameter
# here.
#
# In production code, I would set this to 0, meaning that downstream
# links would accept any amount of data from the upstream link.
# However, when testing it's very useful to use smaller chunk sizes
# like a byte or two.

# default number of bytes to read from downstream
has preferred_bytes => 1;

# We're a class, not a role, so we define BUILDARGS. Other composed
# roles can then wrap around it.
sub BUILDARGS {
    my ($self, $args, $errors) = @_;
    # constructor can be passed value of preferred_bytes:
    if (defined $args->{preferred_bytes}) {
	$self->preferred_bytes($args->{preferred_bytes});
    }
};


# Constructor will be handled by parent class, plus a BUILDARGS
# section in some role (InternalStringSink)
sub new {
    my ($class, $upstream, $port, $bytes, $strref) = @_;

    die "Upstream undefined or can't read_p()\n" 
	unless defined($upstream) and $upstream->can("read_p");

    # There's no point in passing in $ioloop parameter since this
    # routine won't work properly if we're passed in a Mojo::IOLoop
    # *object* as opposed to the class name.
    #
    # $ioloop //= "Mojo::IOLoop";

    # we can leave these as undef, but it's nicer to set them
    # explicitly in case upstream wants to use them in errors or
    # warnings.
    $port   //= 0;
    $bytes  //= 0;

    # Make strref optional (caller can always get the value from the
    # finished event or by calling our to_string method after that)
    my $lvalue = "";		# must be an lvalue (\"" won't work)
    $strref //= \$lvalue;
    die "ref(\$strref) ne 'SCALAR'\n" if "SCALAR" ne ref $strref;

    bless {
#	ioloop   => $ioloop,
	upstream => $upstream,
	port     => $port,
	bytes    => $bytes,
	strref   => $strref,
	running  => 0,
	promise  => undef,
    }, $class;
}

sub write_to_internal {
    # Will take a promise later
    my ($self, $bytes) = @_;

}

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

