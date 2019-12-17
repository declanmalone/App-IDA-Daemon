package App::IDA::Daemon::Link::Stripe;

# Note that 'use parent ...::Link' won't inherit the parent's attr/has
# methods due to them not being lexically declared.
# (Mojo::Base monkey patches them into the class instead).

use Mojo::Base 'App::IDA::Daemon::Link';
use Role::Tiny::With;

# This class is a stepping stone to implementing and testing the IDA
# Split module.

# It does most of what the final class will do, including using
# Crypt::IDA to do the striping(*) transform (by using an identity
# matrix as the transform matrix), and using the same input/output
# matrix design.

use Math::FastGF2::Matrix;
use Crypt::IDA;

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
has [qw(window stripes)];

# These will be used in the algorithm:
has [qw(w k xform_matrix ida_splitter input_eof)];

sub BUILDARGS {
    # we don't get passed $orig
    my ($self, $args, $errors) = @_;

    my ($window, $stripes);
    
    warn "self is a " . ref($self) . "\n";
    warn "args is a " . ref($args) . "\n";
    warn "errors is a " . ref($errors) . "\n";

    # Confirm that we're called *after* other roles' BUILDARGS
    warn "Link::Stripe::BUILDARGS() called\n";
    say "self already contained keys: " . join ", ", keys %$self;

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

    }
}

# consume the required roles
with 'App::IDA::Daemon::Link::Role::Split';

# This sub will be called whenever there's new data that can be put
# into the input matrix and there's free space to write the
# transformed data into the output matrix.
sub split_process {

}

1;
