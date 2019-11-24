package App::IDA::Daemon::StringSink;
use Mojo::Base 'Mojo::EventEmitter';

use warnings;

# A simple string sink to go at the end of a processing pipeline

sub new {
    my ($class, $source, $read, $close, $strref) = @_;
    unless ($source->isa("Mojo::EventEmitter")) {
	warn "StringSink needs a Mojo::EventEmitter as input\n";
	return undef;
    }
    unless ("SCALAR" eq ref $strref) {
	warn "strref must be a reference to a scalar\n";
	return undef;
    }

    my $self = bless {
	source => $source,
	read   => $read,
	close  => $close,
	strref => $strref
    }, $class;

    $source->on($read => sub { $$strref .= $_[1] });
    return $self unless defined($close);
    $source->on($close => 
		sub {
		    $self->emit("close" => $$strref)
		});
    $self;
}

sub to_string { ${$_[0]->{strref}} }

1;
