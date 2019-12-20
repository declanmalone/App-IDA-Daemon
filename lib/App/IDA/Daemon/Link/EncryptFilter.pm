package App::IDA::Daemon::Link::EncryptFilter;

use parent App::IDA::Daemon::Link;

use Role::Tiny::With;

with 'App::IDA::Daemon::Link::Role::Filter';

sub BUILDARGS {
    my ($orig, $self, $args, $errors) = @_;

    warn "EncryptFilter doing BUILDARGS!\n";

    $orig->($self, $args, $errors);
}

sub filter_process {}

1;
