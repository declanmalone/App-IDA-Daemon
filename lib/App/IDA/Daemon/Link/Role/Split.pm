package App::IDA::Daemon::Link::Role::Split;

# Split trait (somewhat like a Filter)
use Mojo::Base -role;

use Mojo::IOLoop;

# Code for checking upstream_* args moved to +PullsFromUpstream
use Role::Tiny::With;

# This was failing with Role::Tiny versions 2.000006 and 2.000005, but
# the most recent version (2.001004) fixes it. Perhaps the failure was
# because we don't define any methods in the role below?
with 'App::IDA::Daemon::Link::Role::PullsFromUpstream';

# Required functionality

# This role doesn't impose very many restraints on how the consuming
# class implements buffer handling or naming of attributes. However,
# it will require the use of a sliding window class (to enforce
# consistency of read/write pointers, and to provide a callback when a
# bundle of streams advances) and some way to determine the number of
# downstream ports.

requires qw(sw downstream_ports);

# downstream ports in the range [0 .. downstream_ports - 1]
sub has_read_port {
    my ($self, $port) = @_;
    $port >= 0 and $port < $self->downstream_ports;
}

# This role provides a generic implementation of a "greedy processing"
# loop. That is to say, whenever it has the opportunity to process
# some data, it will do so. This will be limited, though, by the
# amount of buffer space available (plus availability of upstream
# data) so even though it's greedy, it can never overflow buffers.

# The consuming class must provide these concrete methods to handle
# the particular buffer operations and split algorithm that it uses.
requires qw(split_process accept_input_columns drain_output_column);

# I need to keep a list of outstanding promises so that if read_p
# can't satisfy a request, it creates a new promise and takes a note
# of the promise and how many bytes were requested.

# must wrap [] in a sub to get a fresh array for every new object:
has downstream_promises => sub { [] };

sub old_new {

    my $class = shift;
    my ($upstream, $ports) = @_;

    # the size of our input/output buffers
    my $window = 30;

    # Later, will store $href->{$portno} = [ $promise, $bytes ]
    my $href = { map { $_ => [] } (0 .. $ports - 1) };
    my $self = bless {
	upstream => $upstream,
	ports => $ports,
	# in/out buffers are simple strings (IDA would use matrix)
	in_buf => "",
	# in_eof set when upstream EOF seen AND we empty our input buffer
	in_eof => 0,
	out_bufs => [("") x $ports],
	out_promises => $href,
	fill_promise => undef,
	drain_promise => undef,
	sw => Crypt::IDA::SlidingWindow->new (
	    mode => split,
	    rows => $ports,
	    window => $window,
	),
    }, $class;

    # Filling up the input buffer and transforming it is mostly
    # independent of responding to read_p calls. Even without any
    # read_p requests, the core of this module is a repeating loop
    # that greedily tries to process as much data as possible.
    #
    # There are two things that can stop this greedy loop in its
    # tracks:
    #
    # 1. we're starved of input data
    # 2. we're starved of output buffer space
    #
    # I will use promises to handle both of these:
    #
    # 1. upstream promises us to provide fresh data 
    # 2. downstream promises us that data will drain
    #
    # Although I call this a loop, actually we do work in chunks and
    # queue up repeated calls to _greedily_process

    # upstream fulfills the first promise
    $self->{fill_promise} = $self->_promise_to_read($window * $ports);

    # schedule greedy process
    Mojo::IOLoop->next_tick(sub { $self->_greedily_process });

    # Here's how the drain promise will be resolved
    $self->{sw}->cb_write_bundle( sub { $self->_resolve_drained(); });

    # So I said to myself, ...
    $self;
}

sub _promise_to_read {
    my ($self, $bytes) = @_;
    $self->{upstream}->read_p($bytes);
}

sub _resolve_drained {
    my $self = shift;
    die "No drain_promise to resolve\n"
	unless my $promise =  defined $self->{drain_promise};
    $promise->resolve;
}

