package App::IDA::Daemon::Link::Role::Split;

# Split trait (somewhat like a Filter)
use Mojo::Base -role;

use Mojo::IOLoop;
use Mojo::Promise;

use Crypt::IDA::SlidingWindow;

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

## Refactoring

# The consuming class must provide these concrete methods to handle
# the particular buffer operations and split algorithm that it uses.
requires qw(split_process accept_input_columns drain_output_row);

# At this moment of time, the greedy processing loop seems to be
# working, but it's based on code that was using its own buffers and
# the actual striping is done here. I haven't factored out the three
# routines above yet, in other words.

# As a temporary step, I'm going to work on the refactoring here, and
# then I can move the working code into the Stripe class where it
# belongs.

# Recall that this role will be consumed by both Stripe (my "toy"
# feature intended as a testbed) and the full IDA Split classes.  The
# code that I migrate in here to handle Stripe-specific code will have
# to have analoguous code when working with the full IDA class,
# including:
#
# * using input/output matrices (rather than plain string buffers)
# * manually advancing sliding window pointers
# 

sub split_process {
    my ($self, $cols, $dataref) = @_;
    my $ports = $self->{downstream_ports};
    my $bytes = $cols * $ports;
    # Stripe input col(s) -> output rows
    # TODO: use matrix operation instead of strings
    # TODO: also need to destreaddle

    # TODO: we have a bug in the existing code because we're splicing
    # bytes out of $data instead of {in_buf}. Thus we'll never
    # calculate {in_eof} properly.
    for (my $i =0; $i < $bytes; ++$i) {
	$self->{out_bufs}->[$i % $ports] .=
	    substr($$dataref, 0, 1, "")
    }
    warn "About to advance process by $cols cols\n";
    $self->sw->advance_process($cols);
    warn "After calling sw->advance_process\n";
}

sub accept_input_columns {
    my ($self, $data) = @_;
    # TODO: write to matrix. Also, maybe do checks for full column
    # and/or eof padding here
    $self->{in_buf} .= $data;
 }
sub drain_output_row {
    my ($self, $port, $bytes) = @_;
    my $data = substr($self->{out_bufs}->[$port], 0, $bytes, "");

    # This could trigger a sw callback, which is how the internal
    # algorithm makes progress
    warn "Trying to advance substream $port by $bytes\n";
    # XXX once again, advance_substream doesn't exist and we just hang
    # 
    $self->sw->advance_write_substream($port, $bytes);
    warn "After advancing\n";

    $data;
 }



## Internal Attributes

# Internally, the algorithm needs to set up its own variables. In
# other places I have been using BUILDARGS, but it seems easier to use
# 'has' instead.

# I need to keep a list of outstanding promises so that if read_p
# can't satisfy a request, it creates a new promise and takes a note
# of the promise and how many bytes were requested.
#
# Later on, store a new promise in this structure with:
#
# $self->{out_promises}->[$port] = [ $promise, $bytes ]
has out_promises => sub { [] };

# The greedy algorithm relies on maintaining up to two internal
# promises:
#
# fill_promise: promises to give us more input data
# drain_promise: promises to clear space in a full output buffer

has [ qw(fill_promise drain_promise) ] => undef;

# We also track whether the input is at eof. This is distinct from the
# eof value which is returned by read_p because some data may still be
# travelling through the input-process-output pipeline.

has 'in_eof' => 0;

# A bit more info on the algorithm
#
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

# The code below was originally in main. Since we don't have a
# constructor (we're a role), I have to find a way of starting
# _greedily_process.

=for doing in main

    # upstream fulfills the first promise
    $self->{fill_promise} = $self->_promise_to_read($window * $ports);

    # schedule greedy process
    Mojo::IOLoop->next_tick(sub { $self->_greedily_process });

    # Here's how the drain promise will be resolved
    $self->{sw}->cb_write_bundle( sub { $self->_resolve_drained(); });

