package App::IDA::Daemon::Chainable;
use Mojo::Base -role, "Mojo::EventEmitter";

has [qw() ];
     
sub stop {
    my $self = shift;
    $self->{upstream} -> stop if defined $self->{upstream};
}

sub start {
    my $self = shift;
    $self->{upstream} -> start if defined $self->{upstream};
}

1;

=pod

=head1 NAME

App::IDA::Daemon::Chainable - Role-based sources, filters, sinks

=head1 SYNOPSIS

 use warnings;
 use App::IDA::Daemon::Chainable qw(
 
 ...

=head1 DESCRIPTION

This class implements a Role::Tiny base class for combining
asynchronous "processing elements" in a chained pipeline, similar to a
Unix shell pipeline. Throughout this documentation, I will refer to
these elements as either "Sources", "Filters" or "Sinks".

=over

=item Source

A Source starts a processing pipeline, and sends data downstream to
other processing elements.

Examples include a file or socket that is open for reading.

=item Filter

A Filter receives data from upstream and passes data downstream,
possibly modifying it along the way.

Examples include filters that do encryption/decryption or
compression/decompression.

=item Sink

A Sink comes at the end of a pipeline. It receives data from upstream,
but does not send anything downstream.

=back

Graphically, the pipeline is similar to a Unix shell pipeline:

 Source -> Filter1 -> Filter2 -> Sink

=head1 APPROACH

Broadly speaking, there are two ways to approach the implementation of
asynchronous processing pipelines so that they work well with
Mojo::IOLoop. The first is to model processing elements on
C<Mojo::IOLoop::Stream>. The second involves using Mojo::Promise. I
have chosen the latter route for this implementation, but I will
explain the other method (and its shortcomings) first.


=head2 Base on C<Mojo::IOLoop::Stream>.

Consider a Source element which is an actual C<Mojo::IOLoop::Stream>
object. In order to add Filter (or Sink) processing elements
downstream of this object, the user must subscribe to the C<read>
event that is emitted by the C<Mojo::IOLoop::Stream> object. For
completeness, the downstream object will probably also subscribe to
the Stream object's C<close> event, although this could also be
handled elsewhere (in the code that sets up and manages the entire
chain, for example).

If all other processing elements in the chain are set up in the same
way, they will:

=over

=item * subscribe to the upstream object's read and close events

=item * raise its own read events (if it's not a Sink), and close events

=back

This is easy to set up, but suffers from what I call the "Firehose
Problem". Simply put, processing elements that are downstream of this
kind of object have no control over the rate at which data is being
pumped out by the upstream object. If we have a processing pipeline
where some downstream steps are slower that the upstream steps, then
there is no flow control. All the data that the upstream source is
providing must generate a "read" callback indicating that more data is
ready, and if the downstream step is not ready to deal with it, then
that data must be cached until the slow processing step is ready to
deal with it.

This could happen in several scenarios, such as:

=over

=item Mismatched network transport links

Our Source is a large file being streamed to us over a fast network
link, and a downstream Sink sends it out over a slower network link

=item Mismatched CPU costs

Some downstream processing step performs an expensive, CPU-bound
operation that is slower than the upstream data arrival/processing
rate.

=back

In these kinds of cases, when working with large streams, there is a
possibility that the buffers used to store data waiting for processing
can grow indefinitely, causing the system to eventually run out of
memory.

=head3 Workarounds

One possible work-around would be to:

=over

=item * also implement start/stop functionality on each processing element

=item * have the slow processing element stop the upstream element when
it has enough data, and restart it when it is ready to process some more

=item * ensure that stop/start method calls are propagated all the way
back to the start of the chain

=back

The C<Mojo::IOLoop::Stream> class does implement start/stop methods,
so it would ultimately be possible to turn off the "firehose" at the
source. This would work if the C<Mojo::IOLoop::Stream> object was
acting as a Source, but we would need more wrappers around a similar
object acting as a Sink, at the end of the pipeline.

We can no longer use C<$stream->write()> since it is non-blocking, so
we would need to wrap access to the underlying Mojo::IOLoop::Stream
object with a code fragment such as:

 my $stream = $self->{ostream};
 # pass congestion signal back along chain
 $self->{upstream}->stop();
 # write data, restarting chain when it's flushed
 $stream->write($data, sub { $self->{upstream}->start });

Another, different, workaround would be introduce some form of
rate-limited channel (such as a socket or fifo pair) between a fast
producer and a slow consumer. In that way, even if the producer was
producing data much faster than the consumer could consume it. A fast
producer would write to the transmit side of a socket/fifo pair. At
some point, the operating system itself would make writes to the pipe
block.

However, this workaround only works if the upstream element is doing a
blocking write, which basically rules out using Mojo::IOLoop::Stream
within a processing pipeline unless we wrap up the write call as above.

Neither of these workarounds (or combinations of them) are very
appealing. As a result, I will take a completely different approach,
as described in the next section.

Before leaving, though, I would just like to make a brief comment on
the design of Mojo::IOLoop::Stream. I won't go so far as to say that
the design is bad, per se. Within the context of a web server, most
files are quite small, and where large files are being transferred,
they are actually handled elsewhere in the framework. From that point
of view, the Firehose problem isn't really going to be an issue for
most people.

However, since I'm less interested in using the pre-baked streaming
upload/download features of Mojo, but in creating arbitrary processing
pipelines, these problems do arise for me.

I would point out that once you start using Mojo::IOLoop::Stream
outside of the imagined context of a Mojolicious web app, it will
always lead to potential situations where the system can run out of
memory, unless you apply proper workarounds to prevent that. In
I<that> respect, it's not well designed, in my opinion.

=head2 A promise-based Mojo::IOLoop::Stream

If you examine the man page for C<Mojo::IOLoop::Stream>, you will find
information on the read I<event>, but you will notice that there is no
read I<method>. Basically you're stuck with the Firehose and the only
real workaround is to implement flow control manually via wrapping
your "real" reads and writes up with extra callbacks and methods calls
to start/stop. Expect to also have to add your own buffering code if
you want to C<read()> fewer bytes than each on-read callback throws in
your direction.

A "properly" implemented version of Mojo::IOLoop::Stream would have
additional method calls such as:

=over

=item read_p($opt_bytes)

Takes an optional number of bytes (defaulting to "high water mark") to
read from the Stream and returns a Mojo::Promise which returns up to
that number of bytes upon fulfillment.

In the time between creation of the promise and its fulfillment, the
Mojo::IOLoop::Stream object will not emit any C<read> events. Upon
fulfillment, it will emit a C<read> event to any subscribers with the
data described above.

No more than one call to C<read_p()> on a given
C<Mojo::IOLoop::Stream> object can be active at any time.

=item write_p($data)

Like read_p, but for writing.

=back

With such a pair of methods, C<Mojo::IOLoop::Stream> and pipelines
that use them would allow a "pull" method of accessing the data
stream, as opposed to the "push" method as currently implemented. Or,
going back to the firehose analogy, downstream elements would get to
sip as much data as suited them, rather than at a pace dictated by the
upstream source.



