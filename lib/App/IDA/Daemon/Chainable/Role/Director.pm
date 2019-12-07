package App::IDA::Daemon::Chainable::Role::Director;
use Mojo::Base -role, "Mojo::EventEmitter";

# A Director ignores flow control (start/stop) messages because it is
# self-governing. That is to say, internally, it:
#
# * sends explicit start/stop method calls upstream
# * subscribes to a downstream element's drain event
sub stop { }


sub start { }
