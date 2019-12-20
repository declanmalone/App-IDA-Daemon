package App::IDA::Daemon::Link::Stripe;

# Note that 'use parent ...::Link' below won't inherit the parent's
# attr/has methods due to them not being lexically declared.
#
# (Mojo::Base monkey patches them into the class instead).

use Mojo::Base 'App::IDA::Daemon::Link';
use Role::Tiny::With;

# This class is a stepping stone to implementing and testing the IDA
# Split module.

# It does most of what the final class will do, including using
# Crypt::IDA to do the striping(*) transform (by using an identity
# matrix as the transform matrix), and using the same input/output
# matrix design. Plus, Crypt::IDA::Algorithm has an embedded
# SlidingWindow class, which we also use here and in +Split.

use Math::FastGF2::Matrix;
use Crypt::IDA::Algorithm;

# There are some things that IDA split will do that this class doesn't
# do:
#
# * take IDA-style parameters to set up (we will only take the number
#   of output streams/ports and the size of the sliding window)
#
# * include a share file header in the streams
#
# The idea is to just ensure that the basic outline of the greedy
# processing loop works as expected together with output streams being
# emptied at different rates. I don't want to be bothered with the
# other IDA features to begin with.

# (*) "Striping", by the way, refers to taking every n'th character
# from the input stream and outputting them in one stream. For
# example, striping a string over four output streams would produce:
#
# input stream: abcdefghijklmnopqrstuvwxyz
#
# output stream 0: aeimquy
# output stream 1: bfjnrvz
# output stream 2: cgkosw\0     (+ null padding at eof)
# output stream 3: dhlptx\0     (+ null padding at eof)


# Attribute/Parameter Handling

# This class will have its own parameters, which will be different
# from the IDA Split class. We can't use the 'around BUILDARGS'
# method because we're not a Role, but we can implement our own
# BUILDARGS routine before composing any other Roles in.
#
# This should result in our BUILDARGS being run (rather than our
# parent's version) as well as having all the composed roles wrap
# around it, too. If Link::BUILDARGS did any special processing, we'd
# have to call it here, too, but it doesn't, so we don't.

# The specific attributes/parameters that we need passed to new:
has [qw(window stripes downstream_ports)];

# These will be used in the algorithm:
has [qw(w k xform_matrix ida_splitter input_eof)];

sub BUILDARGS {
    # we don't get passed $orig
    my ($self, $args, $errors) = @_;
    my ($window, $stripes);

    if (1) {
	warn "self is a " . ref($self) . "\n";
	warn "args is a " . ref($args) . "\n";
	warn "errors is a " . ref($errors) . "\n";

	# Confirm that we're called *after* other roles' BUILDARGS
	warn "Link::Stripe::BUILDARGS() called\n";
	say "self already contained keys: " . join ", ", keys %$self;
    }

    if (!exists $args->{window}) {
	push @$errors, "Stripe: Missing 'window' arg";
    } elsif (!defined ($window = $args->{window})) {
	push @$errors, "Stripe: 'window' arg undefined";
    } elsif ($window <= 0) {
	push @$errors, "Stripe: 'window' not strictly positive";
    } else {
	$self->{window} = $window;
    }

    if (!exists $args->{stripes}) {
	push @$errors, "Stripe: Missing 'stripes' arg";
    } elsif (!defined ($stripes = $args->{stripes})) {
	push @$errors, "Stripe: 'stripes' arg undefined";
    } elsif ($stripes <= 0) {
	push @$errors, "Stripe: 'stripes' not strictly positive";
    } else {
	$self->{stripes} = $stripes;
    }    

    # Do other initialisation iff above args were correct
    if (exists ($self->{window}) and exists ($self->{stripes})) {
	$self->{w} = 1;
	$self->{downstream_ports} = $self->{k} = $stripes;
	my $xform = $self->{xform_matrix} = Math::FastGF2::Matrix
	    -> new_identity (size => $stripes, width => 1,
			     org => "rowwise");
	$self->{ida_splitter} = Crypt::IDA::Algorithm
	    -> splitter(k => $stripes, xform => $xform,
			bufsize => $window);

	# The above also sets up input and output matrices but doesn't
	# give us direct access to them. See Convenience methods
	# directly below.
    }
}

# Convenience methods
sub fill_stream {
    my $algo = shift->{ida_splitter};
    $algo->fill_stream(@_);
}

sub empty_substream {
    my $algo = shift->{ida_splitter};
    $algo->empty_substream(@_);
}

sub split_stream {
    my $algo = shift->{ida_splitter};
    $algo->split_stream(@_);
}

# Define methods required by +Split

# downstream_ports already covered by 'has' declaration above

# +Split needs this to set up the bundle motion callback and to query
# the state of the pointers. We're responsible for advancing the
# pointers, though.
sub sw { $_[0]->{ida_splitter}->{sw} }

# consume the required roles
with 'App::IDA::Daemon::Link::Role::Split';

# I wrote these in +Split first, then moved them here after a
# "reasonable" amount of testing/debugging.

# sub split_process { }
# sub accept_input_columns { }
# sub drain_output_column { }

sub split_process {
    my ($self, $cols, $dataref) = @_;
    my $ports = $self->{downstream_ports};

    # Stripe input col(s) -> output rows
    $self->split_stream($cols);
    return;

    # old version using in/out bufs, manual advance
    # DONE: use matrix operation instead of strings
    # N/A: also need to destreaddle
    my $bytes = $cols * $ports;
    for (my $i =0; $i < $bytes; ++$i) {
	$self->{out_bufs}->[$i % $ports] .=
	    substr($$dataref, 0, 1, "")
    }
    warn "About to advance process by $cols cols\n";
    $self->sw->advance_process($cols) if $cols;
    warn "After calling sw->advance_process\n";
}

sub accept_input_columns {
    my ($self, $data) = @_;

    # we don't even have to destraddle because Algorithm does it
    return $self->fill_stream($data);

    # old version using in buf (which should have advanced read buf,
    # too)
    $self->{in_buf} .= $data;
}

sub drain_output_row {
    my ($self, $port, $bytes) = @_;

    # Algorithm takes care of destraddling and advancing pointers
    return $self->empty_substream($port, $bytes);
    
    # old version using separate out_bufs and manual advance
    my $data = substr($self->{out_bufs}->[$port], 0, $bytes, "");

    # This could trigger a sw callback, which is how the internal
    # algorithm makes progress
    warn "drain_output_row: advance substream $port by $bytes\n";
    $self->sw->advance_write_substream($port, $bytes) if $bytes;
    warn "After advancing\n";

    $data;
 }


1;
