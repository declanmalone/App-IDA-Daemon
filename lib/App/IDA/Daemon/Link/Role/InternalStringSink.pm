package App::IDA::Daemon::Link::Role::InternalStringSink;

use v5.10;

# Role for internal string sink
use Mojo::Base -role;

# All implementations of write_to_internal will take a promise later
# since I want a write to an internal Mojo::IOLoop::Stream object to
# drain completely before calling next_tick in Sink's loop. Otherwise
# I get the same kind of firehose problem that happens at the Source
# end if you connect to the Stream with $stream->on(read => ...)
#
# See +Sink for calling context

sub write_to_internal {
    my ($self, $bytes) = @_;

}

1;

__END__

=head1 SYNOPSIS

 use App::IDA::Daemon::Link;

 # Compose a new Link class
 my $class = App::IDA::Daemon::Link
    ->with_roles("+Sink", "+InternalStringSink");
 
 # Create a new instance of the class
 my $output_string = "";
 my $sink = $class->new(
   sink_buffer = \$output_string,
   ...
    # constructor args required for other roles go here
 );
 
 # optionally subscribe to $sink's 'finished' event
 $sink->on(finished => sub {
   warn "Slurped all the data:\n$_[1]\n"
 });
 
 # Set up a chain of other processing elements, then ...
 $sink->start;
 Mojo::IOLoop->start;
 
 # Alternative ways of accessing sunk data
 if (ref($sink->sink_buffer)) {
   say "Sink buffer is a strref containing " . ${$sink->sink_buffer};
 } else {
   say "Sink buffer is a string containing $sink->{sink_buffer}";
 }
 say "Sink buffer contains " . $sink->to_string;

The sink_buffer argument to new() is optional. If it is not provided,
a fresh empty string will be used.

=head1 ROLE DESCRIPTION



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

