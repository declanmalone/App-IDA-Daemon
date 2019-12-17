package App::IDA::Daemon::Link::Role::Sink;

# Sink trait
use Mojo::Base -role;

use Mojo::IOLoop;

# Some other role must supply the concrete method below:
requires qw(write_to_internal);

# See the following roles for concrete implementations:
# * +InternalStringSink
# * +InternalNullSink
# * +InternalStreamSink
# * +InternalDigestSink

# TODO: $self->{bytes} isn't declared as an attribute (we need need a
# BUILDARGS section)
has qw(running preferred_bytes);

# Filters and Sink pull (call read_p) from upstream, so we compose
# that role in here.
use Role::Tiny::With;
with 'App::IDA::Daemon::Link::Role::PullsFromUpstream';

# Sink comes at the end of the processing chain is responsible for
# scheduling itself (directly via start/stop/_thunk) and everything
# upstream of it (indirectly, via repeated calls to $upstream->read_p)
sub stop { $_[0]->{running} = 0 }
sub start {
    my $self = shift;
    return if $self->{running}++;
    Mojo::IOLoop->next_tick(sub { $self->_thunk });
}
sub _thunk {
    my $self = shift;
    return unless $self->{running};
    
    $self->{upstream_object}
    ->read_p($self->{upstream_port}, $self->{bytes})
	->then(
	sub {
	    my ($data, $eof) = @_;
	    # TODO: make this promise-based
	    $self->write_to_internal($data);
	    if ($eof) {
		$self->emit(finished => ${$self->{strref}});
	    } else {
		Mojo::IOLoop->next_tick(sub { $self->_thunk });
	    }
	},
	sub {
	    $self->emit(error => $_[0]);
	});
}


1;
