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



1;
