package App::IDA::Daemon::Link::StringSource;

use parent App::IDA::Daemon::Link;
use Role::Tiny::With;

# The Source role provides the basic processing pattern, but it
# delegates the actual internal stream provision to
# InternalStringSource. (both must be composed at once)

with
    'App::IDA::Daemon::Link::Role::Source',
    'App::IDA::Daemon::Link::Role::InternalStringSource';

# Between the two roles above, we should have all required
# functionality covered, so we don't need to implement anything here.

1;