sub _greedily_process {
    my $self = shift;
    my ($p,@promises) = ();

    # Below are all the conditions that might be stopping us from
    # greedily processing some data.
    $p = $self->{fill_promise};    push @promises, $p if $p;
    $p = $self->{drain_promise};   push @promises, $p if $p;

    # Now join the two promises and get a new one. If we're blocking
    # on both input starvation and lack of output space, we have to
    # wait for both of those to get resolved.
    $p = Mojo::Promises->all(@promises);

    $p->then(sub {
	# Step 0: Parse data from promises 
	my ($data, $eof) = @_;	# (only fill_promise returns any data)
	if (defined $data) {
	    # save data, zero-padding if we're at EOF
	    if ($eof) {
		$data .= "\0" while length($data) % $self->{window};
	    }
	    $self->{in_buf} .= $data;
	    $self->{sw}->advance_read(length($data) / $self->{window});
	}

	# Step 1: Process all we can
	my ($read_ok, $process_ok, $write_ok, @bundle_ok);

	$process_ok = $self->{sw}->process_ok; # columns
	my $bytes = $process_ok * $self->{window};
	my $ports = $self->{ports};
	# Stripe input string across output strings
	for (my $i =0; $i < $bytes; ++$i) {
	    $self->{out_bufs}->[$i % $ports] .= substr($self, 0, 1, "")
	}
	$self->{sw}->advance_process($process_ok);

	# Also update in_eof
	$self->{in_eof} = 1 if $eof and $self->{in_buf} eq "";

	# Step 2: Figure out what's blocking us now and make new
	# promises that those blockages will be resolved.

	# Clear out the old (undef/fulfilled) promises
	$self->{fill_promise} = $self->{drain_promise} = undef;

	my ($read_ok, $process_ok, $write_ok, @bundle_ok)
	    = $self->{sw}->can_advance;
	die "Internal error: could process more!" if $process_ok;
	
	# This code should guarantee that two upstream read_p calls
	# can't be active at once (since we need to fulfil the first
	# promise before calling the upstream read_p again)
	if ($read_ok) {
	    $self->{fill_promise} = $self->_promise_to_read($read_ok * $ports);
	}

	# write_ok is the output buffers' fill level (in columns)
	if ($write_ok == $self->{window}) { # if at least one substream is full
	    # This becomes resolved by:
	    # * various new/pending calls to our read_p by downstream readers
	    # * somebody calls _drain_port (via read_p or we do it below)
	    # * the slowest substream eventually advances
	    # * that triggers the callback in the sliding window class
	    # * that callback resolves the promise
	    $self->{drain_promise} = Mojo::Promise->new;
	}


	# Step 3: Schedule next processing chunk (which will wait for
	# our new promises to resolve)
	Mojo::IOLoop->next_tick(sub { $self->_greedily_process });

	# Step 4: "wake up" any pending read_p calls This may cause
	# the drain_promise to become fulfilled, but that shouldn't
	# cause any problems when we get back to the top of this
	# routine in the next tick
	map { $self->_drain_port($_) } (0 .. $ports - 1);
	
	     });
}


    

# Routine to resolve/reject promise returned by read_p
#
# This can be called in two cases:
#
# 1. a fresh read_p comes in that we know we can satisfy
# 2. the internal event loop produces fresh output and sees a promise
#    waiting to be resolved.

sub _drain_port {
    my $self = shift;
    my $port = shift;

    # Pull out [$promise, $bytes]
    my $aref = $self->{out_promises}->{$port};
    my ($promise, $bytes) = @$aref;

    return unless defined $promise;
    
    # compare what was wanted with what's available
    my $sw = $self->{sw};
    my $avail = $sw->can_empty_substream($port);

    # do nothing yet if there's no data available
    return if $avail == 0;

    # or else we resolve the promise below ...
    $bytes = $avail if $bytes == 0;

    # ... so we can delete it from self right now
    $self->{out_promises}->{$port} = [];
    
    # splice data bytes and update sliding window pointers
    my $data = substr($self->{out_bufs}->[$port], 0, $avail, "");

    # Figure out correct EOF flag for this substream/port
    my $eof = 0;
    $eof++ if $self->{in_eof} and $self->{out_bufs}->[$port] eq "";

    # This could trigger a sw callback, which is how the internal
    # algorithm makes progress
    $self->{sw}->advance_substream($port);

    # resolve read_p promise for this substream
    $promise->resolve($data,$eof);    
}

sub read_p {
    my $self = shift;
    my ($bytes,	$port) = @_;

    die "Stripe::read_p requires a 'port' arg\n" unless defined $port;
    die "A read_p on port $port is already pending\n"
	if defined $self->{out_promises}->[$port];

    # prepare and stash the promise, plus bytes requested
    my $promise = $self->{out_promises}->[$port] = Mojo::Promise->new();
    $self->{out_promises}->{$port} = [ $promise, $bytes ];

    if ($self->{sw}->can_empty_substream($port)) {
	Mojo::IOLoop->next_tick(sub { $self -> _drain_port($port) });
    } else {
	# Nothing we can do now; need to wait for algo to fill up the
	# output buffer, at which point *it* calls _drain_port
    }

    $promise;
}


1;
