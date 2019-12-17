package App::IDA::Daemon::Link::Stripe;

use parent App::IDA::Daemon::Link;
use Role::Tiny::With;

use v5.10;

# This class is a stepping stone to implementing and testing the IDA
# Split module.
#
# It does most of what the final class will do, including using
# Crypt::IDA to do the striping(*) transform (by using an identity
# matrix as the transform matrix), and using the same input/output
# matrix design.
#
# There are some things that IDA split will do that this class doesn't
# do:
#
# * take IDA-style parameters to set up (we will only take the number
#   of output streams/ports)
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

# The specific attributes/parameters that we need:
has qw(window downstream_ports);

sub BUILDARGS {
    # we don't get passed $orig
    my ($self, $args, $errors) = @_;

    warn "self is a " . ref($self) . "\n";
    warn "args is a " . ref($args) . "\n";
    warn "errors is a " . ref($errors) . "\n";

    # Confirm that we're called after other roles' BUILDARGS
    warn "Link::Stripe::BUILDARGS() called\n";
    say "self already contained keys: " . join ", ", keys %$self;
    
}

# consume the required roles
with 'App::IDA::Daemon::Link::Role::Split';

# This sub will be called whenever there's new data that can be put
# into the input matrix and there's free space to write the
# transformed data into the output matrix.
sub split_process {

}

1;
