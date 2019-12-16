package App::IDA::Daemon::Link::NullFilter;

use parent App::IDA::Daemon::Link;

use Role::Tiny::With;

with 'App::IDA::Daemon::Link::Role::Filter';

sub filter_process {}

1;
