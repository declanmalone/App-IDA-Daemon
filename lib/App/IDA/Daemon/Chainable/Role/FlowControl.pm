package App::IDA::Daemon::Chainable::Role::FlowControl;
use Mojo::Base -role, "Mojo::EventEmitter";

has [qw(ioloop running)];

requires '_do_chunk';

sub stop {
    my $self = shift;
    $self->{running} = 0;
    $self->{upstream} -> stop if defined $self->{upstream};
}

sub start {
    my $self = shift;
    $self->{running} = 1;
    $self->{ioloop}->next_tick(sub { $self->_do_chunk });
    $self->{upstream} -> start if defined $self->{upstream};
}

