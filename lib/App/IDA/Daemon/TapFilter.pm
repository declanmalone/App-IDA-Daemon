package App::IDA::Daemon::TapFilter;
use Mojo::Base 'Mojo::EventEmitter';

use warnings;

# Tap into a processing pipeline with an arbitrary callback

sub new {
    my ($class, $source, $read, $close, $callback) = @_;
    unless ($source->isa("Mojo::EventEmitter")) {
	warn "StringSink needs a Mojo::EventEmitter as input\n";
	return undef;
    }
    unless ("CODE" eq ref $callback) {
	warn "callback must be a code reference\n";
	return undef;
    }

    my $self = bless {
	source   => $source,
	read     => $read,
	close    => $close,
	callback => $callback
    }, $class;

    $source->on($read => sub { &$callback(@_) });
    return $self unless defined($close);
    $source->on($close => sub { $self->emit("close") });
    $self;
}

1;