=cut

# Here's how: do it in read_p. It will check if the processing loop is
# running, and if not start it using the three lines above (and set
# running to 1). Let's factor that out here ...

# Similar to code in +Sink, but keep methods private
has running => 0;
sub _stop { $_[0]->{running} = 0 };
sub _start {
    my $self = shift;
    return if $self->{running}++;
    warn "Starting _greedily_process\n";

    my $window = $self->window           or die;
    my $ports  = $self->downstream_ports or die;

    warn "call _promise_to_read for " . $window * $ports . " bytes\n";
    $self->{fill_promise} = $self->_promise_to_read($window * $ports);

    # schedule greedy process
    Mojo::IOLoop->next_tick(sub { $self->_greedily_process });

    # Here's how the drain promise will be resolved
    $self->sw->cb_wrote_bundle( sub { $self->_resolve_drained(); });
}


sub _promise_to_read {
    my ($self, $bytes) = @_;
    warn "_promise_to_read looking for $bytes bytes\n";
    my $rc = $self->{upstream_object}->read_p($self->{upstream_port}, $bytes);
    warn "upstream object->read_p returned a " . ref ($rc) . "\n";
    $rc;
}

sub _resolve_drained {
    my $self = shift;
    die "No drain_promise to resolve\n"
	unless defined(my $promise = $self->{drain_promise});
    warn "Resolving drain_promise\n";
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
    $p = Mojo::Promise->all(@promises);

    $p->then(sub {
	# Step 0: Parse data from promises
	
	# TODO: I should have 'my ($p1,$p2) = @_' because the return
	# value from Promise->all will be ([]) or ([],[]). I need to
	# change 'if (defined $data)' too... (see next XXX)
	# 
	my ($data, $eof) = @_;	# (only fill_promise returns any data)
	warn "_greedily_process promise(s) resolved\n";
	if (defined $data) {
	    warn "data is defined (we fulfilled a fill_promise)\n";
	    # XXX $data that's returned is an ARRAY!
	    # Need to flatten it
	    $data = $data->[0];
	    warn "Data is '$data'\n";
	    # save data, zero-padding if we're at EOF
	    if ($eof) {
		$data .= "\0" while length($data) % $self->{downstream_ports};
		warn "Did padding at eof\n";
	    }
	    # TODO: handle length($data) % downstream_ports != 0

	    # We can't use a state variable declaration here since
	    # we're in an anonymous sub that only gets called once, so
	    # we have to add a new object attribute to store data that
	    # doesn't fill a full column.

	    # We need to work with full columns because that's a
	    # restriction imposed by our use of SlidingWindow.

	    # idea: track number of input bytes read and return that
	    # value + 1 as eof. This would enable a truly stream-based
	    # IDA split routine to report this value back to its
	    # caller and have it saved so that a later combine step
	    # can use that value to know how many padding bytes to
	    # remove/ignore at the end.  (currently, my IDA does use a
	    # streaming *process*, but essentially it's file-based,
	    # since the splitter has to be told in advance how large
	    # the file is so that it can prepend the correct header
	    # info). Anyway, tracking bytes read only adds a tiny bit
	    # of overhead, and returning extra information in the eof
	    # field is practically a zero-cost abstraction, assuming
	    # that we need to return a true value of eof anyway.

	    # Refactor: call delegated method (DONE)
	    $self->accept_input_columns($data);

	    warn "self->window is $self->{window}\n";
	    warn "Trying to call sw->advance_read\n";
	    # XXX we get stuck here (fixed)
	    my $amount = length($data) / $self->{downstream_ports};
	    warn "Maybe get stuck trying to advance_read by $amount cols?\n";
	    $self->sw->advance_read(length($data) / $self->{downstream_ports});
	    warn "After calling sw->advance_read\n";
	}

	# Step 1: Process all we can
	my ($read_ok, $process_ok, $write_ok, @bundle_ok)
	    = $self->sw->can_advance;

	warn "We can process $process_ok columns\n";

	# Refactor: call delegated method (DONE)
	my $cols = $process_ok;
	# TODO: don't send \$data 
	$self->split_process($cols, \$data);
	# This was moved into sub, but we need the variable here too
	my $ports = $self->{downstream_ports};
	
	# BUG: Two bugs, actually wrong semantics and {in_buf} will
	# never empty.
	# The fix for the first is to just set in_eof if eof.
	# We also need to consult in_eof when draining the out_bufs.
	# That combination will give in_eof the right semantics.
	$self->{in_eof} = 1 if $eof and $self->{in_buf} eq "";

	# Step 2: Figure out what's blocking us now and make new
	# promises that those blockages will be resolved.

	# Clear out the old (undef/fulfilled) promises
	$self->{fill_promise} = $self->{drain_promise} = undef;

	($read_ok, $process_ok, $write_ok, @bundle_ok)
	    = $self->sw->can_advance;
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
	    warn "Output buffer full; need drain_promise\n";
	    $self->{drain_promise} = Mojo::Promise->new;
	}


	# Step 3: Schedule next processing chunk (which will wait for
	# our new promises to resolve)
	warn "Scheduling next loop of _greedily_process\n";
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
    my ($self, $port) = @_;

    # Pull out [$promise, $bytes]
    my $aref = $self->{out_promises}->[$port];
    my ($promise, $bytes) = @$aref;

    warn "Checking if drain promise exists...\n";
    return unless defined $promise;
    warn "Yes it does! ($promise for $bytes byte(s))\n";

    # compare what was wanted with what's available
    my $sw = $self->sw;
    my $avail = $sw->can_empty_substream($port);

    warn "Currently $avail byte(s) available\n";

    # do nothing yet if there's no data available
    return if $avail == 0;

    # or else we resolve the promise below ...
    $bytes = $avail if $bytes == 0;

    # ... so we can delete it from self now (it's in $promise)
    $self->{out_promises}->[$port] = undef;

    # Refactor: call delegated method (TODOs below)
    # splice data bytes and update sliding window pointers

    # delegate the data and sliding window tasks, but keep eof and
    # promise handling here (renamed to drain_output_row)
    my $data = $self->drain_output_row($port, $bytes);

    # Figure out correct EOF flag for this substream/port
    # TODO: rewrite with new logic:
    # if in_eof and (input buffer empty) and (this output row empty)

    # TODO: add feature to SlidingWindow to return fill levels
    # required to implement the above (if it doesn't already have
    # it).

    # TODO: We shouldn't be looking at {out_bufs} here.

    my $eof = 0;
    $eof++ if $self->{in_eof} and $self->{out_bufs}->[$port] eq "";

    # resolve read_p promise for this substream
    $promise->resolve($data,$eof);    
}

sub read_p {
    my ($self, $port, $bytes) = @_;

    warn "+Split: upstream_object is " .  $self->{upstream_object} . "\n";
    warn "+Split: upstream_port is "   .  $self->{upstream_port}   . "\n";

    die "Stripe::read_p requires a 'port' arg\n" unless defined $port;
    die "A read_p on port $port is already pending\n"
	if defined $self->{out_promises}->[$port];

    # start the greedy processing loop if it's not running
    $self->_start if !$self->{running};

    # prepare and stash the promise, plus bytes requested
    my $promise = $self->{out_promises}->[$port] = Mojo::Promise->new();
    $self->{out_promises}->[$port] = [ $promise, $bytes ];

    if ($self->sw->can_empty_substream($port)) {
	Mojo::IOLoop->next_tick(sub { $self -> _drain_port($port) });
    } else {
	# Nothing we can do now; need to wait for algo to fill up the
	# output buffer, at which point *it* calls _drain_port
    }

    $promise;
}


1;
